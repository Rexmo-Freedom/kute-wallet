// lib/providers/ledger/ledger_action_controller.dart
//
// Connect-and-approve controller for one reviewed Ledger venue action
// (Wallet hardening Phase 4a, P4.5, plan B10).
//
// Rules this file enforces:
// * Connecting is never approval. After the device is connected, unlocked,
//   in the Ethereum app and on the paired account, the controller stops at
//   `review`. Only an explicit `approve()` call signs, and it executes the
//   exact intent the user reviewed (its hash is re-verified first).
// * One approval at a time. A second `approve()` while one is running is
//   ignored, so a double tap gives one device prompt.
// * App authentication (Phase 1b `requireFreshAuthGrant`) runs through the
//   injectable [LedgerAppApproval] before any device prompt. Step-up
//   intents get a grant bound to the reviewed intent, consumed against the
//   re-verified intent right before the device prompt; session-only
//   intents ride the unlocked session. The Ledger approval on the device
//   stays mandatory: the grant is extra app protection, never a
//   replacement.
// * There is never a phone signer. The executor receives the Ledger
//   external signer only.
// * "Nothing was sent" is claimed only when no signature was obtained.
//   Once a POST may have started the state is `pending` and the submitted
//   action record is reconciled, never re-signed or resubmitted.
// * Cancel is always available. While the device prompt is open, cancel
//   disconnects the Ledger so the prompt cannot be approved afterwards.
//   Callers keep their own intent and entered amount.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_transports_provider.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/eth/eth_address_operation.dart';
import 'package:kute/services/hardware/ledger/eth/eth_apdu_common.dart';
import 'package:kute/services/hardware/ledger/eth/eth_app_config_operation.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_evm_signer.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart';
import 'package:kute/services/hardware/ledger/ledger_polymarket_executor.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:ledger_flutter_plus/ledger_flutter_plus.dart' show LedgerDevice;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

// ─────────────────────────── app approval seam ─────────────────────────

/// What the app approval step returned for one reviewed Ledger action.
class LedgerAppAuth {
  /// A session-only intent (D-9): the unlocked session is enough.
  const LedgerAppAuth.session()
      : approved = true,
        grant = null;

  /// A step-up intent the user freshly approved.
  const LedgerAppAuth.granted(AuthGrant this.grant) : approved = true;

  const LedgerAppAuth.declined()
      : approved = false,
        grant = null;

  final bool approved;
  final AuthGrant? grant;
}

/// Phase 1b seam. The controller asks this before any device prompt.
/// Tests pass a fake.
abstract class LedgerAppApproval {
  Future<LedgerAppAuth> authorize(
    BuildContext context,
    WidgetRef ref,
    LedgerSensitiveIntentDraft intent, {
    required String reason,
  });
}

/// The Phase 1b [SensitiveIntent] for a Ledger intent draft. Throws
/// [ArgumentError] for an action outside [SensitiveAction].
SensitiveIntent sensitiveIntentFromLedgerDraft(
        LedgerSensitiveIntentDraft draft) =>
    SensitiveIntent(
      action: SensitiveAction.values.byName(draft.action),
      walletId: draft.walletId,
      venue: draft.venue,
      account: draft.account,
      destination: draft.destination,
      asset: draft.asset,
      amountMax: draft.amountMax,
      limits: draft.limits,
      ttl: draft.ttl,
    );

/// Step-up intents (D-9: orders, sells, withdrawals) need
/// a fresh biometric or Kute PIN approval through [requireFreshAuthGrant].
/// Session-only intents (cancels, internal transfers, fixed approvals,
/// builder fee, wraps) ride the unlocked session.
class StepUpLedgerAppApproval implements LedgerAppApproval {
  const StepUpLedgerAppApproval();

  @override
  Future<LedgerAppAuth> authorize(
    BuildContext context,
    WidgetRef ref,
    LedgerSensitiveIntentDraft intent, {
    required String reason,
  }) async {
    if (!intent.requiresStepUp) return const LedgerAppAuth.session();
    final grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: sensitiveIntentFromLedgerDraft(intent),
      reason: reason,
    );
    return grant == null
        ? const LedgerAppAuth.declined()
        : LedgerAppAuth.granted(grant);
  }
}

final ledgerAppApprovalProvider =
    Provider<LedgerAppApproval>((ref) => const StepUpLedgerAppApproval());

