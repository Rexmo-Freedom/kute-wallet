import 'package:hive_ce/hive.dart';
import 'package:kute/models/swap_order_model.dart';

/// Capture before starting a quote. Wiping this wallet invalidates the scope,
/// including requests that have not reached their persistence step yet.
class PendingReceiveQuoteScope {
  const PendingReceiveQuoteScope._(this.walletId, this._all, this._wallet);

  final String walletId;
  final int _all;
  final int _wallet;
}

/// Quoted receive instructions remain discoverable after their screen closes.
/// Expiry ends the displayed price guarantee, not observation of late funding.
class PendingReceiveQuoteCache {
  PendingReceiveQuoteCache._();

  static const boxName = 'pending_receive_quotes_v1';
  static Future<Box<SwapOrder>>? _opening;
  static Future<void> _mutationTail = Future<void>.value();
  static int _allGeneration = 0;
  static final _walletGenerations = <String, int>{};

  static PendingReceiveQuoteScope capture(String walletId) =>
      PendingReceiveQuoteScope._(
          walletId, _allGeneration, _walletGenerations[walletId] ?? 0);

  static bool isCurrent(PendingReceiveQuoteScope scope) =>
      scope._all == _allGeneration &&
      scope._wallet == (_walletGenerations[scope.walletId] ?? 0);

  static Future<void> _mutate(Future<void> Function() action) {
    final next = _mutationTail.then((_) => action());
    // A failed write reaches its caller without poisoning later cleanup.
    _mutationTail = next.catchError((Object _) {});
    return next;
  }

  static Future<Box<SwapOrder>> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<SwapOrder>(boxName);
    return _opening ??=
        Hive.openBox<SwapOrder>(boxName).whenComplete(() => _opening = null);
  }

  /// Await this write before making a new address available to its payer.
  static Future<void> save({
    required SwapOrder display,
    required DateTime expiresAt,
    required PendingReceiveQuoteScope scope,
  }) =>
      _mutate(() async {
        void checkScope() {
          if (scope.walletId != display.walletId || !isCurrent(scope)) {
            throw StateError('Receive wallet was cleared');
          }
        }

        checkScope();
        final record = display.copyWith(
          expiresAt: expiresAt.toUtc().millisecondsSinceEpoch,
        );
        if (!_valid(record)) throw StateError('Invalid receive quote');
        final box = await _box();
        checkScope();
        final previous = box.get(record.id);
        if (previous != null && !_sameInstructions(previous, record)) {
          throw StateError('Receive quote instructions changed');
        }
        await box.put(record.id, record);
        // Also flush a repeated save: a previous flush could have failed after
        // Hive updated its in-memory value.
        await box.flush();
        checkScope();
      });

  static Future<List<SwapOrder>> pending() async {
    await _mutationTail;
    final box = await _box();
    return box.values.where(_valid).toList(growable: false);
  }

  /// Only after its real order has been durably added to normal order tracking.
  static Future<void> complete(String quoteId) => _mutate(() async {
        final box = await _box();
        await box.delete(quoteId);
        await box.flush();
      });

  static Future<void> deleteForWallet(String walletId) {
    _walletGenerations[walletId] = (_walletGenerations[walletId] ?? 0) + 1;
    return _mutate(() async {
      final box = await _box();
      await box.deleteAll([
        for (final key in box.keys)
          if (box.get(key)?.walletId == walletId) key,
      ]);
      await box.flush();
    });
  }

  /// Fence requests synchronously, then drain earlier writes before deleting.
  /// A restored wallet starts new requests with a freshly captured scope.
  static Future<void> clear() {
    _allGeneration++;
    return _mutate(() async {
      final opening = _opening;
      if (opening != null) {
        try {
          await opening;
        } catch (_) {
          // Still remove any partially opened box from disk.
        }
      }
      await Hive.deleteBoxFromDisk(boxName);
    });
  }

  static bool _valid(SwapOrder record) =>
      record.id.startsWith('q_') &&
      record.id.length > 2 &&
      record.providerName == 'Orchestra' &&
      (record.walletId?.isNotEmpty ?? false) &&
      record.networkFrom.isNotEmpty &&
      record.coinFrom.isNotEmpty &&
      record.networkTo.toLowerCase() == 'spark' &&
      const {'BTC', 'USDB'}.contains(record.coinTo.toUpperCase()) &&
      record.depositAddress.isNotEmpty &&
      record.withdrawalAddress.isNotEmpty &&
      record.refundAddress.isNotEmpty &&
      record.expiresAt != null;

  static bool _sameInstructions(SwapOrder a, SwapOrder b) =>
      a.id == b.id &&
      a.walletId == b.walletId &&
      a.networkFrom == b.networkFrom &&
      a.coinFrom == b.coinFrom &&
      a.networkTo == b.networkTo &&
      a.coinTo == b.coinTo &&
      a.depositAddress == b.depositAddress &&
      a.depositExtraId == b.depositExtraId &&
      a.depositAmount == b.depositAmount &&
      a.withdrawalAddress == b.withdrawalAddress &&
      a.refundAddress == b.refundAddress &&
      a.refundExtraId == b.refundExtraId &&
      a.expiresAt == b.expiresAt;
}
