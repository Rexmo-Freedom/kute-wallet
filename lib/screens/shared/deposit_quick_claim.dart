// Claim now: the optional, costlier way to add an on-chain deposit to the
// spending wallet at once. The default stays the automatic claim at 3
// confirmations under the normal fee cap; this is offered only when the SDK
// can actually claim the deposit now:
//  - confirming, when the provider quotes an early claim (DepositEarlyClaim
//    below, on the pending sheets);
//  - mature but refused for its fee, or after a failed claim (the unclaimed
//    deposit sheet in transactions_builder.dart).
// One approval (the step-up used for sends), then the shared result sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/extension.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/spark_deposit_actions.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Test seam: stands in for the one approval Claim now asks first.
/// Receives the claim intent and answers with a grant for it, or null.
@visibleForTesting
Future<AuthGrant?> Function(SensitiveIntent intent)? debugDepositClaimApproval;

/// The step-up for Claim now, bound to the deposit and the most the claim
/// may cost. True once approved and consumed; false when declined.
Future<bool> approveDepositClaim(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
  required String txid,
  required int vout,
  required int maxFeeSats,
}) async {
  SensitiveIntent intent() => SensitiveIntent(
        action: SensitiveAction.depositClaim,
        walletId: walletId,
        venue: 'bitcoin',
        destination: 'spark',
        asset: 'BTC',
        amountMax: BigInt.from(maxFeeSats),
        limits: {'deposit': '$txid:$vout'},
      );
  final seam = debugDepositClaimApproval;
  final AuthGrant? grant;
  if (seam != null) {
    grant = await seam(intent());
  } else {
    double? feeUsd;
    try {
      final rate = ref.read(selectedCurrencyProvider('usd')).toDouble();
      if (rate > 0) feeUsd = maxFeeSats / 1e8 * rate;
    } catch (_) {}
    grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: intent(),
      reason: context.l10n
          .stepUpReasonClaimDeposit(ref.read(conversionProvider(maxFeeSats))),
      amountUsd: feeUsd,
    );
  }
  if (grant == null || !context.mounted) return false;
  try {
    AuthGrants.consume(grant, intent());
    return true;
  } on ReauthRequired catch (e) {
    await showStepUpReviewAgain(context,
        action: SensitiveAction.depositClaim, field: e.primaryFieldClass);
    return false;
  } on AuthGrantException {
    return false;
  }
}

/// Localized copy for an expected deposit action failure.
String depositActionMessage(
    BuildContext context, WidgetRef ref, SparkDepositActionException e,
    {bool refund = false}) {
  final l10n = context.l10n;
  return switch (e.reason) {
    SparkDepositActionReason.walletChanged => l10n.depositActionWalletChanged,
    SparkDepositActionReason.busy => l10n.depositActionBusy,
    SparkDepositActionReason.walletUnavailable =>
      l10n.depositActionWalletUnavailable,
    SparkDepositActionReason.invalidDeposit => l10n.depositActionInvalidDeposit,
    SparkDepositActionReason.immature => l10n.depositActionImmature,
    SparkDepositActionReason.refundInProgress =>
      l10n.depositActionRefundInProgress,
    SparkDepositActionReason.invalidFee =>
      refund ? l10n.invalidRate : l10n.depositActionInvalidFee,
    SparkDepositActionReason.invalidAddress => l10n.pleaseEnterAnAddress,
    SparkDepositActionReason.feeExceeded => l10n.depositAddFeeAboveLimit(ref
        .read(conversionProvider((e.requiredFeeSats ?? BigInt.zero).toInt()))),
  };
}

/// The result sheet after a submitted claim.
void showDepositClaimSuccess(
  NavigatorState rootNav,
  BuildContext context,
  WidgetRef ref, {
  required int amountSats,
  required bool settled,
}) {
  final unit = ref.read(settingsProvider).btcFormat;
  pushKuteSuccessOverlay(
    navigator: rootNav,
    overlay: KuteConfirmation(
      message: context.l10n.activityBitcoinAdded,
      amount:
          amountSats > 0 ? '${amountSats.toFormattedString(unit)} $unit' : null,
      detail: settled ? null : context.l10n.activityBitcoinAddedPending,
      onDone: () => rootNav.pop(),
    ),
  );
}

/// The result sheet after a claim that did not go through: failure tone,
/// the reason in plain words, and Try again.
void showDepositClaimFailure(
  NavigatorState rootNav,
  BuildContext context, {
  required String detail,
  required VoidCallback onRetry,
}) {
  pushKuteSuccessOverlay(
    navigator: rootNav,
    overlay: KuteConfirmation(
      tone: KuteConfirmationTone.failure,
      message: context.l10n.depositClaimFailedTitle,
      detail: detail,
      buttonText: context.l10n.walletsTryAgain,
      onDone: () {
        rootNav.pop();
        onRetry();
      },
      secondaryButtonText: context.l10n.close,
      onSecondary: () => rootNav.pop(),
    ),
  );
}

/// Claim now on a deposit still confirming, when the provider offers an
/// early claim. Shows nothing until it has a quote, and nothing at all when
/// the provider offers none (the deposit then waits for its 3
/// confirmations). [vout] may be unknown for a mempool row: the SDK's
/// pending deposit for [txid] supplies it.
class DepositEarlyClaim extends ConsumerStatefulWidget {
  const DepositEarlyClaim({
    super.key,
    required this.txid,
    this.vout,
    required this.amountSats,
  });

  final String txid;
  final int? vout;
  final int amountSats;

