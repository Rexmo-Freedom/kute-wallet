import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:kute/models/onchain_types.dart';

typedef OnchainTransport = Future<Object?> Function(
    String method, Map<String, Object?> arguments);

/// Safe error categories only. SDK errors can contain descriptors or keys.
class OnchainException implements Exception {
  final String code;
  const OnchainException(this.code);

  @override
  String toString() => switch (code) {
        'insufficient_funds' =>
          'Insufficient balance for the amount and network fee.',
        'invalid_address' => 'Address is invalid',
        'invalid_amount' => 'Amount is below the network minimum.',
        'invalid_fee_rate' => 'That fee rate cannot build this transaction.',
        'timeout' => 'Wallet request timed out. It may still be completing.',
        'busy' =>
          'The wallet is still completing a request. Please try again later.',
        'wallet_open_failed' =>
          'Could not open the wallet. Its saved data was preserved.',
        'wallet_mismatch' =>
          'Wallet configuration does not match the open wallet.',
        'unsupported' =>
          'Native Bitcoin support is unavailable on this platform.',
        _ => 'Could not complete the wallet request.',
      };
}

/// Keeps the existing settings key and custom Electrum endpoints working.
class OnchainEndpoint {
  final String kind;
  final String url;
  const OnchainEndpoint(this.kind, this.url);

  /// Blockstream's public Electrum servers. Electrum is the default over
  /// Esplora: the BDK Esplora client has no request timeout, so one stalled
  /// connection holds the wallet's single native slot until the app
  /// restarts, while the Electrum client gives up after ten seconds and
  /// the fallback host takes over.
  static const defaultMainnet = 'electrum.blockstream.info:50002';
  static const defaultTestnet = 'electrum.blockstream.info:60002';

  factory OnchainEndpoint.fromStored(String value, {bool testnet = false}) {
    final node = value.trim();
    if (node.isEmpty) {
      return OnchainEndpoint(
          'electrum', 'ssl://${testnet ? defaultTestnet : defaultMainnet}');
    }
    if (node == 'https://blockstream.info/api') {
      return OnchainEndpoint(
          'esplora',
          testnet
              ? 'https://blockstream.info/testnet/api'
              : 'https://blockstream.info/api');
    }
    final uri = Uri.tryParse(node);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      return OnchainEndpoint('esplora', node.replaceFirst(RegExp(r'/+$'), ''));
    }
    return OnchainEndpoint(
        'electrum', node.contains('://') ? node : 'ssl://$node');
  }
}

class NativeWalletSession {
  final NativeOnchainService service;
  final String walletId;
  final String sessionId;
  final bool isNewWallet;
  final bool temporary;
  OnchainSnapshot snapshot;
  bool _closed = false;
  bool _closing = false;
  bool _completedFullScan = false;
  bool get needsInitialScan => isNewWallet && !_completedFullScan;

  NativeWalletSession._(this.service, this.walletId, this.sessionId,
      this.isNewWallet, this.temporary, this.snapshot);

  Future<void> sync({bool fullScan = false}) =>
      service.sync(this, fullScan: fullScan);

  Future<Object?> call(String method, Map<String, Object?> arguments,
          {Duration timeout = const Duration(seconds: 30)}) =>
      service.call(this, method, arguments, timeout: timeout);

  Future<void> close({bool deleteTemporary = false}) =>
      service.close(this, deleteTemporary: deleteTemporary);
}

class _PendingScan {
  final bool fullScan;
  final Future<void> actual;
  final Future<void> visible;
  _PendingScan(this.fullScan, this.actual, this.visible);
}

