// lib/screens/share/claimed_prompt_sheet.dart
//
// "{name} claimed your {amount}. Send now." The sheet the pay-on-open
// pass (services/share_link_claims.dart) shows for one claimed share
// link. Send now runs the wallet's own send to the destination the
// recipient's wallet gave (a Spark address, or a BOLT11 invoice for
// bitcoin) behind the normal PIN/biometric step-up, then records the
// payment locally and reports it to the backend. Later closes the sheet
// and the next pass asks again.
//
// The money path is the existing one: `prepareGenericPaymentProvider` /
// `prepareLightningPaymentProvider` for bitcoin,
// `prepareSparkTokenPaymentProvider` for dollars (the token's own base
// units, never sats), executed by the same providers the send flows use.
// The step-up intent binds the destination, the asset and the exact
// amount, so what is approved is what is sent.
//
// DOLLARS FALLING SHORT are funded like an order (founder, 8 November 2026:
// "just literally do like normal fills";
// services/one_balance/gift_funding.dart): the sheet names each leg that
// must go ("Moving $20.00 from Bitcoin → Dollars") and its fee in the
// slips' own fee row before the tap, one approval binds the payment and the
// leg, and the money's steps (MoneyStepsView) take the mascot's place while
// they run. A funding failure says "Could not send. Kute will ask again
// next time it opens." with the steps showing where the money is; a swap
// refused by policy says so in the policy's own words. Dollars that cover
// it read exactly as they always did. The run does not need the sheet: it
// goes on, and pays, if the sheet is swiped away.
//
// A failure after the SDK accepted the payment is still a payment: the
// payment id is stored at once and `POST /paid` is retried by the next
// pass, never the send.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show PrepareSendPaymentResponse, SendPaymentRequest;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart'
    show formatDollars;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/breez/sdk_operation_guard.dart'
    show runSparkMutation;
import 'package:kute/models/kute_state.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/breez_provider.dart'
    show
        executeSparkTransactionProvider,
        prepareGenericPaymentProvider,
        prepareLightningPaymentProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_mascot.dart';
import 'package:kute/screens/shared/money_fee_summary.dart'
    show MoneyFeeSummary, fundingLegFeeLabel;
import 'package:kute/screens/shared/money_steps_view.dart'
    show MoneyStepsView, moneyPlaceName;
import 'package:kute/screens/shared/move_steps_view.dart' show moveStepLines;
import 'package:kute/screens/shared/venue_cash_pull_copy.dart'
    show venueCashVenueName;
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/funding/hot_settlement.dart' show HotSettlement;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show bitcoinLegSpreadEstimate, cachedSpendingBitcoin;
import 'package:kute/services/one_balance/gift_funding.dart';
import 'package:kute/services/one_balance/money_steps.dart'
    show MoneyPlace, MoneyStepStatus;
import 'package:kute/services/runtime_capabilities_service.dart'
    show runtimeCapabilitiesProvider;
import 'package:kute/services/share_link_events.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/theme/app_theme.dart';

/// Shows the prompt for [claim] over the root navigator. Resolves when the
/// sheet closes, whatever happened.
Future<void> showClaimedPromptSheet(
        BuildContext context, ClaimedShareLink claim) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: 'share_claimed_prompt'),
      builder: (_) => ClaimedPromptSheet(claim: claim),
    );

class ClaimedPromptSheet extends ConsumerStatefulWidget {
  const ClaimedPromptSheet({super.key, required this.claim});

  final ClaimedShareLink claim;

  /// Test seam: what Send now runs. Null runs the real payment. The
  /// answer is the payment id, or null when the user declined.
  @visibleForTesting
  static Future<String?> Function(
      BuildContext context, WidgetRef ref, ClaimedShareLink claim)? debugPayer;

  @override
  ConsumerState<ClaimedPromptSheet> createState() => _ClaimedPromptSheetState();
}

class _ClaimedPromptSheetState extends ConsumerState<ClaimedPromptSheet> {
  bool _sending = false;
  bool _sent = false;
  String? _error;
  double? _bitcoinSpread;