  @override
  ConsumerState<DepositEarlyClaim> createState() => _DepositEarlyClaimState();
}

class _DepositEarlyClaimState extends ConsumerState<DepositEarlyClaim> {
  String? _walletId;
  int? _vout;
  int? _feeSats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    _vout = widget.vout;
    _load();
  }

  Future<void> _load() async {
    final walletId = _walletId;
    if (walletId == null || widget.txid.isEmpty) return;
    final actions = ref.read(sparkDepositActionsProvider);
    try {
      var vout = _vout;
      if (vout == null) {
        final deposit =
            await actions.depositForTxid(walletId: walletId, txid: widget.txid);
        vout = deposit?.vout;
      }
      if (vout == null) return;
      final quote = await actions.quote(
          walletId: walletId, txid: widget.txid, vout: vout);
      if (!mounted) return;
      final fee = quote.earlyFeeSats;
      // Only a quote the provider made, below the deposit itself.
      if (fee == null || fee <= 0 || fee >= widget.amountSats) return;
      setState(() {
        _vout = vout;
        _feeSats = fee;
      });
    } catch (_) {
      // No quote: the deposit simply waits for its confirmations.
    }
  }

  Future<void> _claim() async {
    final walletId = _walletId;
    final vout = _vout;
    final fee = _feeSats;
    if (_busy || walletId == null || vout == null || fee == null) return;
    final ceiling = suggestedClaimFeeSats(
            lastQuoteSats: fee, depositAmountSats: widget.amountSats) ??
        fee;
    final container = ProviderScope.containerOf(context, listen: false);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final actions = ref.read(sparkDepositActionsProvider);
    final approved = await approveDepositClaim(context, ref,
        walletId: walletId, txid: widget.txid, vout: vout, maxFeeSats: ceiling);
    if (!approved || !mounted) return;
    setState(() => _busy = true);
    TrackingService.depositQuickClaimStarted(
        amountSats: widget.amountSats,
        feeSats: fee,
        maxFeeSats: ceiling,
        stage: 'confirming');
    try {
      final result = await actions.claim(
        walletId: walletId,
        txid: widget.txid,
        vout: vout,
        maxFeeSats: BigInt.from(ceiling),
        depositAmountSats: BigInt.from(widget.amountSats),
        early: true,
      );
      TrackingService.depositQuickClaimSucceeded(
          amountSats: widget.amountSats,
          feeSats: fee,
          stage: 'confirming',
          outcome: result.outcome.name);
      if (result.outcome != SparkDepositClaimOutcome.statusUnknown) {
        container
            .read(walletTransactionCacheProvider.notifier)
            .removeSparkUnclaimedDeposit(walletId,
                txid: widget.txid, vout: vout);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showDepositClaimSuccess(rootNav, context, ref,
          amountSats: widget.amountSats, settled: false);
    } catch (e) {
      if (e is SparkDepositActionException &&
          e.reason == SparkDepositActionReason.busy) {
        // Another claim holds this deposit right now: nothing failed.
        if (mounted) {
          showMessageSnackBarInfo(
              context: context, message: context.l10n.depositActionBusy);
        }
        return;
      }
      final category =
          e is SparkDepositActionException ? e.reason.name : 'sdk_error';
      TrackingService.depositQuickClaimFailed(
          amountSats: widget.amountSats,
          feeSats: fee,
          stage: 'confirming',
          errorCategory: category);
      if (e is SparkDepositActionException &&
          e.reason == SparkDepositActionReason.feeExceeded &&
          e.requiredFeeSats != null &&
          mounted) {
        // The quote moved: the button shows the new fee for a fresh approval.
        setState(() => _feeSats = e.requiredFeeSats!.toInt());
      }
      if (!mounted) return;
      showDepositClaimFailure(
        rootNav,
        context,
        detail: e is SparkDepositActionException
            ? depositActionMessage(context, ref, e)
            : userErrorCopy(context, e,
                fallback: context.l10n.depositReasonFailed),
        onRetry: () {
          if (mounted) _claim();
        },
      );
    } finally {
      container.invalidate(listSparkUnclaimedDepositsProvider);
      container
          .read(backgroundSyncNotifierProvider.notifier)
          .performFullUpdate();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = _feeSats;
    if (fee == null) return const SizedBox.shrink();
    final feeText = ref.watch(conversionProvider(fee));
    return Padding(
      padding: EdgeInsets.only(top: 16.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DepositFeeRow(feeSats: fee),
          SizedBox(height: 12.h),
          AppButton(
            text: context.l10n.depositClaimNowFee(feeText),
            onPressed: _busy ? null : _claim,
            isLoading: _busy,
            compact: true,
          ),
        ],
      ),
    );
  }
}

/// "Fee to claim now   ₿12,000 · $8.10": the fee row of both claim sheets,
/// in the sheet's own detail-row type.
class DepositFeeRow extends ConsumerWidget {
  const DepositFeeRow({super.key, required this.feeSats});

  final int feeSats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = '${ref.watch(conversionProvider(feeSats))} · '
        '${ref.watch(conversionToFiatProvider(feeSats))}';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 9.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(context.l10n.depositFeeToClaimNow,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              )),
          SizedBox(width: 12.w),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

/// The quiet grey note of the deposit sheets (no tinted banner).
class DepositSheetNote extends StatelessWidget {
  const DepositSheetNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: c.textTertiary, size: 14.sp),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: c.textTertiary, fontSize: 13.sp, height: 1.35)),
        ),
      ],
    );
  }
}