// ─────────────────────────────── request ───────────────────────────────

class LedgerSigningContext {
  const LedgerSigningContext({
    required this.walletId,
    required this.pairedAddress,
    required this.signer,
  });

  final String walletId;
  final String pairedAddress;

  /// The Ledger's external signer. The only authority an executor gets.
  final EvmExternalSigner signer;
}

/// Reads venue state for a submission whose outcome is unknown. Returns
/// true when confirmed, false when rejected, null when still unknown.
/// Implementations must never sign or post.
typedef LedgerReconcile = Future<bool?> Function(String recordId);

class LedgerActionRequest<R> {
  const LedgerActionRequest({
    required this.intent,
    required this.execute,
    this.amountUsd,
    this.reconcile,
  });

  /// The reviewed action. Executed exactly as reviewed.
  final LedgerActionIntent intent;

  /// Runs the executor for [intent] with the Ledger signer.
  final Future<R> Function(LedgerSigningContext context) execute;

  /// Used only for the bucketed tracking value; never sent raw.
  final double? amountUsd;

  final LedgerReconcile? reconcile;

  String get action => intent.kind.name;
  LedgerActionClass get actionClass => classifyLedgerAction(intent.kind);
}

// ──────────────────────────────── state ────────────────────────────────

enum LedgerApprovalStep {
  chooseTransport,
  scanning,
  connecting,
  unlock,
  openApp,
  installApp,
  updateApp,
  checkingAccount,
  review,
  approveOnDevice,
  submitting,
  pending,
  success,
  failed,
}

enum LedgerApprovalError {
  /// A typed device failure; see [LedgerApprovalState.failure].
  device,
  notPaired,
  appAuthDeclined,
  blocked,
  geoBlocked,
  tradingDisabled,
  accountUnsupported,
  intentMismatch,
  nonceRejected,
  venueRejected,
  orderIdMismatch,
  unknown,
}

enum LedgerApprovalOutcomeKind {
  success,

  /// Submitted; the outcome is not known yet. The record is tracked.
  pending,

  /// The user closed the sheet while the request was already submitting.
  backgrounded,
  cancelled,
  failed,
}

class LedgerApprovalOutcome<R> {
  const LedgerApprovalOutcome(this.kind, {this.result, this.recordId});

  final LedgerApprovalOutcomeKind kind;
  final R? result;
  final String? recordId;

  bool get isSuccess => kind == LedgerApprovalOutcomeKind.success;
  bool get isPending =>
      kind == LedgerApprovalOutcomeKind.pending ||
      kind == LedgerApprovalOutcomeKind.backgrounded;
}

class LedgerApprovalState {
  const LedgerApprovalState({
    this.step = LedgerApprovalStep.chooseTransport,
    this.transport = LedgerConnectionType.bluetooth,
    this.error,
    this.failure,
    this.signatureObtained = false,
    this.recordId,
    this.result,
    this.checking = false,
  });

  final LedgerApprovalStep step;
  final LedgerConnectionType transport;
  final LedgerApprovalError? error;
  final LedgerFailure? failure;

  /// True once the device returned any signature for this attempt. From
  /// then on the UI never says "Nothing was sent".
  final bool signatureObtained;
  final String? recordId;
  final Object? result;

  /// A pending status check is running.
  final bool checking;

  /// Whether "Approve again" is offered from [LedgerApprovalStep.failed].
  /// Only when nothing could have reached the venue, or the venue answered
  /// with a rejection (so nothing executed).
  bool get canRetry {
    if (step != LedgerApprovalStep.failed) return false;
    switch (error) {
      case LedgerApprovalError.nonceRejected:
      case LedgerApprovalError.venueRejected:
      case LedgerApprovalError.appAuthDeclined:
        return true;
      case LedgerApprovalError.device:
        return failure?.code != LedgerFailureCode.wrongDevice &&
            failure?.code != LedgerFailureCode.wrongSigner;
      default:
        return false;
    }
  }

