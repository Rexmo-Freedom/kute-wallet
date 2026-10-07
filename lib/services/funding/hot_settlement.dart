// lib/services/funding/hot_settlement.dart
//
// Riverpod glue for the hot settlement flows (Phase 5 plan P5.7). Keeps
// each call site's change mechanical: the flow keeps its own quote request,
// payment and Activity row code, and this file supplies the runner, the
// pinned wallet id, route availability, ownership and error copy.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show BreezSdk, PrepareSendPaymentResponse, SendPaymentMethod_SparkAddress,
        SendPaymentRequest;
import 'package:kute/helpers/user_error_copy.dart' show readsAsUserCopy;
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/breez/error_handling.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/polymarket/hot_withdrawal_guard.dart'
    show EarlierPolymarketWithdrawalPending, PendingPolymarketWithdrawal;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/balance_provider.dart'
    show WalletBalanceCacheNotifier, walletBalanceCacheProvider;
import 'package:kute/providers/breez_provider.dart'
    show
        prepareGenericPaymentProvider,
        prepareSparkTokenPaymentProvider,
        reflectAcceptedSparkSend;
import 'package:kute/providers/usdb_provider.dart'
    show sparkTokenIdentifierFor;
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show selectedCurrencyProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart'
    show orchestraSupportedRoutesProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/funding/settlement_quote_policy.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/security/address_guard.dart' show sameSparkAddress;

class _PreparedSparkSettlement {
  const _PreparedSparkSettlement(
      this.walletId, this.wrapper, this.sdk, this.response);

  final String walletId;
  final BreezSdkSpark wrapper;
  final BreezSdk sdk;
  final PrepareSendPaymentResponse response;
}

class HotSettlement {
  HotSettlement._();

  static Future<SettlementRunner>? _runner;

  /// The app-wide runner. One instance, so a quote verified before a review
  /// tap can be paid after it.
  static Future<SettlementRunner> runner() {
    return _runner ??= SettlementStore.shared()
        .then((store) => SettlementRunner(store: store))
        .catchError((Object e) {
      _runner = null;
      throw e;
    });
  }

  /// The spending wallet the operation is pinned to.
  static String spendingWalletId(ProviderReader read) {
    final id = pickSpendingWallet(read(settingsProvider))?.id;
    if (id == null || id.isEmpty) {
      throw const WalletGuardException(WalletGuardReason.ownAddressUnavailable,
          field: 'wallet');
    }
    return id;
  }

  static SettlementPayer payerFor(RouteKey route) => route.fromChain == 'spark'
      ? SettlementPayer.sparkHot
      : SettlementPayer.polygonRelayer;

  /// Route availability (B2) for a hot wallet. A route that needs a live
  /// catalog forces one refresh when the catalog is older than 15 min.
  static Future<RouteAvailability> availability(
      ProviderReader read, RouteKey route) async {
    final req = routeRequirementFor(route, ledgerWallet: false);
    final catalog = req == RouteRequirement.live
        ? await read(orchestraSupportedRoutesProvider.notifier)
            .refreshIfOlderThan(kMoneyCatalogMaxAge)
        : read(orchestraSupportedRoutesProvider);
    return catalog.availability(route, req: req, now: DateTime.now());
  }

  /// A verified quote through the Phase 2 gate, with the response's clock
  /// skew and transport retries on [idempotencyKey].
  static Future<SettlementQuoteResult> quote(
    ProviderReader read,
    OrchestraQuoteRequest request, {
    required String flow,
    required String idempotencyKey,
  }) async {
    final fetched = await OrchestraQuoteGate.fetchVerifiedWithSkew(
      request,
      OrchestraQuoteGate.boundsFor(request,
          usdPerBtc: read(selectedCurrencyProvider('USD')).toDouble()),
      flow: flow,
      idempotencyKey: idempotencyKey,
    );
    return SettlementQuoteResult(fetched.quote, skew: fetched.skew);
  }