  ClaimedShareLink get claim => widget.claim;

  bool get _dollars => claim.kind == ShareLinkKind.dollars;

  @override
  void initState() {
    super.initState();
    if (!_dollars) return;
    // A leg an earlier attempt left on its way: follow it (a read). The
    // funding's steps redraw from the row.
    ShareLinksStore.revision.addListener(_rowChanged);
    if (ShareLinksStore.byId(claim.id)?.funding?.onItsWay ?? false) {
      unawaited(ref.read(giftFundingRunnerProvider).resume(claim.id));
    }
    unawaited(_readBitcoinSpread());
  }

  /// Orchestra's own price for the Bitcoin leg, for the fee row, as a slip
  /// reads it; the assumed spread stands until it answers, or if it does not.
  Future<void> _readBitcoinSpread() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final landUsd = _preview()?.bitcoinUsd ?? 0;
    if (landUsd <= 0) return;
    final spread = await bitcoinLegSpreadEstimate(
        cachedSpendingBitcoin(ref.read), landUsd);
    if (spread != null && mounted) setState(() => _bitcoinSpread = spread);
  }

  @override
  void dispose() {
    ShareLinksStore.revision.removeListener(_rowChanged);
    super.dispose();
  }

  void _rowChanged() {
    if (!mounted) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(() {});
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// What the person reads when "Send now" stopped short of paying.
  String _failureText(Object e) {
    final l10n = context.l10n;
    return switch (e) {
      GiftFundingRefused(:final denied?) => denied.messageIn(l10n),
      GiftFundingRefused(category: 'insufficient_funds') =>
        l10n.sendMoreThanAvailable,
      GiftFundingStopped(:final cause?)
          when HotSettlement.fundsMayHaveMoved(cause) =>
        HotSettlement.messageFor(cause, l10n) ?? l10n.shareSendFailed,
      _ => l10n.shareSendFailed,
    };
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final pay = ClaimedPromptSheet.debugPayer ?? payShareLinkClaim;
    // The sheet may be gone when the money lands: the report needs no ref.
    final api = ref.read(shareLinksApiProvider);
    String? paymentId;
    try {
      paymentId = await pay(context, ref, claim);
    } catch (e) {
      paymentId = null;
      if (mounted) setState(() => _error = _failureText(e));
    }
    if (paymentId == null) {
      if (mounted) setState(() => _sending = false);
      return;
    }
    // The money moved. Record it before anything else can fail (a funded
    // payment recorded and counted itself the moment it was accepted).
    if (ShareLinksStore.recordPaid(claim, paymentId)) {
      ShareLinkEvents.paid(claim.kind, claim.amountMinor);
    }
    try {
      await api.markPaid(claim.id, paymentId: paymentId);
      ShareLinksStore.put(
          ShareLinksStore.byId(claim.id)!.copyWith(paidReported: true));
    } catch (_) {
      // Reported by the next pass (ShareLinkClaims._reportUnreported).
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).maybePop();
  }

  /// How Dollars would be topped up for this link, on the figures in hand:
  /// null when they cover it or the link is no dollars one.
  GiftFundingPreview? _preview() {
    if (!_dollars || _sent) return null;
    final preview = giftFundingPreviewNow(
      ref.read,
      amountUsd: claim.amountMinor / 100,
      heldUsd:
          GiftFundingRunner.reservedUsd(except: claim.id, now: DateTime.now()),
      pendingUsd: _onItsWayUsd(),
      bitcoinSpread: _bitcoinSpread,
    );
    return preview.needsFunding || !preview.covers ? preview : null;
  }

  double _onItsWayUsd() {
    final funding = ShareLinksStore.byId(claim.id)?.funding;
    if (funding == null) return 0;
    var sum = 0.0;
    for (final s in funding.steps.legs) {
      if (s.id != kGiftFundingSendId && s.status == MoneyStepStatus.running) {
        sum += funding.landsUsd[s.id] ?? s.usd;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final local = ShareLinksStore.byId(claim.id);
    final name = local?.label?.trim() ?? '';
    final amount =
        shareLinkAmountLabel(context, ref, claim.kind, claim.amountMinor);
    final title = name.isEmpty
        ? l10n.shareClaimedPromptTitleUnnamed(amount)
        : l10n.shareClaimedPromptTitle(name, amount);
    if (_dollars) {
      // [_preview] reads these: a change redraws the funding lines.
      ref.watch(runtimeCapabilitiesProvider);
      ref.watch(usdBalanceProvider);
    }
    final funding = _dollars ? local?.funding : null;
    final steps = funding?.steps;
    // The money's steps in the mascot's place, while there are any to tell:
    // Sal is in them.
    final showSteps = steps != null && !steps.isEmpty && !_sent;
    final preview = showSteps && _sending ? null : _preview();
    final refusal = _dollars && preview != null && !preview.covers
        ? bitcoinToDollarsDenied(ref.read(runtimeCapabilitiesProvider))
            ?.messageIn(l10n)
        : null;
    return AppBottomSheetContainer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSteps)
              MoneyStepsView(
                key: const ValueKey('share-claimed-steps'),
                lines: moveStepLines(l10n, steps, money: formatDollars),
                graph: steps,
                toLabel: name.isEmpty ? null : name,
                money: formatDollars,
              )
            else
              Center(
                child: KuteMascot(
                  state: _sent
                      ? KuteState.incoming
                      : _sending
                          ? KuteState.outgoing
                          : KuteState.idle,
                  size: 72.sp,
                ),
              ),
            SizedBox(height: 16.h),
            Text(
              _sent ? l10n.shareLinkPaid : title,
              key: const ValueKey('share-claimed-title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.25,
              ),
            ),
            if (!_sent) ...[
              // Once the money is moving the steps say what is happening;
              // the approval this line asks for is behind the person.
              if (!(showSteps && _sending)) ...[
                SizedBox(height: 8.h),
                Text(
                  _error ?? refusal ?? l10n.shareClaimedPromptBody,
                  key: const ValueKey('share-claimed-body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _error != null || refusal != null
                        ? AppColors.error
                        : c.textSecondary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
              // What has to move first and what that costs, before the tap:
              // the steps' own line, the slips' own fee row.
              if (preview != null &&
                  preview.covers &&
                  preview.needsFunding &&
                  !_sending) ...[
                SizedBox(height: 16.h),
                // Steps on screen already say what moves: the fee alone.
                _FundingLines(preview: preview, feeOnly: showSteps),
              ],
              SizedBox(height: 24.h),
              // Later stays on the sheet, a text button above the bar.
              AppTextButton(
                key: const ValueKey('share-claimed-later'),
                text: l10n.shareLater,
                onPressed:
                    _sending ? null : () => Navigator.of(context).maybePop(),
              ),
              // THE BAR IS THE BUTTON (kute_bar_context.dart): Send now is
              // the floating Sal bar's primary action, busy while the
              // payment runs; the sheet keeps clear of it.
              KuteBarContextScope(
                barContext: KuteBarContext.primary(
                  label: l10n.shareSendNow,
                  onPrimary: _send,
                  enabled: !_sending,
                  busy: _sending,
                  source: 'share_claimed_prompt',
                  disabledLabel: null,
                ),
                child: SizedBox(height: kuteBarScrollClearance.h),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A short "Send now"'s funding before the tap: each leg in the steps' own
/// words, then the fee in the slips' own row (a tap lists it leg by leg).
class _FundingLines extends StatelessWidget {
  const _FundingLines({required this.preview, this.feeOnly = false});

  final GiftFundingPreview preview;
  final bool feeOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final style = TextStyle(
      color: c.textPrimary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w600,
      height: 1.4,
    );
    return Column(
      key: const ValueKey('share-claimed-funding'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!feeOnly && preview.bitcoinUsd > 0)
          Text(
            l10n.moneyStepMovingFromTo(
                formatDollars(preview.bitcoinUsd),
                moneyPlaceName(l10n, MoneyPlace.bitcoin),
                moneyPlaceName(l10n, MoneyPlace.dollars)),
            textAlign: TextAlign.center,
            style: style,
          ),
        if (!feeOnly)
          for (final p in preview.pulls)
            Text(
              l10n.moneyStepMovingFromTo(
                  formatDollars(p.usd),
                  venueCashVenueName(l10n, p.venue),
                  moneyPlaceName(l10n, MoneyPlace.dollars)),
              textAlign: TextAlign.center,
              style: style,
            ),
        if (!preview.fees.isEmpty) ...[
          SizedBox(height: 8.h),
          MoneyFeeSummary(
            key: const ValueKey('share-claimed-fee'),
            usd: preview.fees.totalUsd,
            label: l10n.slipMoveFee,
            details: [
              if (preview.fees.legs.length > 1)
                for (final leg in preview.fees.legs)
                  MoneyFeeSummary(
                      usd: leg.feeUsd,
                      label: fundingLegFeeLabel(l10n, leg.source)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Pays [claim] from the spending wallet behind the step-up, funding what
/// Dollars lack first ([GiftFundingRunner]). Resolves to the Spark payment
/// id, or null when the user declined the prompt. Throws when the payment
/// could not be prepared or was refused, or the funding stopped short.
Future<String?> payShareLinkClaim(
    BuildContext context, WidgetRef ref, ClaimedShareLink claim) async {
  if (claim.kind == ShareLinkKind.dollars) {
    final label =
        shareLinkAmountLabel(context, ref, claim.kind, claim.amountMinor);
    return ref.read(giftFundingRunnerProvider).pay(
          claim,
          approve: (intent) => context.mounted
              ? requireFreshAuthGrant(
                  context,
                  ref,
                  intent: intent,
                  reason: context.l10n.stepUpReasonSend(label),
                  amountUsd: claim.amountMinor / 100,
                )
              : Future<AuthGrant?>.value(),
        );
  }
  final destination = claim.claimDestination.trim();
  final isBolt11 = claim.kind == ShareLinkKind.bitcoin &&
      destination.toLowerCase().startsWith('ln');
  final walletId = HotSettlement.spendingWalletId(ref.read);
  final amountMax = BigInt.from(claim.amountMinor);
  final intent = SensitiveIntent(
    action: SensitiveAction.send,
    walletId: walletId,
    venue: isBolt11 ? 'lightning' : 'spark',
    destination: destination,
    asset: claim.kind.asset,
    amountMax: amountMax,
    limits: {
      IntentLimit.provider: 'share_link',
      IntentLimit.maxMode: false,
      'sourcePool': 'btc',
    },
  );
  final amountLabel =
      shareLinkAmountLabel(context, ref, claim.kind, claim.amountMinor);
  final grant = await requireFreshAuthGrant(
    context,
    ref,
    intent: intent,
    reason: context.l10n.stepUpReasonSend(amountLabel),
    amountUsd: null,
  );
  if (grant == null) return null;
  try {
    AuthGrants.consume(grant, intent);
  } on AuthGrantException {
    return null;
  }

  if (isBolt11) {
    final wrapper = await ref.read(prepareLightningPaymentProvider((
      address: destination,
      amount: claim.amountMinor,
      comment: null,
      isDraining: false,
    )).future);
    final prepared = wrapper.prepareResponse;
    if (prepared is! PrepareSendPaymentResponse) {
      throw StateError('Unexpected Lightning destination');
    }
    LedgerOperationScope.assertHotAllowed(HotSigningAction.sparkTransaction);
    final sdk = (await ref.read(breezSDKProvider.future)).instance;
    if (sdk == null) throw StateError('Spark wallet not connected');
    final response = await runSparkMutation(
        sdk,
        () => sdk.sendPayment(
            request: SendPaymentRequest(prepareResponse: prepared)));
    return response.payment.id;
  }
  final prepared = await ref.read(prepareGenericPaymentProvider((
    destination: destination,
    amountSats: claim.amountMinor,
    isDraining: false,
  )).future);
  final response =
      await ref.read(executeSparkTransactionProvider(prepared).future);
  return response.payment.id;
}