  LedgerApprovalState copyWith({
    LedgerApprovalStep? step,
    LedgerConnectionType? transport,
    LedgerApprovalError? error,
    LedgerFailure? failure,
    bool clearError = false,
    bool? signatureObtained,
    String? recordId,
    Object? result,
    bool? checking,
  }) =>
      LedgerApprovalState(
        step: step ?? this.step,
        transport: transport ?? this.transport,
        error: clearError ? null : (error ?? this.error),
        failure: clearError ? null : (failure ?? this.failure),
        signatureObtained: signatureObtained ?? this.signatureObtained,
        recordId: recordId ?? this.recordId,
        result: result ?? this.result,
        checking: checking ?? this.checking,
      );
}

// ────────────────────────────── controller ─────────────────────────────

class LedgerActionController extends StateNotifier<LedgerApprovalState> {
  LedgerActionController(this._ref, this.walletId)
      : super(const LedgerApprovalState());

  final Ref _ref;
  final String walletId;

  LedgerActionRequest<Object?>? _request;
  bool _executing = false;
  bool _cancelled = false;
  String? _connectedModel;

  LedgerActionRequest<Object?>? get request => _request;

  LedgerService get _service => _ref.read(ledgerServiceProvider.notifier);

  void _set(LedgerApprovalState next) {
    if (mounted) state = next;
  }

  String? get _pairedAddress {
    final identity = _ref.read(ledgerIdentityProvider(walletId));
    if (identity == null || !identity.hasVerifiedEvm) return null;
    return identity.evmAddress;
  }

  /// Starts the flow for a reviewed [request]. Reuses a live connection;
  /// otherwise offers transports (USB only on Android with its flag on).
  void begin(LedgerActionRequest<Object?> request) {
    _request = request;
    _cancelled = false;
    TrackingService.ledgerApprovalRequested(
      action: request.action,
      clarity: request.actionClass.clarity.name,
    );
    if (request.intent.walletId != walletId || _pairedAddress == null) {
      _fail(LedgerApprovalError.notPaired);
      return;
    }
    if (_service.deviceSession != null) {
      unawaited(_preflight());
      return;
    }
    final transports = _ref.read(ledgerTransportsProvider);
    if (transports.length > 1) {
      _set(const LedgerApprovalState(step: LedgerApprovalStep.chooseTransport));
    } else {
      selectTransport(transports.first);
    }
  }

  void selectTransport(LedgerConnectionType transport) {
    if (_executing) return;
    _set(LedgerApprovalState(
        step: LedgerApprovalStep.scanning, transport: transport));
    TrackingService.ledgerConnectStarted(
      transport: transport == LedgerConnectionType.usb ? 'usb' : 'bluetooth',
      reason: _request?.action ?? 'unknown',
    );
    unawaited(_service.startScan(transport));
  }

  void rescan() => selectTransport(state.transport);

  Future<void> connect(LedgerDevice device) async {
    if (state.step != LedgerApprovalStep.scanning) return;
    _set(state.copyWith(step: LedgerApprovalStep.connecting, clearError: true));
    final model = device.deviceInfo.name;
    final ok = await _service.connectToDevice(device);
    if (!mounted || _cancelled) return;
    if (!ok) {
      final failure = _service.state.failure ??
          const LedgerFailure(LedgerFailureCode.disconnected);
      TrackingService.ledgerConnectResult(
          outcome: failure.code.name, model: model);
      _failDevice(failure);
      return;
    }
    _connectedModel = model;
    TrackingService.ledgerConnectResult(outcome: 'connected', model: model);
    await _preflight();
  }

  /// Retries the unlock, open-app, install or update step.
  Future<void> retryPreflight() => _preflight();