  /// A plan for a hot flow between two of the wallet's own accounts, or to
  /// an external recipient when [destination] is null.
  static SettlementPlan plan(
    ProviderReader read, {
    required SettlementFlow flow,
    required RouteKey route,
    required SettlementAccountKind source,
    required SettlementAccountKind? destination,
    required Future<SettlementQuoteResult> Function(String idempotencyKey)
        requestQuote,
    required Future<SettlementFundingProof> Function(
            VerifiedOrchestraQuote quote, Object? prepared)
        fund,
    Future<Object?> Function(VerifiedOrchestraQuote quote, String operationId)?
        prepareFunding,
    Future<SettlementReviewDecision> Function(VerifiedOrchestraQuote quote,
            {required bool refreshed})?
        review,
    String? externalRecipient,
    double? amountUsd,
    String? walletId,
    SettlementStepUpHook? stepUp,
  }) {
    final pinned = walletId ?? spendingWalletId(read);
    final resolver = OwnedAddressResolver(ProviderOwnedAddressSources(read));
    return SettlementPlan(
      walletId: pinned,
      flow: flow,
      route: route,
      sourceAccount: source,
      destinationAccount: destination,
      payer: payerFor(route),
      amountUsd: amountUsd,
      checkAvailability: () => availability(read, route),
      resolveOwnership: () => destination == null
          ? resolver.resolveExternalSend(
              walletId: pinned,
              route: route,
              source: source,
              recipientAddress: externalRecipient ?? '',
            )
          : resolver.resolve(
              walletId: pinned,
              route: route,
              source: source,
              destination: destination,
            ),
      requestQuote: requestQuote,
      review: review,
      prepareFunding: prepareFunding,
      fund: fund,
      // Phase 1b: the flow binds its step-up grant here. Flows that pass
      // no hook keep their own approval upstream.
      stepUp: stepUp,
    );
  }

  /// Prepares a Spark payment of the quoted amount to the quote's deposit
  /// address. Moves nothing.
  ///
  /// WHICH BALANCE PAYS is decided here and nowhere else, from the source
  /// asset the quote was VERIFIED against (`quote.request`, which the
  /// quote guard has already echo-checked against Flashnet's own reply).
  /// A dollar-token source funds from the token balance in the token's own
  /// base units; anything else funds from bitcoin in satoshis. The two
  /// units are never converted into one another, and a failure on one path
  /// never retries on the other.
  static Future<Object?> prepareSpark(
      ProviderReader read, VerifiedOrchestraQuote quote) async {
    final walletId = spendingWalletId(read);
    final wrapper = await read(breezSDKProvider.future);
    final sdk = wrapper.instance;
    if (sdk == null || spendingWalletId(read) != walletId) {
      throw const WalletGuardException(WalletGuardReason.ownAddressUnavailable,
          field: 'wallet_changed');
    }
    // Null means "this is a satoshi send". It is a decision, not a
    // fallback: the echo check below holds it against the SDK's reply.
    final requestedToken = sparkTokenIdentifierFor(
        quote.request.sourceChain, quote.request.sourceAsset);
    final response = requestedToken == null
        ? await read(prepareGenericPaymentProvider((
            destination: quote.depositAddress,
            amountSats: quote.amountIn.toInt(),
            isDraining: false,
          )).future)
        : await read(prepareSparkTokenPaymentProvider((
            destination: quote.depositAddress,
            // Base units of the token itself (six decimals for dollars),
            // exactly as the verified quote asked for them. Not sats.
            amountBaseUnits: quote.amountIn,
            tokenIdentifier: requestedToken,
          )).future);
    if (spendingWalletId(read) != walletId ||
        !identical(wrapper.instance, sdk)) {
      throw const WalletGuardException(WalletGuardReason.ownAddressUnavailable,
          field: 'wallet_changed');
    }
    if (response.amount != quote.amountIn) {
      throw const WalletGuardException(WalletGuardReason.amountMismatch);
    }
    final method = response.paymentMethod;
    if (method is! SendPaymentMethod_SparkAddress ||
        !sameSparkAddress(method.address, quote.depositAddress)) {
      throw const WalletGuardException(WalletGuardReason.echoMismatch,
          field: 'deposit_address');
    }
    // The token echo, on BOTH the response and the method, against the
    // exact identifier that was asked for. Equality, never presence: a
    // bitcoin send must echo no token at all (requestedToken is null), and
    // a dollar send that echoed some OTHER token would spend some other
    // balance for the same quoted amount.
    if (response.tokenIdentifier != requestedToken ||
        method.tokenIdentifier != requestedToken) {
      throw const WalletGuardException(WalletGuardReason.echoMismatch,
          field: 'token_identifier');
    }
    return _PreparedSparkSettlement(walletId, wrapper, sdk, response);
  }

