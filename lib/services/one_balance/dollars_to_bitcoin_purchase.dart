// lib/services/one_balance/dollars_to_bitcoin_purchase.dart
//
// The purchase of bitcoin from the spending account's Dollars:
// `spark:USDB` → `spark:BTC`, both ends the wallet's own Spark address.
// One function for both callers so the money path is the same wherever
// it runs:
//
//  * the Move sheet's "Buy bitcoin" from Dollars, while the sheet is up;
//  * the purchase that finishes a Buy bitcoin whose venue cash came home
//    to Dollars first (pending_bitcoin_purchase.dart), after the sheet
//    has closed, under the Buy's one approval.
//
// It reads providers through the app's container ([ProviderReader]), never
// through a widget, so it keeps working once the sheet is gone.

import 'package:kute/helpers/auth_grant.dart'
    show AuthGrant, AuthGrantException, AuthGrants;
import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDouble;
import 'package:kute/helpers/venue_intents.dart'
    show DirectLegGrants, GrantGuard;
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart'
    show SettlementAccountKind, SettlementFlow;
import 'package:kute/models/swap_order_model.dart' show SwapOrder;
import 'package:kute/providers/currency_conversions_provider.dart'
    show selectedCurrencyProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/fee_history_service.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_registration.dart'
    show followSettlementRegistration, withSettlementOrderId;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingProof, SettlementStepUpHook;
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart'
    show OrchestraQuoteRequest, RecipientKind, kManualMoveQuoteTag;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/tracking_service.dart';

/// The route a purchase from Dollars takes.
final RouteKey kDollarsToBtcRoute = RouteKey(
    fromChain: kOrchestraUsdChain,
    fromAsset: kOrchestraUsdAssetCode,
    toChain: 'spark',
    toAsset: 'BTC');

/// What a purchase from Dollars sent.
class DollarsToBitcoinSent {
  const DollarsToBitcoinSent({
    required this.sentUsd,
    required this.registered,
    required this.operationId,
  });

  /// The dollars that left (the verified quote's amount in).
  final double sentUsd;

  /// Orchestra knew the order before this returned (else it is being
  /// registered in the background).
  final bool registered;

  /// The settlement operation of the purchase.
  final String operationId;
}

/// The purchase's step-up under the approval it already has ([grant], the
/// Buy's one approval, `DirectLegGrants.buyBitcoin`): no second prompt.
/// Accepted only for the own Spark address and the route it binds and no
/// more than approved; consumed right before the runner pays.
SettlementStepUpHook approvedPurchaseStepUp(AuthGrant grant) => (auth) async {
      final sep = auth.destination.lastIndexOf('|');
      final recipient =
          sep < 0 ? auth.destination : auth.destination.substring(0, sep);
      if (!DirectLegGrants.coversPurchase(grant,
          walletId: auth.walletId,
          recipient: recipient,
          routeLabel: auth.routeLabel,
          amountIn: auth.amountIn)) {
        return false;
      }
      try {
        AuthGrants.consume(
            grant, GrantGuard.derive(grant, amountMax: auth.amountIn));
        return true;
      } on AuthGrantException {
        return false;
      }
    };

