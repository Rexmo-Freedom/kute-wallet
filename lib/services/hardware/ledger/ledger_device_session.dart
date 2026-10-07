// lib/services/hardware/ledger/ledger_device_session.dart
//
// One serialized Ledger device session (Wallet hardening Phase 3, B2).
//
// `ledger_flutter_plus` already queues single commands per connection.
// This adds what was missing:
//   * whole flows (open app, check account, sign) run one at a time;
//     a second flow while one is in flight fails with `busy` instead of
//     queuing a second device prompt,
//   * reads that need no prompt queue behind the current flow,
//   * app switching through the dashboard (GET_APP_AND_VERSION, QUIT_APP,
//     OPEN_APP, poll),
//   * a reconnect during a switch only to the SAME device ID, followed by
//     the caller's identity check; a different ID gives `wrongDevice`,
//   * timeouts: 10 s for commands with no prompt, 120 s for prompts,
//   * every failure mapped to a typed [LedgerFailure].
//
// BLE link behaviour during app switches differs per model; the session
// logic here is unit tested against fakes and still needs the physical
// device matrix (plan section D).

import 'dart:async';
import 'dart:typed_data';

import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';
import 'package:ledger_flutter_plus/ledger_flutter_plus.dart'
    show LedgerConnection, LedgerDevice;

typedef LedgerReconnect = Future<LedgerConnection> Function(
    LedgerDevice device);

/// Re-verifies device identity (for example the Bitcoin fingerprint)
/// after a reconnect.
typedef LedgerIdentityCheck = Future<void> Function(LedgerSessionScope scope);

class LedgerDeviceSession {
  LedgerDeviceSession({
    required LedgerConnection connection,
    LedgerReconnect? reconnect,
    this.commandTimeout = const Duration(seconds: 10),
    this.promptTimeout = const Duration(seconds: 120),
    this.reconnectTimeout = const Duration(seconds: 30),
    this.appPollInterval = const Duration(milliseconds: 500),
    this.appPollAttempts = 40,
    Future<void> Function(Duration)? delay,
  })  : _connection = connection,
        deviceId = connection.device.id,
        _reconnect = reconnect,
        _delay = delay ?? ((d) => Future<void>.delayed(d));

  /// The device this session is pinned to for its whole life.
  final String deviceId;
  final Duration commandTimeout;
  final Duration promptTimeout;
  final Duration reconnectTimeout;
  final Duration appPollInterval;
  final int appPollAttempts;

  final LedgerReconnect? _reconnect;
  final Future<void> Function(Duration) _delay;

  LedgerConnection _connection;
  LedgerConnection get connection => _connection;

  bool _flowActive = false;
  Future<void> _tail = Future.value();
  LedgerAppId? _confirmedApp;
  int _reconnects = 0;

  /// True while a prompting flow is in flight.
  bool get isBusy => _flowActive;

  /// The app GET_APP_AND_VERSION last confirmed open, if any.
  LedgerAppId? get confirmedApp => _confirmedApp;

  int get reconnectCount => _reconnects;

  /// Runs a flow that may prompt on the device. Throws `busy` at once when
  /// another flow is in flight; never queues a second prompt.
  Future<T> run<T>(
    Future<T> Function(LedgerSessionScope scope) flow, {
    LedgerIdentityCheck? identityCheck,
  }) async {
    if (_flowActive) throw const LedgerFailure(LedgerFailureCode.busy);
    _flowActive = true;
    try {
      return await _enqueue(
          () => flow(LedgerSessionScope._(this, identityCheck)));
    } finally {
      _flowActive = false;
    }
  }

  /// Runs a flow with no device prompt, queued behind the current one.
  Future<T> read<T>(Future<T> Function(LedgerSessionScope scope) flow) =>
      _enqueue(() => flow(LedgerSessionScope._(this, null)));

