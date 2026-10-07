import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// Persists the **at-the-time** USD value of a transaction the first moment it
/// appears, so we can later show what it was worth then vs now (gain/loss) and
/// convert to any display currency from the stored USD.
///
/// We store USD (not the user's currency) so a later currency change still
/// works, and we store the BTC/USD price + sats so the value can be re-derived
/// and compared. The snapshot is written ONCE per txid and never overwritten —
/// it's a historical record.
///
/// Applies to: Outlogic orders, on-chain/Lightning/Spark receives & sends, and
/// Polymarket deposits/withdrawals. For onramp orders that already know the
/// exact fiat paid (Outlogic), pass that USD directly via [recordUsd]; for the
/// rest, pass the current BTC/USD price via [recordFromBtcPrice].
class TxFiatSnapshotService {
  static const String boxName = 'tx_fiat_snapshot';

  static Box<String>? get _box {
    try {
      return Hive.box<String>(boxName);
    } catch (_) {
      return null;
    }
  }

  /// Record `sats` valued at [btcUsdPrice] for [txid], once. No-op if already
  /// recorded or inputs are invalid.
  static void recordFromBtcPrice(String txid, int sats, double btcUsdPrice) {
    if (sats <= 0 || btcUsdPrice <= 0) return;
    final usd = (sats / 100000000.0) * btcUsdPrice;
    _record(txid, usd: usd, sats: sats, btcUsdPrice: btcUsdPrice);
  }

  /// Record a known USD value directly (e.g. the exact fiat paid on an Outlogic
  /// purchase). [sats] is the BTC amount the order delivered, used for the
  /// current-value comparison.
  static void recordUsd(String txid, double usd, int sats) {
    if (usd <= 0) return;
    final btcUsdPrice =
        sats > 0 ? usd / (sats / 100000000.0) : 0.0;
    _record(txid, usd: usd, sats: sats, btcUsdPrice: btcUsdPrice);
  }

  static void _record(String txid,
      {required double usd, required int sats, required double btcUsdPrice}) {
    final box = _box;
    if (box == null || txid.isEmpty) return;
    final key = txid.toLowerCase();
    if (box.containsKey(key)) return; // historical — never overwrite
    box.put(
      key,
      jsonEncode({
        'usd': usd,
        'sats': sats,
        'btc_usd': btcUsdPrice,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// The stored snapshot for [txid], or null if none.
  static TxFiatSnapshot? snapshot(String txid) {
    final box = _box;
    if (box == null || txid.isEmpty) return null;
    final raw = box.get(txid.toLowerCase());
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return TxFiatSnapshot(
        usd: (m['usd'] as num?)?.toDouble() ?? 0,
        sats: (m['sats'] as num?)?.toInt() ?? 0,
        btcUsdPrice: (m['btc_usd'] as num?)?.toDouble() ?? 0,
        timestampMs: (m['ts'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class TxFiatSnapshot {
  /// USD value at the moment the tx was first seen.
  final double usd;

  /// BTC amount (sats) the value was based on.
  final int sats;

  /// BTC/USD price at snapshot time.
  final double btcUsdPrice;
  final int timestampMs;

  const TxFiatSnapshot({
    required this.usd,
    required this.sats,
    required this.btcUsdPrice,
    required this.timestampMs,
  });

  /// Current USD value of the same sats at [currentBtcUsd].
  double currentUsd(double currentBtcUsd) =>
      (sats / 100000000.0) * currentBtcUsd;

  /// Signed % change of the value from snapshot to now. Positive = up.
  double changePct(double currentBtcUsd) {
    if (usd <= 0) return 0;
    return (currentUsd(currentBtcUsd) - usd) / usd * 100.0;
  }
}