  /// Sends a payment [prepareSpark] prepared and returns its payment id.
  /// Only call from a plan's `fund` callback.
  static Future<String> sendSpark(ProviderReader read, Object? prepared) async {
    LedgerOperationScope.assertHotAllowed(HotSigningAction.sparkTransaction);
    if (prepared is! _PreparedSparkSettlement ||
        spendingWalletId(read) != prepared.walletId ||
        !identical(prepared.wrapper.instance, prepared.sdk)) {
      throw const WalletGuardException(WalletGuardReason.ownAddressUnavailable,
          field: 'wallet_changed');
    }
    // Use the exact SDK that prepared this payment. No asynchronous provider
    // lookup may substitute another spending wallet between this check/send.
    try {
      // The balance shown before the send, for its hold below. Display
      // only: a reader without the cache never stops the send.
      WalletBalanceCacheNotifier? cache;
      var before = 0;
      try {
        final notifier = read(walletBalanceCacheProvider.notifier);
        before = notifier.shownSparkSats(prepared.walletId);
        cache = notifier;
      } catch (_) {
        cache = null;
      }
      final response = await prepared.sdk.sendPayment(
          request: SendPaymentRequest(prepareResponse: prepared.response));
      // A bitcoin send shows in the balance at once (a dollar send holds
      // nothing: `sparkSendDebit` is null for a token transfer).
      if (cache != null) {
        try {
          reflectAcceptedSparkSend(cache, prepared.sdk,
              walletId: prepared.walletId,
              prepared: prepared.response,
              paymentId: response.payment.id,
              balanceBeforeSats: before);
        } catch (_) {}
      }
      return response.payment.id;
    } catch (error) {
      handlePaymentException(error);
    }
  }

  /// Copy for a settlement error, or null when the caller's own message
  /// applies.
  static String? messageFor(Object error, AppLocalizations l10n) {
    if (error is SettlementFundingUnknown) {
      // A relayer that has the transaction and has not settled it yet is
      // not an outcome nobody can account for. Saying so to somebody
      // whose withdrawal is plainly on its way reads as money lost.
      if (error.cause is PendingPolymarketWithdrawal) {
        return l10n.withdrawalStillSettlingBody;
      }
      return l10n.settlementFundingUnknownBody;
    }
    if (error is SettlementStopped) {
      switch (error.reason) {
        case SettlementStopReason.blockedPending:
          return l10n.settlementBlockedPending;
        case SettlementStopReason.routeUnavailable:
          return l10n.routeUnavailableNothingSent;
        case SettlementStopReason.quoteExpired:
          return l10n.settlementExpiredNothingSent;
        case SettlementStopReason.quoteReplaced:
          return l10n.settlementQuoteChangedConfirmAgain;
        case SettlementStopReason.declined:
          return null;
      }
    }
    if (error is EarlierPolymarketWithdrawalPending) {
      return l10n.withdrawalEarlierStillSettlingBody;
    }
    if (error is WalletGuardException) return error.messageFor(l10n);
    if (error is OrchestraQuoteFailure) {
      final mapped = error.routeError?.messageFor(l10n);
      if (mapped != null) return mapped;
      // A refusal whose code this app does not recognise still arrives
      // with the provider's own sentence. Throwing that away left the
      // caller on a generic "could not be completed", which says nothing
      // and, worse, implies the outcome is in doubt when the quote was
      // refused and nothing was sent.
      final provider = error.message.trim();
      return readsAsUserCopy(provider) ? provider : null;
    }
    return null;
  }

  /// Whether funds may have left when [error] was thrown by a run.
  static bool fundsMayHaveMoved(Object error) =>
      error is SettlementFundingUnknown;
}