  Future<T> _enqueue<T>(Future<T> Function() body) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      return await body();
    } catch (error, stack) {
      if (error is LedgerFailure) rethrow;
      final mapped =
          LedgerFailure.from(error, appConfirmedOpen: _confirmedApp != null);
      if (mapped.code == LedgerFailureCode.unknown &&
          LedgerFailure.statusWordOf(error) == null) {
        rethrow;
      }
      Error.throwWithStackTrace(mapped, stack);
    } finally {
      done.complete();
    }
  }

  Future<Uint8List> _send(
    LedgerApdu apdu, {
    required bool prompts,
    LedgerCommandPhase phase = LedgerCommandPhase.command,
    LedgerAppId? app,
  }) async {
    final connection = _connection;
    if (connection.isDisconnected) {
      _confirmedApp = null;
      throw LedgerFailure(LedgerFailureCode.disconnected, app: app);
    }
    try {
      return await connection
          .sendOperation<Uint8List>(LedgerApduOperation(apdu))
          .timeout(prompts ? promptTimeout : commandTimeout);
    } on TimeoutException {
      throw LedgerFailure(LedgerFailureCode.timeout, app: app);
    } catch (error) {
      final failure = LedgerFailure.from(error,
          appConfirmedOpen: _confirmedApp != null, phase: phase, app: app);
      if (failure.code == LedgerFailureCode.disconnected) _confirmedApp = null;
      throw failure;
    }
  }

  Future<void> _ensureApp(LedgerSessionScope scope, LedgerAppId app) async {
    LedgerRunningApp running;
    try {
      running = await scope.currentApp();
    } on LedgerFailure catch (f) {
      if (f.code != LedgerFailureCode.disconnected) rethrow;
      await _reconnectSameDevice(scope);
      running = await scope.currentApp();
    }
    if (running.isApp(app)) {
      _confirmedApp = app;
      return;
    }
    _confirmedApp = null;

    if (!running.isDashboard) {
      await _sendRecovering(scope, quitAppApdu(), prompts: false);
      await _pollApp(scope, (r) => r.isDashboard, target: null);
    }
    await _sendRecovering(scope, openAppApdu(app.deviceName),
        prompts: true, phase: LedgerCommandPhase.openApp, app: app);
    await _pollApp(scope, (r) => r.isApp(app), target: app);
    _confirmedApp = app;
  }

  /// Sends a switching command; a dropped link reconnects to the same
  /// device instead of failing (some models reset BLE on app switch).
  Future<void> _sendRecovering(
    LedgerSessionScope scope,
    LedgerApdu apdu, {
    required bool prompts,
    LedgerCommandPhase phase = LedgerCommandPhase.command,
    LedgerAppId? app,
  }) async {
    try {
      await _send(apdu, prompts: prompts, phase: phase, app: app);
    } on LedgerFailure catch (f) {
      if (f.code != LedgerFailureCode.disconnected) rethrow;
      await _reconnectSameDevice(scope);
    }
  }

  Future<void> _pollApp(
    LedgerSessionScope scope,
    bool Function(LedgerRunningApp running) done, {
    required LedgerAppId? target,
  }) async {
    LedgerRunningApp? last;
    for (var attempt = 0; attempt < appPollAttempts; attempt++) {
      try {
        last = await scope.currentApp();
        if (done(last)) return;
      } on LedgerFailure catch (f) {
        switch (f.code) {
          case LedgerFailureCode.disconnected:
            await _reconnectSameDevice(scope);
          case LedgerFailureCode.locked:
          case LedgerFailureCode.rejected:
          case LedgerFailureCode.appNotInstalled:
          case LedgerFailureCode.wrongDevice:
          case LedgerFailureCode.busy:
            rethrow;
          default:
            // The app is still loading; keep polling.
            break;
        }
      } on FormatException {
        // Partial response while the app loads; keep polling.
      }
      await _delay(appPollInterval);
    }
    if (target != null && last != null && !last.isDashboard) {
      throw LedgerFailure(LedgerFailureCode.wrongApp, app: target);
    }
    throw LedgerFailure(LedgerFailureCode.timeout, app: target);
  }

  Future<void> _reconnectSameDevice(LedgerSessionScope scope) async {
    _confirmedApp = null;
    final reconnect = _reconnect;
    if (reconnect == null) {
      throw const LedgerFailure(LedgerFailureCode.disconnected);
    }
    final LedgerConnection next;
    try {
      next = await reconnect(_connection.device).timeout(reconnectTimeout);
    } on LedgerFailure {
      rethrow;
    } catch (_) {
      throw const LedgerFailure(LedgerFailureCode.disconnected);
    }
    if (next.device.id != deviceId) {
      try {
        await next.disconnect();
      } catch (_) {}
      throw const LedgerFailure(LedgerFailureCode.wrongDevice);
    }
    _connection = next;
    _reconnects++;
    final check = scope._identityCheck;
    if (check != null) await check(scope);
  }
}

/// The handle a flow uses to talk to the device.
class LedgerSessionScope {
  LedgerSessionScope._(this._session, this._identityCheck);

  final LedgerDeviceSession _session;
  final LedgerIdentityCheck? _identityCheck;

  LedgerAppId? get confirmedApp => _session._confirmedApp;

  LedgerConnection get connection => _session._connection;

  /// Sends one APDU frame and returns its payload (status word stripped).
  Future<Uint8List> send(
    LedgerApdu apdu, {
    bool prompts = false,
    LedgerCommandPhase phase = LedgerCommandPhase.command,
  }) =>
      _session._send(apdu, prompts: prompts, phase: phase);

  Future<LedgerRunningApp> currentApp() async =>
      parseAppAndVersion(await send(getAppAndVersionApdu()));

  /// Makes [app] the running app, quitting another app and opening this
  /// one through the dashboard when needed. The user confirms the open on
  /// the device.
  Future<void> ensureApp(LedgerAppId app) => _session._ensureApp(this, app);
}