/// Native owns every mutable BDK object. Dart receives immutable snapshots.
///
/// A UI timeout NEVER releases admission: only the actual platform reply does.
/// This matters because a blocking Rust network call cannot be cancelled safely.
class NativeOnchainService {
  static final instance = NativeOnchainService();
  static const channel = MethodChannel('com.kutewallet.app/onchain');
  final OnchainTransport _transport;
  final Duration syncTimeout;
  final Duration fullScanTimeout;
  final int maxPending;
  int _pending = 0;
  final _opening = <String, Future<NativeWalletSession>>{};
  final _identities = <String, String>{};
  final _sessions = <String, NativeWalletSession>{};
  final _active = <String, Future<Object?>>{};
  final _scans = <String, _PendingScan>{};
  final _closing = <String, Future<void>>{};
  final _retired = <String>{};
  final _reservations = <String, int>{};
  bool _closingAll = false;

  NativeOnchainService({
    OnchainTransport? transport,
    this.syncTimeout = const Duration(seconds: 60),
    this.fullScanTimeout = const Duration(minutes: 5),
    this.maxPending = 16,
  }) : _transport = transport ??
            ((method, args) => channel.invokeMethod<Object?>(method, args));

  Future<Object?> _invoke(
      String method, Map<String, Object?> args, Duration timeout) async {
    if (_pending >= maxPending) throw const OnchainException('busy');
    _pending++;
    try {
      return await _transport(method, {
        ...args,
        'deadlineMs': DateTime.now().add(timeout).millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      throw const OnchainException('unsupported');
    } on PlatformException catch (error) {
      const allowed = {
        'invalid_request',
        'wallet_open_failed',
        'wallet_mismatch',
        'network',
        'insufficient_funds',
        'invalid_address',
        // Named build refusals. Native used to collapse every failure that
        // was not InsufficientFunds into 'invalid_transaction'; these two
        // carry a reason the person can act on and the send flow already
        // has copy for both.
        'invalid_amount',
        'invalid_fee_rate',
        'invalid_transaction',
        'busy',
        'timeout',
        'unsupported',
        'internal'
      };
      throw OnchainException(
          allowed.contains(error.code) ? error.code : 'internal');
    } finally {
      _pending--;
    }
  }

  Future<T> _visible<T>(Future<T> actual, Duration timeout) =>
      actual.timeout(timeout,
          onTimeout: () => throw const OnchainException('timeout'));

  Future<Object?> primitive(String method, Map<String, Object?> args) {
    const allowed = {'mnemonic', 'derive', 'inspectPsbt'};
    if (!allowed.contains(method)) {
      return Future.error(const OnchainException('invalid_request'));
    }
    const timeout = Duration(seconds: 30);
    return _visible(_invoke(method, args, timeout), timeout);
  }

  Future<NativeWalletSession> open({
    required String walletId,
    required String dbPath,
    required String descriptor,
    required String changeDescriptor,
    required String network,
    required OnchainEndpoint endpoint,
    bool temporary = false,
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (_closingAll ||
        _closing.containsKey(walletId) ||
        _retired.contains(walletId)) {
      return Future.error(const OnchainException('busy'));
    }
    final args = <String, Object?>{
      'walletId': walletId,
      'dbPath': dbPath,
      'descriptor': descriptor,
      'changeDescriptor': changeDescriptor,
      'network': network,
      'backendKind': endpoint.kind,
      'backendUrl': endpoint.url,
      'temporary': temporary
    };
    // Retain only a digest for identity comparisons, never a second secret copy.
    final identity = sha256.convert(utf8.encode(jsonEncode(args))).toString();
    if (_identities.containsKey(walletId) &&
        _identities[walletId] != identity) {
      return Future.error(const OnchainException('wallet_mismatch'));
    }
    final session = _sessions[walletId];
    if (session != null) return Future.value(session);
    final pending = _opening[walletId];
    if (pending != null) return _visible(pending, timeout);
    _identities[walletId] = identity;
    final actual = _invoke('open', args, timeout).then((value) {
      final map = Map<String, Object?>.from(value! as Map);
      final session = NativeWalletSession._(
          this,
          walletId,
          map['sessionId']! as String,
          map['isNewWallet']! as bool,
          temporary,
          OnchainSnapshot.fromMap(map['snapshot']));
      _sessions[walletId] = session;
      return session;
    }).whenComplete(() {
      _opening.remove(walletId);
      if (!_sessions.containsKey(walletId)) _identities.remove(walletId);
    });
    _opening[walletId] = actual;
    return _visible(actual, timeout).catchError((Object error) {
      // A temporary open can finish after its caller timed out. Its session
      // still needs releasing even though recovery never received the token.
      if (temporary && error is OnchainException && error.code == 'timeout') {
        unawaited(actual
            .then((session) => close(session, deleteTemporary: true))
            .catchError((Object _) {}));
      }
      throw error;
    });
  }

  Future<Object?> _start(NativeWalletSession session, String method,
      Map<String, Object?> args, Duration timeout) {
    if (session._closed ||
        (session._closing && method != 'close') ||
        !identical(_sessions[session.walletId], session)) {
      return Future.error(const OnchainException('wallet_mismatch'));
    }
    if (_active.containsKey(session.walletId)) {
      return Future.error(const OnchainException('busy'));
    }
    late Future<Object?> actual;
    actual = _invoke(
            method,
            {
              'walletId': session.walletId,
              'sessionId': session.sessionId,
              ...args
            },
            timeout)
        .whenComplete(() {
      if (identical(_active[session.walletId], actual)) {
        _active.remove(session.walletId);
      }
    });
    _active[session.walletId] = actual;
    return actual;
  }

  Future<Object?> call(
          NativeWalletSession session, String method, Map<String, Object?> args,
          {Duration timeout = const Duration(seconds: 30)}) =>
      _visible(_start(session, method, args, timeout), timeout);

  /// True while a send build holds [walletId]'s slot reservation. Callers
  /// that can be deferred (the background scan tick) read this and skip
  /// their turn instead of racing the build for the single native slot.
  bool isSlotReserved(String walletId) => (_reservations[walletId] ?? 0) > 0;

  /// Runs [action] while no NEW scan may start on [walletId].
  ///
  /// The slot itself stays first come — a scan already in flight cannot be
  /// cancelled and [action] still waits for it — but once that scan ends
  /// nothing re-takes the slot ahead of the build. Without this a repeating
  /// or promoted scan could keep re-acquiring the slot for the whole of the
  /// build's wait, which is what left the hardware Sign step on an
  /// indefinite loader with no fee and no enabled action.
  ///
  /// Re-entrant per wallet and always released, so a thrown [action] cannot
  /// leave scanning wedged off.
  Future<T> withSlotReservation<T>(
      String walletId, Future<T> Function() action) async {
    _reservations.update(walletId, (held) => held + 1, ifAbsent: () => 1);
    try {
      return await action();
    } finally {
      final held = (_reservations[walletId] ?? 1) - 1;
      if (held <= 0) {
        _reservations.remove(walletId);
      } else {
        _reservations[walletId] = held;
      }
    }
  }

  /// Resolves once no operation is in flight for [walletId]. A read that
  /// can wait (an address peek while the first full scan runs) parks here
  /// instead of being rejected with 'busy'. Admission stays first come:
  /// another operation may claim the slot between this returning and the
  /// caller's own request, so callers still handle 'busy'.
  /// Waits for [walletId]'s slot to fall idle.
  ///
  /// [timeout] bounds the wait. Without one this can spin forever: each
  /// time the slot frees, a background scan can claim it again before
  /// the caller gets there, and a wallet that is synced every few
  /// seconds never hands it over. That starved the receive address,
  /// which waited here and left the QR shimmering with no end.
  ///
  /// Returning after the deadline is not a failure. The caller then
  /// simply tries its request, and a slot that is genuinely busy
  /// answers with `busy`, which callers already handle.
  Future<void> whenIdle(String walletId, {Duration? timeout}) async {
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    while (true) {
      while (_active.containsKey(walletId)) {
        if (deadline != null && DateTime.now().isAfter(deadline)) return;
        final operation = _active[walletId]!;
        try {
          if (deadline == null) {
            await operation;
          } else {
            final left = deadline.difference(DateTime.now());
            if (left <= Duration.zero) return;
            await operation.timeout(left, onTimeout: () => null);
          }
        } catch (_) {}
      }
      // Yield one event-loop turn so a follow-up chained on the finished
      // operation (an incremental scan promoting to a full scan) claims
      // the slot before the caller does.
      await Future<void>.delayed(Duration.zero);
      if (!_active.containsKey(walletId)) return;
      if (deadline != null && DateTime.now().isAfter(deadline)) return;
    }
  }

  Future<void> sync(NativeWalletSession session, {bool fullScan = false}) {
    if (session._closed ||
        session._closing ||
        !identical(_sessions[session.walletId], session)) {
      return Future.error(const OnchainException('wallet_mismatch'));
    }
    final existing = _scans[session.walletId];
    if (existing != null) {
      if (fullScan && !existing.fullScan) {
        // An incremental scan cannot establish recovery completion. Wait for
        // the real reply, then request discovery; never silently downgrade.
        return _visible(
            existing.actual.then((_) => sync(session, fullScan: true)),
            fullScanTimeout);
      }
      return existing.visible;
    }
    // A send build holds a reservation while it waits for the slot. Starting
    // a scan now would claim the slot the instant the build's wait resolved
    // and push the Sign step through another full wait, so refuse until the
    // reservation is released. Scans already in flight are untouched.
    if (isSlotReserved(session.walletId)) {
      return Future.error(const OnchainException('busy'));
    }
    final timeout = fullScan ? fullScanTimeout : syncTimeout;
    late Future<void> actual;
    actual =
        _start(session, 'sync', {'fullScan': fullScan}, timeout).then((value) {
      final map = Map<String, Object?>.from(value! as Map);
      if (map['fullScan'] != fullScan) throw const OnchainException('internal');
      session.snapshot = OnchainSnapshot.fromMap(map['snapshot']);
      if (fullScan) session._completedFullScan = true;
    }).whenComplete(() {
      if (identical(_scans[session.walletId]?.actual, actual)) {
        _scans.remove(session.walletId);
      }
    });
    final visible = _visible(actual, timeout);
    _scans[session.walletId] = _PendingScan(fullScan, actual, visible);
    return visible;
  }

  Future<void> close(NativeWalletSession session,
      {bool deleteTemporary = false}) {
    if (deleteTemporary && !session.temporary) {
      return Future.error(const OnchainException('invalid_request'));
    }
    final pending = _closing[session.walletId];
    if (pending != null) return pending;
    session._closing = true;
    final actual =
        _doClose(session, deleteTemporary: deleteTemporary).whenComplete(() {
      _closing.remove(session.walletId);
      session._closing = false;
    });
    _closing[session.walletId] = actual;
    return actual;
  }

  Future<void> _doClose(NativeWalletSession session,
      {required bool deleteTemporary}) async {
    // Close has no UI deadline while waiting for the existing owner. It must
    // never delete a temporary SQLite file under a still-running scan.
    while (_active.containsKey(session.walletId)) {
      final operation = _active[session.walletId]!;
      try {
        await operation;
      } catch (_) {}
    }
    if (session._closed) return;
    await _start(session, 'close', {'deleteTemporary': deleteTemporary},
        const Duration(minutes: 5));
    session._closed = true;
    _sessions.remove(session.walletId);
    _identities.remove(session.walletId);
  }

  Future<void> closeWallet(String walletId) async {
    final opening = _opening[walletId];
    if (opening != null) {
      try {
        await opening;
      } catch (_) {}
    }
    final session = _sessions[walletId];
    if (session != null) await close(session);
  }

  Future<void> retireWallet(String walletId) async {
    _retired.add(walletId);
    await closeWallet(walletId);
  }

  Future<void> closeAll({Future<void> Function()? afterClose}) async {
    if (_closingAll) throw const OnchainException('busy');
    _closingAll = true;
    try {
      for (final id in {..._opening.keys, ..._sessions.keys}) {
        await closeWallet(id);
      }
      await afterClose?.call();
    } finally {
      _closingAll = false;
    }
  }
}