  /// Opens the Ethereum app and checks the device account against the
  /// paired address. Stops at `review`; never signs.
  Future<void> _preflight() async {
    final session = _service.deviceSession;
    final paired = _pairedAddress;
    if (paired == null) {
      _fail(LedgerApprovalError.notPaired);
      return;
    }
    if (session == null) {
      _failDevice(const LedgerFailure(LedgerFailureCode.disconnected));
      return;
    }
    final path =
        _ref.read(ledgerIdentityProvider(walletId))?.evmDerivationPath ??
            kLedgerEvmDerivationPath;
    _set(state.copyWith(step: LedgerApprovalStep.openApp, clearError: true));
    try {
      await session.run((scope) async {
        await scope.ensureApp(LedgerAppId.ethereum);
        _set(state.copyWith(step: LedgerApprovalStep.checkingAccount));
        final config = parseEthAppConfig(await scope.send(ethAppConfigApdu()));
        if (!config.supports(kLedgerEthMinimumAppVersion)) {
          throw const LedgerFailure(LedgerFailureCode.unsupportedAppVersion,
              app: LedgerAppId.ethereum);
        }
        final account = parseEthAddressResponse(
            await scope.send(ethGetAddressApdu(path: path, display: false)));
        if (!sameEvmAddress(account.address, paired)) {
          throw const LedgerFailure(LedgerFailureCode.wrongDevice);
        }
      });
      if (_cancelled) return;
      _set(state.copyWith(step: LedgerApprovalStep.review, clearError: true));
    } on LedgerFailure catch (failure) {
      if (_cancelled) return;
      switch (failure.code) {
        case LedgerFailureCode.locked:
          _set(state.copyWith(
              step: LedgerApprovalStep.unlock, failure: failure));
        case LedgerFailureCode.wrongApp:
          _set(state.copyWith(
              step: LedgerApprovalStep.openApp, failure: failure));
        case LedgerFailureCode.appNotInstalled:
          _set(state.copyWith(
              step: LedgerApprovalStep.installApp, failure: failure));
        case LedgerFailureCode.unsupportedAppVersion:
          _set(state.copyWith(
              step: LedgerApprovalStep.updateApp, failure: failure));
        default:
          _failDevice(failure);
      }
    } on FormatException {
      if (_cancelled) return;
      _failDevice(const LedgerFailure(LedgerFailureCode.unknown));
    }
  }

