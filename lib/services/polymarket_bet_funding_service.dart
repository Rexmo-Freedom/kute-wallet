// Per-bet funding-currency tracker. At bet-place time we record
// whether the user funded the buy from BTC or from existing USDC.
// On sell / claim / auto-claim, the redeem flow reads the tag and
// auto-routes the proceeds back to the original asset (BTC funding
// → trigger an Orchestra USDC.e → BTC sweep on the credited delta).
//
// Why per-conditionId (not per-orderId): the user can place multiple
// orders on the same market over time, and they all redeem against
// the same conditionId. The funding source for the FIRST buy is the
// one we honour on resolve — subsequent top-ups inherit the same
// destination. Simple and matches user intent ("I bet from my BTC,
// I expect to get BTC back").
//
// See `project_bet_source_currency` memory for the broader plan
// including the 5-min fast-market WS hook.

import 'package:hive_ce/hive.dart';

/// Asset the user funded a bet from. Stored as the raw enum name in
/// Hive so the data file is human-readable for debugging.
enum BetFundingSource {
  btc,
  usdc,
}

class PolymarketBetFundingService {
  static const _boxName = 'polymarket_bet_funding';
  static Box<String> get _box => Hive.box<String>(_boxName);

  /// Record that the bet on [conditionId] was funded from [source].
  /// First write wins — later writes for the same condition are
  /// ignored so a user who tops up a winning position from a
  /// different asset doesn't accidentally re-route the existing
  /// stake away from its original currency. Idempotent.
  ///
  /// `marketTitle` is purely diagnostic — kept in the stored row so
  /// the user-facing copy can read "Routed to Bitcoin" without
  /// another lookup, and so a dev inspecting the Hive box can sanity-
  /// check the tag corresponds to the right bet.
  static Future<void> tag({
    required String conditionId,
    required BetFundingSource source,
    String? marketTitle,
  }) async {
    if (conditionId.isEmpty) return;
    if (_box.containsKey(conditionId)) return;
    final payload =
        '${source.name}|${DateTime.now().millisecondsSinceEpoch}|${marketTitle ?? ''}';
    await _box.put(conditionId, payload);
  }

  /// Read the funding source for [conditionId]. Returns null when
  /// no tag exists (bet placed pre-feature, or never recorded).
  /// Callers should default to "leave proceeds as USDC" on null so
  /// the auto-sweep path stays opt-in.
  static BetFundingSource? read(String conditionId) {
    if (conditionId.isEmpty) return null;
    final raw = _box.get(conditionId);
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.isEmpty) return null;
    return switch (parts.first) {
      'btc' => BetFundingSource.btc,
      'usdc' => BetFundingSource.usdc,
      _ => null,
    };
  }

  /// True when [conditionId] was BTC-funded — convenience accessor
  /// for the post-redeem auto-sweep gate. Cheap to call repeatedly.
  static bool isBtcFunded(String conditionId) =>
      read(conditionId) == BetFundingSource.btc;

  /// Clear the tag once the position has been fully settled and
  /// swept. Called from the redeem path after a successful claim +
  /// sweep so the box doesn't grow unbounded. Idempotent.
  static Future<void> clear(String conditionId) async {
    if (conditionId.isEmpty) return;
    await _box.delete(conditionId);
  }

  /// Box opener for app boot. Call once during Hive init alongside
  /// the other Polymarket boxes. Safe to call multiple times.
  static Future<void> ensureOpen() async {
    if (Hive.isBoxOpen(_boxName)) return;
    await Hive.openBox<String>(_boxName);
  }
}
