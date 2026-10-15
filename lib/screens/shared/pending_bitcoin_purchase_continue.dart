// lib/screens/shared/pending_bitcoin_purchase_continue.dart
//
// The one-tap continue of a Buy bitcoin whose purchase from Dollars waits
// on the person (pending_bitcoin_purchase.dart): the approval ran out, it
// was declined, or the app restarted while the money came home. The
// move's Activity row says "Your $X is in Investments. Tap to buy
// Bitcoin" ([pendingPurchaseWaitingUsd]); the tap asks ONE fresh approval
// for exactly that purchase and hands it back to the finisher.
//
// A move with no record (an older build tied the purchase to the open
// sheet, so its money landed in Dollars and nothing bought) gets the same
// row and the same tap ([legacyPurchaseUsd]): the tap records the purchase
// from the move, for what landed, never more than the move's own amount,
// and only while Dollars hold all of it.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart'
    show AuthGrant, AuthGrants, SensitiveIntent;
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart' show DirectLegGrants;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/one_balance/dollars_to_bitcoin_purchase.dart'
    show kDollarsToBtcRoute;
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show kVenueCashOnwardMinimumUsd;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/tracking_service.dart';

/// Test seam: stands in for the fresh approval the continue asks.
@visibleForTesting
Future<AuthGrant?> Function(SensitiveIntent intent)?
    debugPendingPurchaseApproval;

double _floorCents(double usd) =>
    usd.isFinite && usd > 0 ? ((usd * 100) + 1e-6).floor() / 100 : 0;

/// What move [moveId]'s waiting purchase would buy now, when it waits on
/// the person and its money is in Dollars: the purchase's amount, never
/// more than Dollars hold. Null otherwise (nothing waits, it is running,
/// or what came home has not landed yet: the row stays Pending).
double? pendingPurchaseWaitingUsd(
    BitcoinPurchaseFinisher finisher, String moveId, double dollarsUsd) {
  final p = finisher.waitingOnApproval(moveId);
  if (p == null) return null;
  // A purchase made from a record-less move is all or nothing: its money
  // still in Dollars, or it is not offered.
  if (p.legacy) return legacyPurchaseUsd(p.usd, dollarsUsd);
  final usd = math.min(p.usd, _floorCents(dollarsUsd));
  return usd >= kVenueCashOnwardMinimumUsd ? usd : null;
}

/// What a record-less move's missing purchase ([usd]: what landed in
/// Dollars for it, capped at its own amount) would buy now: all of it
/// while Dollars hold it, else null (the money was spent since; nothing
/// the balance cannot cover is offered).
double? legacyPurchaseUsd(double usd, double dollarsUsd) {
  final amount = _floorCents(usd);
  if (amount < kVenueCashOnwardMinimumUsd) return null;
  return dollarsUsd + 0.005 >= amount ? amount : null;
}

/// Asks one fresh approval for move [moveId]'s waiting purchase and hands
/// it to the finisher, which buys at once (the money is in Dollars).
/// Declined: nothing moves, the row keeps saying so.
///
/// [legacyUsd]: the move has no record (its purchase never went and no
/// finisher ever owned it); what landed in Dollars for it, capped at its
/// own amount. The tap records the purchase from the move first, so it
/// follows the same path from here on.
Future<void> continuePendingBitcoinPurchase(
    BuildContext context, WidgetRef ref, String moveId,
    {double? legacyUsd, String? moveWalletId}) async {
  final finisher = ref.read(bitcoinPurchaseFinisherProvider);
  if (finisher.running(moveId)) return;
  final dollars = ref.read(usdBalanceProvider);
  if (PendingBitcoinPurchaseStore.get(moveId) == null) {
    if (legacyUsd == null) return;
    final usd = legacyPurchaseUsd(legacyUsd, dollars);
    if (usd == null) return;
    PendingBitcoinPurchaseStore.put(PendingBitcoinPurchase(
      moveId: moveId,
      walletId: moveWalletId,
      usd: usd,
      createdAt: DateTime.now(),
      stage: PendingPurchaseStage.needsApproval,
      legacy: true,
    ));
  }
  final usd = pendingPurchaseWaitingUsd(finisher, moveId, dollars);
  if (usd == null) return;
  final legacy = PendingBitcoinPurchaseStore.get(moveId)?.legacy ?? false;
  final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
  if (walletId == null || walletId.isEmpty) return;
  final String ownSpark = await ref.read(sparkSelfAddressProvider.future);
  if (ownSpark.isEmpty || !context.mounted) return;
  TrackingService.track('move_purchase_continue_tapped', params: {
    'amount_usd': usd,
    if (legacy) 'legacy': true,
  });
  final intent = DirectLegGrants.buyBitcoin(
    walletId: walletId,
    ownSpark: ownSpark,
    route: kDollarsToBtcRoute.label,
    asset: kOrchestraUsdAssetCode,
    totalUsd: usd,
    directLegs: null,
    ttl: AuthGrants.autofireTtl,
  );
  final seam = debugPendingPurchaseApproval;
  final amount = '\$${usd.toStringAsFixed(2)}';
  final grant = seam != null
      ? await seam(intent)
      : await requireFreshAuthGrant(
          context,
          ref,
          intent: intent,
          reason: context.l10n.stepUpReasonSend(amount),
          amountUsd: usd,
        );
  if (grant == null) return;
  unawaited(finisher.start(
      moveId: moveId,
      usd: usd,
      grant: grant,
      walletId: walletId,
      resumed: true,
      legacy: legacy));
}