/// Buys bitcoin with [amountBaseUnits] of the dollar token ([usd] in
/// dollars) under [stepUp], and books it exactly as the Move sheet always
/// has: the exchange row, the move's one row ([moveId]: the purchase is
/// its last step), the registration followed in the background, the
/// backend attribution, the fee and `convert_success`.
///
/// Returns once the dollars are SENT (the registration runs in the
/// background): never waits for the bitcoin to land. [onQuoting] hears the
/// quote being asked, [onFunding] the moment the dollars are handed to the
/// send (anything thrown before it moved nothing).
Future<DollarsToBitcoinSent> buyBitcoinFromDollars(
  ProviderReader read, {
  required BigInt amountBaseUnits,
  required double usd,
  required SettlementStepUpHook stepUp,
  String? moveId,
  void Function()? onQuoting,
  void Function()? onFunding,
}) async {
  // Both legs settle on the wallet's own Spark address, and a failed
  // swap refunds to that same address. Resolution failure throws BEFORE
  // anything moves.
  final sparkAddress = await read(sparkSelfAddressProvider.future);
  final ownSpark = await read(sparkSelfAddressProvider.future);
  final runner = await HotSettlement.runner();
  final settled = await runner.run(HotSettlement.plan(
    read,
    flow: SettlementFlow.moveDollarsToBtc,
    route: kDollarsToBtcRoute,
    source: SettlementAccountKind.sparkHot,
    destination: SettlementAccountKind.sparkHot,
    amountUsd: usd,
    stepUp: stepUp,
    requestQuote: (key) {
      onQuoting?.call();
      return HotSettlement.quote(
        read,
        OrchestraQuoteRequest(
          sourceChain: kOrchestraUsdChain,
          sourceAsset: kOrchestraUsdAssetCode,
          destinationChain: 'spark',
          destinationAsset: 'BTC',
          amountBaseUnits: amountBaseUnits,
          recipientAddress: sparkAddress,
          refundAddress: sparkAddress,
          recipientKind: RecipientKind.ownSpark,
          ownAddress: ownSpark,
          tag: kManualMoveQuoteTag,
        ),
        flow: 'move_buy_bitcoin_dollars',
        idempotencyKey: key,
      );
    },
    // The token echo lives in `prepareSpark`: it funds from the dollar
    // balance because the VERIFIED quote's source asset says so, and
    // refuses outright if the SDK echoes anything else. A failure here
    // never retries on satoshis.
    prepareFunding: (verifiedQuote, _) =>
        HotSettlement.prepareSpark(read, verifiedQuote),
    registerInBackground: true,
    fund: (verifiedQuote, prepared) async {
      onFunding?.call();
      final paymentId = await HotSettlement.sendSpark(read, prepared);
      PolymarketSparkTxsService.tag(paymentId);
      return SettlementFundingProof.spark(paymentId);
    },
  ));
  final orchQuote = settled.quote.quote;
  final sentUsd = settled.quote.amountIn.toDouble() / 1e6;
  final orderId = settled.orderId ?? orchQuote.quoteId;
  final estOut =
      orchestraAmountToDouble(orchQuote.estimatedOut, 'BTC', chain: 'spark');

  // The deposit leg is written in DOLLARS (two decimals) — writing it
  // with the bitcoin divisor is the bug the dollar rows exist to make
  // impossible.
  final exchange = SwapOrder(
    id: orderId,
    coinFrom: kOrchestraUsdAssetCode,
    networkFrom: 'SPARK',
    coinTo: 'BTC',
    networkTo: 'SPARK',
    depositAddress: orchQuote.depositAddress,
    depositAmount: sentUsd.toStringAsFixed(2),
    withdrawalAmount: estOut.toStringAsFixed(8),
    status: 'exchanging',
    timestamp: DateTime.now().millisecondsSinceEpoch,
    withdrawalAddress: sparkAddress,
    depositMin: '0',
    depositMax: '0',
    rate: '0',
    refundAddress: sparkAddress,
    provider: 'Orchestra',
    walletId: read(settingsProvider).activeWalletId,
    operationId: settled.operation.operationId,
  );
  // The purchase is the last leg of its multi-source move: one row.
  MultiSourceMoveStore.attachFinal(moveId, settled.operation.operationId);
  await read(swapOrdersProvider.notifier).addExchange(exchange);
  followSettlementRegistration(read, settled);
  // Backend attribution for the REAL order only — a quote id (q_…) would
  // create a row the completion can never reconcile with.
  if (orderId.startsWith('ord_')) {
    // ignore: unawaited_futures
    AffiliateService.logProviderEvent(
      provider: 'orchestra',
      providerOrderId: orderId,
      status: 'pending',
      sourceAsset: kOrchestraUsdAssetCode,
      sourceAmount: sentUsd,
      destinationAsset: 'BTC',
      destinationAmount: estOut,
    );
  }
  read(walletTransactionCacheProvider.notifier).mergeSwapOrder(exchange);
  BackgroundSyncService().syncNow();

  final feeWalletId = read(settingsProvider).activeWalletId;
  final usdPerBtc = read(selectedCurrencyProvider('usd')).toDouble();
  withSettlementOrderId(settled, (orderId) {
    // Orchestra's spread on the leg, against the live BTC price. The
    // dollars that left are the reference, so the fair bitcoin is
    // `sentUsd / price` and anything short of it is the spread.
    try {
      if (usdPerBtc > 0 && usdPerBtc.isFinite) {
        final spreadUsd = sentUsd - (estOut * usdPerBtc);
        if (spreadUsd > 0) {
          FeeHistoryService.log(
            id: 'orch-$orderId',
            kind: FeeKind.orchestraSpread,
            microUsd: (spreadUsd * 1000000).round(),
            nativeAmount: spreadUsd.toStringAsFixed(6),
            nativeUnit: 'usd',
            source: 'Orchestra',
            txId: orderId,
            walletId: feeWalletId,
          );
        }
      }
    } catch (_) {}

    TrackingService.track('convert_success', params: {
      'direction': 'dollars_to_btc',
      'amount_bucket': TrackingService.usdBucket(sentUsd),
      ...TrackingService.exactUsd('amount_usd', sentUsd),
      'order_id': orderId,
      'provider': 'orchestra',
    });
  });
  return DollarsToBitcoinSent(
    sentUsd: sentUsd,
    registered: settled.registered,
    operationId: settled.operation.operationId,
  );
}
