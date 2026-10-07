// lib/providers/ledger/ledger_hyperliquid_activity_provider.dart
//
// Hyperliquid activity for one Ledger wallet, keyed by wallet ID and bound
// to the device-verified EVM address. Mirrors what the main screen does
// for the spending account (`hyperliquidUserFillsProvider` for the REST
// read and 60 s poll, `hyperliquidUserEventsProvider` for the websocket):
//
//   * a REST read of the address's fills first,
//   * the address-keyed `userFills` and `orderUpdates` websocket channels
//     (no auth, nothing signed) for live rows,
//   * a 60 s poll as the reconciliation backstop.
//
// A live fill or order update also invalidates `ledgerHlAccountProvider`
// so positions, balances and open orders move with it. Read only.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';

/// Newest first, capped so the tab stays a feed, not a full history.
const int kLedgerHlMaxFills = 200;

class LedgerHlFillsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<HlFill>, String> {
  HyperliquidWebSocket? _ws;
  StreamSubscription<HlWsMessage>? _sub;
  Timer? _poll;
  Timer? _retryTimer;
  int _retryAttempts = 0;
  bool _connecting = false;
  bool _disposed = false;
  String? _address;

  @override
  Future<List<HlFill>> build(String walletId) async {
    ref.onDispose(_cleanup);
    _disposed = false;
    final identity = ref.watch(ledgerIdentityProvider(walletId));
    if (identity == null ||
        identity.walletId != walletId ||
        !identity.hasVerifiedEvm) {
      return const [];
    }
    final address = identity.evmAddress!;
    _address = address;
    _poll = Timer.periodic(
        const Duration(seconds: 60), (_) => unawaited(_refresh(address)));
    unawaited(_connect(address));
    final fills =
        await ref.read(ledgerHyperliquidModelProvider).getUserFills(address);
    return _sorted(fills);
  }

  void _cleanup() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _poll?.cancel();
    _poll = null;
    _ws?.dispose();
    _ws = null;
    _address = null;
    _retryAttempts = 0;
    _connecting = false;
  }

  Future<void> _refresh(String address) async {
    if (_disposed || _address != address) return;
    try {
      final fills =
          await ref.read(ledgerHyperliquidModelProvider).getUserFills(address);
      if (_disposed || _address != address) return;
      state = AsyncData(_sorted(fills));
    } catch (_) {
      // Keep the last good list; the next tick or the tab's retry re-reads.
    }
  }

  Future<void> _connect(String address) async {
    if (_connecting || _ws != null) return;
    _connecting = true;
    try {
      final ws = HyperliquidWebSocket();
      _ws = ws;
      ws.subscribeUser(address);
      // onError is mandatory: the socket stream forwards failures and a
      // missing handler would surface as a fatal crash (see the socket's
      // header comment).
      _sub = ws.messages.listen(
        (msg) => _onMessage(address, msg),
        onError: (Object e, StackTrace st) => _tearDownAndRetry(),
        onDone: _tearDownAndRetry,
      );
      await ws.connect();
      _retryAttempts = 0;
    } catch (_) {
      _tearDownAndRetry();
    } finally {
      _connecting = false;
    }
  }

  void _tearDownAndRetry() {
    _sub?.cancel();
    _sub = null;
    _ws?.dispose();
    _ws = null;
    final address = _address;
    if (_disposed || address == null) return;
    if (_retryAttempts >= 5) return;
    _retryTimer?.cancel();
    final delay = Duration(seconds: 5 * (_retryAttempts + 1));
    _retryTimer = Timer(delay, () {
      _retryAttempts++;
      final addr = _address;
      if (!_disposed && addr != null) unawaited(_connect(addr));
    });
  }

  void _onMessage(String address, HlWsMessage msg) {
    if (_disposed || _address != address) return;
    if (msg is HlUserFillsMessage) {
      // The subscribe-time snapshot is history the REST read already
      // holds; only live frames change the list.
      if (msg.isSnapshot || msg.fills.isEmpty) return;
      // While the first REST read is still pending its result would
      // overwrite a merge; that read (or the poll) carries the fill.
      final current = state.valueOrNull;
      if (current != null) state = AsyncData(_merge(current, msg.fills));
      ref.invalidate(ledgerHlAccountProvider(arg));
    } else if (msg is HlOrderUpdatesMessage) {
      if (msg.updates.isEmpty) return;
      // Placed, filled or cancelled: the open orders list moved.
      ref.invalidate(ledgerHlAccountProvider(arg));
    }
  }

  static String _key(HlFill f) => '${f.hash}:${f.tradeId ?? f.oid}:${f.time}';

  static List<HlFill> _sorted(List<HlFill> fills) {
    final sorted = [...fills]..sort((a, b) => b.time.compareTo(a.time));
    return sorted.length > kLedgerHlMaxFills
        ? sorted.sublist(0, kLedgerHlMaxFills)
        : sorted;
  }

  static List<HlFill> _merge(List<HlFill> current, List<HlFill> incoming) {
    final seen = current.map(_key).toSet();
    final fresh = incoming.where((f) => seen.add(_key(f))).toList();
    if (fresh.isEmpty) return current;
    return _sorted([...fresh, ...current]);
  }
}

/// Fills for the Ledger wallet's verified address: REST first, websocket
/// live, 60 s poll. Empty until the Ethereum identity is paired.
final ledgerHlFillsProvider = AsyncNotifierProvider.autoDispose
    .family<LedgerHlFillsNotifier, List<HlFill>, String>(
  LedgerHlFillsNotifier.new,
);
