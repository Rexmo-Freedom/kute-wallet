// lib/screens/shared/pending_bitcoin_purchase_continue.dart
//
// The one-tap continue of a Buy bitcoin whose purchase from Dollars waits
// on the person (pending_bitcoin_purchase.dart): the approval ran out, it
// was declined, or the app restarted while the money came home. The
// move's Activity row says "Your $X is in Investments. Tap to buy
// Bitcoin" ([pendingPurchaseWaitingUsd]); the tap asks ONE fresh approval
// for exactly that purchase and hands it back to the finisher.

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
  final usd = math.min(p.usd, _floorCents(dollarsUsd));
  return usd >= kVenueCashOnwardMinimumUsd ? usd : null;
}

/// Asks one fresh approval for move [moveId]'s waiting purchase and hands
/// it to the finisher, which buys at once (the money is in Dollars).
/// Declined: nothing moves, the row keeps saying so.
Future<void> continuePendingBitcoinPurchase(
    BuildContext context, WidgetRef ref, String moveId) async {
  final finisher = ref.read(bitcoinPurchaseFinisherProvider);
  final usd =
      pendingPurchaseWaitingUsd(finisher, moveId, ref.read(usdBalanceProvider));
  if (usd == null) return;
  final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
  if (walletId == null || walletId.isEmpty) return;
  final String ownSpark = await ref.read(sparkSelfAddressProvider.future);
  if (ownSpark.isEmpty || !context.mounted) return;
  TrackingService.track('move_purchase_continue_tapped', params: {
    'amount_usd': usd,
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
      resumed: true));
}