  /// Signs and submits the reviewed intent. [appAuth] is the Phase 1b
  /// step; it runs before any device prompt. A step-up intent must come
  /// back with a grant, which is consumed against the re-verified intent
  /// before the device is asked. Ignored unless at `review` and when
  /// already running. A retry goes through [begin] again, so the user
  /// always sees the review before a new prompt.
  Future<void> approve({
    required Future<LedgerAppAuth> Function(LedgerSensitiveIntentDraft intent)
        appAuth,
  }) async {
    final request = _request;
    if (request == null || _executing) return;
    if (state.step != LedgerApprovalStep.review) return;
    _executing = true;
    _cancelled = false;
    final action = request.action;

    try {
      request.intent.verify();
    } on LedgerIntentMismatchException {
      _executing = false;
      _fail(LedgerApprovalError.intentMismatch);
      return;
    }

    final LedgerAppAuth auth;
    try {
      auth = await appAuth(request.intent.toSensitiveIntent());
    } catch (_) {
      _executing = false;
      _fail(LedgerApprovalError.appAuthDeclined);
      return;
    }
    if (!auth.approved || _cancelled) {
      _executing = false;
      TrackingService.ledgerApprovalResult(
          action: action, outcome: 'app_auth_declined');
      if (!_cancelled) _fail(LedgerApprovalError.appAuthDeclined);
      return;
    }

    // The grant is app protection on top of the device approval, bound to
    // what the user reviewed: re-verify the intent, then consume the grant
    // before any device prompt. A step-up intent never rides the session.
    final draft = request.intent.toSensitiveIntent();
    final grant = auth.grant;
    if (draft.requiresStepUp && grant == null) {
      _executing = false;
      _fail(LedgerApprovalError.appAuthDeclined, trackAction: action);
      return;
    }
    if (grant != null) {
      try {
        request.intent.verify();
        AuthGrants.consume(grant, sensitiveIntentFromLedgerDraft(draft));
      } on LedgerIntentMismatchException {
        _executing = false;
        _fail(LedgerApprovalError.intentMismatch, trackAction: action);
        return;
      } on ReauthRequired catch (e) {
        _executing = false;
        TrackingService.track('step_up_reauth_required', params: {
          'action_type': grant.action.name,
          'field_class': e.primaryFieldClass.name,
        });
        _fail(LedgerApprovalError.intentMismatch, trackAction: action);
        return;
      } on AuthGrantException {
        _executing = false;
        _fail(LedgerApprovalError.appAuthDeclined, trackAction: action);
        return;
      } on ArgumentError {
        _executing = false;
        _fail(LedgerApprovalError.intentMismatch, trackAction: action);
        return;
      }
    }
    // Phase 5 B12: the backend session (the Polymarket relay) is prepared
    // before the Ledger scope below, since minting one signs with the hot
    // wallet identity, which the scope refuses.
    try {
      await AffiliateService.prepareSessionForLedgerOperation();
    } catch (_) {}
    // The review may have closed while session preparation was in flight.
    // A cancelled approval must never reach a device prompt or submission.
    if (!mounted || _cancelled) {
      _executing = false;
      return;
    }

    final paired = _pairedAddress;
    final session = _service.deviceSession;
    if (paired == null || session == null) {
      _executing = false;
      _failDevice(const LedgerFailure(LedgerFailureCode.disconnected));
      return;
    }

    final signer = _ref.read(ledgerEvmSignerFactoryProvider)(session, paired);
    var signatures = 0;
    final steps = signer.steps.listen((step) {
      switch (step) {
        case LedgerSignStep.awaitingApproval:
          _set(state.copyWith(step: LedgerApprovalStep.approveOnDevice));
        case LedgerSignStep.signed:
          signatures++;
          _set(state.copyWith(
              step: LedgerApprovalStep.submitting, signatureObtained: true));
        default:
          break;
      }
    });
    _set(LedgerApprovalState(
      step: LedgerApprovalStep.approveOnDevice,
      transport: state.transport,
    ));

    try {
      // Phase 5 B12: hot entry points refuse to run inside this scope.
      final result = await LedgerOperationScope.run(
          walletId,
          () => request.execute(LedgerSigningContext(
                walletId: walletId,
                pairedAddress: paired,
                signer: signer.externalSigner,
              )));
      TrackingService.ledgerApprovalResult(action: action, outcome: 'approved');
      TrackingService.ledgerActionSubmitted(
          action: action, amountUsd: request.amountUsd);
      _set(state.copyWith(
        step: LedgerApprovalStep.success,
        result: result,
        signatureObtained: true,
        clearError: true,
      ));
    } on LedgerSubmissionUnknownException catch (e) {
      TrackingService.ledgerApprovalResult(
          action: action, outcome: 'submitted_unknown');
      TrackingService.ledgerActionSubmitted(
          action: action, amountUsd: request.amountUsd);
      _set(state.copyWith(
        step: LedgerApprovalStep.pending,
        recordId: e.recordId,
        signatureObtained: true,
        clearError: true,
      ));
    } on LedgerFailure catch (failure) {
      TrackingService.ledgerApprovalResult(
          action: action,
          outcome: _cancelled ? 'cancelled' : failure.code.name);
      _failDevice(failure, signatureObtained: signatures > 0);
    } on LedgerActionBlockedException {
      _fail(LedgerApprovalError.blocked, trackAction: action);
    } on LedgerHyperliquidGeoBlockedException {
      _fail(LedgerApprovalError.geoBlocked, trackAction: action);
    } on LedgerHyperliquidDisabledException {
      _fail(LedgerApprovalError.tradingDisabled, trackAction: action);
    } on LedgerPolymarketAccountUnsupportedException {
      _fail(LedgerApprovalError.accountUnsupported, trackAction: action);
    } on LedgerIntentMismatchException {
      _fail(LedgerApprovalError.intentMismatch,
          trackAction: action, signatureObtained: signatures > 0);
    } on LedgerOrderIdMismatchException {
      _fail(LedgerApprovalError.orderIdMismatch,
          trackAction: action, signatureObtained: true);
    } on HyperliquidNonceRejectedException {
      _fail(LedgerApprovalError.nonceRejected,
          trackAction: action, signatureObtained: signatures > 0);
    } on HyperliquidRejectedException {
      _fail(LedgerApprovalError.venueRejected,
          trackAction: action, signatureObtained: signatures > 0);
    } on LedgerPolymarketOrderRejectedException {
      _fail(LedgerApprovalError.venueRejected,
          trackAction: action, signatureObtained: signatures > 0);
    } on LedgerPolymarketAuthException {
      _fail(LedgerApprovalError.venueRejected,
          trackAction: action, signatureObtained: signatures > 0);
    } catch (error) {
      final sw = LedgerFailure.statusWordOf(error);
      if (sw != null) {
        final failure = LedgerFailure.from(error, appConfirmedOpen: true);
        TrackingService.ledgerApprovalResult(
            action: action, outcome: failure.code.name);
        _failDevice(failure, signatureObtained: signatures > 0);
      } else {
        _fail(LedgerApprovalError.unknown,
            trackAction: action, signatureObtained: signatures > 0);
      }
    } finally {
      await steps.cancel();
      await signer.dispose();
      _executing = false;
    }
  }

