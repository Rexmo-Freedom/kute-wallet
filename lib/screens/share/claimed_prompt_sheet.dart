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
// A failure after the SDK accepted the payment is still a payment: the
// payment id is stored at once and `POST /paid` is retried by the next
// pass, never the send.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show PrepareSendPaymentResponse, SendPaymentRequest;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
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
        prepareLightningPaymentProvider,
        prepareSparkTokenPaymentProvider;
import 'package:kute/providers/usdb_provider.dart' show usdbTokenIdentifier;
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_mascot.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/funding/hot_settlement.dart' show HotSettlement;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';
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

  ClaimedShareLink get claim => widget.claim;

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final pay = ClaimedPromptSheet.debugPayer ?? payShareLinkClaim;
    String? paymentId;
    try {
      paymentId = await pay(context, ref, claim);
    } catch (_) {
      paymentId = null;
      if (mounted) setState(() => _error = context.l10n.shareSendFailed);
    }
    if (paymentId == null) {
      if (mounted) setState(() => _sending = false);
      return;
    }
    // The money moved. Record it before anything else can fail.
    final local = ShareLinksStore.byId(claim.id);
    ShareLinksStore.put((local ??
            PendingShareLink(
              id: claim.id,
              kind: claim.kind,
              amountMinor: claim.amountMinor,
              marketSlug: claim.marketSlug,
              url: '',
              createdAt: DateTime.now(),
              status: ShareLinkStatus.paid,
            ))
        .copyWith(status: ShareLinkStatus.paid, paymentId: paymentId));
    ShareLinkEvents.paid(claim.kind, claim.amountMinor);
    try {
      await ref
          .read(shareLinksApiProvider)
          .markPaid(claim.id, paymentId: paymentId);
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
    return AppBottomSheetContainer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              SizedBox(height: 8.h),
              Text(
                _error ?? l10n.shareClaimedPromptBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _error != null ? AppColors.error : c.textSecondary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 24.h),
              AppButton(
                key: const ValueKey('share-claimed-send-now'),
                text: l10n.shareSendNow,
                isLoading: _sending,
                onPressed: _sending ? null : _send,
              ),
              SizedBox(height: 8.h),
              AppTextButton(
                key: const ValueKey('share-claimed-later'),
                text: l10n.shareLater,
                onPressed:
                    _sending ? null : () => Navigator.of(context).maybePop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pays [claim] from the spending wallet behind the step-up. Resolves to
/// the Spark payment id, or null when the user declined the prompt.
/// Throws when the payment could not be prepared or was refused.
Future<String?> payShareLinkClaim(
    BuildContext context, WidgetRef ref, ClaimedShareLink claim) async {
  final destination = claim.claimDestination.trim();
  final isBolt11 = claim.kind == ShareLinkKind.bitcoin &&
      destination.toLowerCase().startsWith('ln');
  final walletId = HotSettlement.spendingWalletId(ref.read);
  final amountMax = claim.kind == ShareLinkKind.dollars
      ? dollarsBaseUnitsFromCents(claim.amountMinor)
      : BigInt.from(claim.amountMinor);
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
      'sourcePool': claim.kind == ShareLinkKind.dollars ? 'usd' : 'btc',
    },
  );
  final amountLabel =
      shareLinkAmountLabel(context, ref, claim.kind, claim.amountMinor);
  final grant = await requireFreshAuthGrant(
    context,
    ref,
    intent: intent,
    reason: context.l10n.stepUpReasonSend(amountLabel),
    amountUsd:
        claim.kind == ShareLinkKind.dollars ? claim.amountMinor / 100 : null,
  );
  if (grant == null) return null;
  try {
    AuthGrants.consume(grant, intent);
  } on AuthGrantException {
    return null;
  }

  if (claim.kind == ShareLinkKind.dollars) {
    final prepared = await ref.read(prepareSparkTokenPaymentProvider((
      destination: destination,
      amountBaseUnits: amountMax,
      tokenIdentifier: usdbTokenIdentifier,
    )).future);
    final response =
        await ref.read(executeSparkTransactionProvider(prepared).future);
    return response.payment.id;
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