  /// Reads venue state for a pending submission. Never signs.
  Future<void> checkPending() async {
    final reconcile = _request?.reconcile;
    final recordId = state.recordId;
    if (state.step != LedgerApprovalStep.pending ||
        state.checking ||
        reconcile == null ||
        recordId == null) {
      return;
    }
    _set(state.copyWith(checking: true));
    bool? confirmed;
    try {
      confirmed = await reconcile(recordId);
    } catch (_) {
      confirmed = null;
    }
    TrackingService.ledgerPendingChecked(
      action: _request?.action ?? 'unknown',
      outcome: confirmed == null
          ? 'unknown'
          : confirmed
              ? 'confirmed'
              : 'rejected',
    );
    if (!mounted) return;
    if (confirmed == true) {
      _set(state.copyWith(step: LedgerApprovalStep.success, checking: false));
    } else if (confirmed == false) {
      state = LedgerApprovalState(
        step: LedgerApprovalStep.failed,
        transport: state.transport,
        error: LedgerApprovalError.venueRejected,
        signatureObtained: true,
        recordId: recordId,
      );
    } else {
      _set(state.copyWith(checking: false));
    }
  }

  /// Cancels from any step and returns what the caller should assume.
  Future<LedgerApprovalOutcomeKind> cancel() async {
    final step = state.step;
    _cancelled = true;
    switch (step) {
      case LedgerApprovalStep.chooseTransport:
      case LedgerApprovalStep.scanning:
      case LedgerApprovalStep.connecting:
        await _service.stopScan();
      case LedgerApprovalStep.approveOnDevice:
        // The prompt must not stay approvable after the sheet is gone.
        await _service.disconnect();
      default:
        break;
    }
    final outcome = switch (step) {
      LedgerApprovalStep.submitting => LedgerApprovalOutcomeKind.backgrounded,
      LedgerApprovalStep.pending => LedgerApprovalOutcomeKind.pending,
      LedgerApprovalStep.success => LedgerApprovalOutcomeKind.success,
      _ => LedgerApprovalOutcomeKind.cancelled,
    };
    if (outcome == LedgerApprovalOutcomeKind.cancelled && !_executing) {
      TrackingService.ledgerApprovalResult(
          action: _request?.action ?? 'unknown', outcome: 'cancelled');
    }
    return outcome;
  }

  String? get connectedModel => _connectedModel;

  void _failDevice(LedgerFailure failure, {bool signatureObtained = false}) {
    _set(LedgerApprovalState(
      step: LedgerApprovalStep.failed,
      transport: state.transport,
      error: LedgerApprovalError.device,
      failure: failure,
      signatureObtained: signatureObtained || state.signatureObtained,
    ));
  }

  void _fail(
    LedgerApprovalError error, {
    String? trackAction,
    bool signatureObtained = false,
  }) {
    if (trackAction != null) {
      TrackingService.ledgerApprovalResult(
          action: trackAction, outcome: error.name);
    }
    _set(LedgerApprovalState(
      step: LedgerApprovalStep.failed,
      transport: state.transport,
      error: error,
      signatureObtained: signatureObtained,
    ));
  }

  @override
  void dispose() {
    if (!_executing) {
      try {
        unawaited(_service.stopScan());
      } catch (_) {}
    }
    super.dispose();
  }
}

final ledgerActionControllerProvider = StateNotifierProvider.autoDispose
    .family<LedgerActionController, LedgerApprovalState, String>(
  (ref, walletId) => LedgerActionController(ref, walletId),
);

// ─────────────────────────── pending records ───────────────────────────

/// Records of this wallet still waiting for a venue answer. The account
/// tabs can list them and reconcile without any device prompt.
final ledgerPendingActionsProvider = FutureProvider.autoDispose
    .family<List<LedgerSubmittedAction>, String>((ref, walletId) async {
  final records =
      await ref.watch(ledgerSubmittedActionStoreProvider).forWallet(walletId);
  return records
      .where((r) =>
          r.stage == LedgerSubmissionStage.submitting ||
          r.stage == LedgerSubmissionStage.submittedUnknown)
      .toList(growable: false);
});
