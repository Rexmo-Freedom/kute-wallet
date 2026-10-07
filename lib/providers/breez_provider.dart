import 'dart:async';

import 'package:kute/services/spark_deposit_actions.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart' show pickSpendingWallet;
import 'package:kute/models/breez/error_handling.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/models/breez/lnurl_service.dart';
import 'package:kute/models/breez/lnurl_webhook_manager.dart';
import 'package:kute/models/breez/username_utilities.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

enum AnalyzedPaymentType { lightning, bitcoin, spark, lnurl, bip21, unknown }

class FeeDetail {
  final String label;
  final int amountSats;

  FeeDetail({required this.label, required this.amountSats});
}

class PrepareLightningPaymentResponse {
  final dynamic prepareResponse;
  final int networkFee;

  PrepareLightningPaymentResponse({
    required this.prepareResponse,
    required this.networkFee,
  });
}

// SDK responses are immutable, but the current wallet/SDK can change while a
// review or biometric prompt is open. Retain their original signing context.
final _preparedPaymentBindings = Expando<_PaymentSdkBinding>();

class _PaymentSdkBinding {
  const _PaymentSdkBinding(this.walletId, this.wrapper, this.sdk);

  final String walletId;
  final BreezSdkSpark wrapper;
  final BreezSdk sdk;

  void check(Ref ref) {
    if (pickSpendingWallet(ref.read(settingsProvider))?.id != walletId ||
        !identical(wrapper.instance, sdk)) {
      throw StateError('The spending wallet changed. Review the payment again.');
    }
  }
}

Future<_PaymentSdkBinding> _paymentSdkBinding(Ref ref) async {
  final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
  if (walletId == null || walletId.isEmpty) {
    throw StateError('No spending wallet is available.');
  }
  final wrapper = await ref.watch(breezSDKProvider.future);
  final sdk = wrapper.instance;
  if (sdk == null) throw StateError('The spending wallet is disconnected.');
  final binding = _PaymentSdkBinding(walletId, wrapper, sdk);
  binding.check(ref);
  return binding;
}

_PaymentSdkBinding _preparedPaymentBinding(Ref ref, Object response) {
  final binding = _preparedPaymentBindings[response];
  if (binding == null) {
    throw StateError('Prepare the payment again before sending.');
  }
  binding.check(ref);
  return binding;
}

/// What a prepared Spark send takes out of the spending wallet's BITCOIN
/// balance, in sats: the whole amount when the fee comes out of it
/// (`feesIncluded`, a 100% send), else the amount plus the fee. [feeSats]
/// is the fee part, at [speed] for an on-chain exit.
///
/// Null when the send does not spend the bitcoin balance this way: a
/// dollar-token send, or one funded by a token conversion.
({int debitSats, int feeSats})? sparkSendDebit(
  Object prepared, {
  OnchainConfirmationSpeed speed = OnchainConfirmationSpeed.fast,
}) {
  if (prepared is PrepareSendPaymentResponse) {
    if (prepared.tokenIdentifier != null ||
        prepared.conversionEstimate != null) {
      return null;
    }
    final amount = prepared.amount.toInt();
    final fee = sparkPreparedFeeSats(prepared, speed);
    return (
      debitSats:
          prepared.feePolicy == FeePolicy.feesIncluded ? amount : amount + fee,
      feeSats: fee,
    );
  }
  if (prepared is PrepareLnurlPayResponse) {
    if (prepared.conversionEstimate != null) return null;
    final amount = prepared.amountSats.toInt();
    final fee = prepared.feeSats.toInt();
    return (
      debitSats:
          prepared.feePolicy == FeePolicy.feesIncluded ? amount : amount + fee,
      feeSats: fee,
    );
  }
  return null;
}

/// Shows a send the SDK just accepted in the spending wallet's balance at
/// once, then has the SDK catch its own figure up.
///
/// The Breez SDK (0.26, client runtime) answers `getInfo()` from a cached
/// balance it refreshes on `PaymentSucceeded`, a claimed deposit, an
/// incoming payment or its own wallet sync (every 60 s). A send accepted
/// as PENDING (an on-chain exit always is) only emits `PaymentPending`,
/// which refreshes nothing, so `getInfo()` keeps counting the coins that
/// left for up to a minute or more. [balanceBeforeSats] is the balance
/// shown just before the send; the shown balance drops to it less the
/// send at once, and a forced `syncWallet` (which rewrites the SDK's
/// cached balance from its leaves) then hands the SDK's own figure back.
///
/// Never throws: the send already happened, and a display refresh that
/// fails must not report it as failed.
void reflectAcceptedSparkSend(
  WalletBalanceCacheNotifier cache,
  BreezSdk sdk, {
  required String walletId,
  required Object prepared,
  required String paymentId,
  required int balanceBeforeSats,
  OnchainConfirmationSpeed speed = OnchainConfirmationSpeed.fast,
}) {
  try {
    final debit = sparkSendDebit(prepared, speed: speed);
    if (debit == null) return;
    cache.holdOutgoingSparkSend(
      walletId,
      key: paymentId,
      balanceBeforeSats: balanceBeforeSats,
      debitSats: debit.debitSats,
      feeSats: debit.feeSats,
    );
    unawaited(_catchUpSparkBalance(cache, sdk, walletId, paymentId));
  } catch (_) {
    // Display only.
  }
}

Future<void> _catchUpSparkBalance(WalletBalanceCacheNotifier cache,
    BreezSdk sdk, String walletId, String paymentId) async {
  try {
    await sdk
        .syncWallet(request: const SyncWalletRequest())
        .timeout(const Duration(seconds: 20));
    final info = await sdk.getInfo(request: const GetInfoRequest());
    cache.settleOutgoingSparkSend(
        walletId, paymentId, info.balanceSats.toInt());
  } catch (_) {
    // Offline or slow: the hold stays until the SDK figure shows the
    // send, the payment fails or completes, or the hold expires.
  }
}

final parseInputProvider = FutureProvider.family<InputType, String>((ref, input) async {
  final sdkWrapper = await ref.watch(breezSDKProvider.future);
  try {
    return await sdkWrapper.instance!.parse(input: input);
  } catch (e) {
    handlePaymentException(e);
  }
});

/// Helps the Camera/UI decide where to route the user based on input type.
final identifyInputTypeProvider = FutureProvider.family<AnalyzedPaymentType, String>((ref, input) async {
  if (input.isEmpty) return AnalyzedPaymentType.unknown;
  try {
    final sdkWrapper = await ref.watch(breezSDKProvider.future);
    final parsed = await sdkWrapper.instance!.parse(input: input);

    if (parsed is InputType_Bolt11Invoice || parsed is InputType_Bolt12Offer) {
      return AnalyzedPaymentType.lightning;
    } else if (parsed is InputType_LnurlPay ||
        parsed is InputType_LnurlAuth ||
        parsed is InputType_LnurlWithdraw ||
        parsed is InputType_LightningAddress) {
      return AnalyzedPaymentType.lnurl;
    } else if (parsed is InputType_Bip21) {
      return AnalyzedPaymentType.bip21;
    } else if (parsed is InputType_BitcoinAddress) {
      return AnalyzedPaymentType.bitcoin;
    } else if (parsed is InputType_SparkAddress || parsed is InputType_SparkInvoice) {
      return AnalyzedPaymentType.spark;
    }
    return AnalyzedPaymentType.unknown;
  } catch (e) {
    return AnalyzedPaymentType.unknown;
  }
});

/// The fee the SDK charges for an on-chain exit at [speed]: the SSP's
/// own fee PLUS the L1 broadcast fee. The SDK's `withdraw` takes
/// `user_fee_sat + l1_broadcast_fee_sat` (`CoopExitFeeQuote::fee_sats`,
/// `SendOnchainSpeedFeeQuote::total_fee_sat`), so reading `userFeeSat`
/// alone under-states what leaves the wallet by the broadcast fee.
int sparkOnchainFeeSats(
    SendOnchainFeeQuote quote, OnchainConfirmationSpeed speed) {
  final q = switch (speed) {
    OnchainConfirmationSpeed.fast => quote.speedFast,
    OnchainConfirmationSpeed.medium => quote.speedMedium,
    OnchainConfirmationSpeed.slow => quote.speedSlow,
  };
  return (q.userFeeSat + q.l1BroadcastFeeSat).toInt();
}

/// The service (operator) part of [sparkOnchainFeeSats] at each speed, in
/// sats. The SDK quotes it per speed, like the broadcast fee.
Map<OnchainConfirmationSpeed, int> sparkOnchainServiceFeesBySpeed(
        SendOnchainFeeQuote quote) =>
    {
      OnchainConfirmationSpeed.fast: quote.speedFast.userFeeSat.toInt(),
      OnchainConfirmationSpeed.medium: quote.speedMedium.userFeeSat.toInt(),
      OnchainConfirmationSpeed.slow: quote.speedSlow.userFeeSat.toInt(),
    };

/// The fee a prepared Spark payment costs, in sats: the total at
/// [speed] for an on-chain exit, the transfer fee for a Spark address
/// or invoice, and the routing fee for a Lightning invoice.
int sparkPreparedFeeSats(
    PrepareSendPaymentResponse resp, OnchainConfirmationSpeed speed) {
  final method = resp.paymentMethod;
  if (method is SendPaymentMethod_BitcoinAddress) {
    return sparkOnchainFeeSats(method.feeQuote, speed);
  }
  if (method is SendPaymentMethod_SparkAddress) return method.fee.toInt();
  if (method is SendPaymentMethod_SparkInvoice) return method.fee.toInt();
  if (method is SendPaymentMethod_Bolt11Invoice) {
    return method.lightningFeeSats.toInt();
  }
  return 0;
}

/// What the recipient of a prepared Spark payment receives, in sats.
///
/// Under `feesIncluded` (a 100% send) the prepared amount is the whole
/// balance and the SDK takes the fee out of it at send time, exactly as
/// its own `send` does (`amount_sats = total - fee_for_speed`), so the
/// recipient gets the amount less the fee for the chosen [speed]. Under
/// `feesExcluded` the prepared amount is what arrives and the fee is
/// paid on top. Never negative.
///
/// Since breez 0.26 an on-chain send whose quote expired while Review
/// was open re-quotes at send time and never charges more than the fee
/// shown here: it keeps [speed] or steps down to a cheaper one, and
/// refuses ("fee rose") when even the slowest costs more. So a 100%
/// recipient gets at least this figure, never less.
int sparkPreparedRecipientSats(
    PrepareSendPaymentResponse resp, OnchainConfirmationSpeed speed) {
  final amount = resp.amount.toInt();
  if (resp.feePolicy != FeePolicy.feesIncluded) return amount;
  final net = amount - sparkPreparedFeeSats(resp, speed);
  return net > 0 ? net : 0;
}

/// The spending wallet's balance, synced with the operators first when
/// that is possible.
///
/// A 100% send spends every leaf, so the figure it asks for has to be
/// the one leaf selection will find. `getInfo` reads the balance the
/// last background sync cached: one that lags a payment that just left
/// asks for more than the leaves hold (refused as insufficient funds),
/// and one that lags a payment that just arrived leaves it behind. A
/// failed sync (offline, timeout) falls back to the cached figure; the
/// SDK still refuses a drain it cannot fund, it never overspends.
Future<int> sparkDrainBalanceSats(BreezSdk sdk) async {
  try {
    await sdk
        .syncWallet(request: const SyncWalletRequest())
        .timeout(const Duration(seconds: 20));
  } catch (_) {
    // Cached balance below.
  }
  final info = await sdk.getInfo(request: const GetInfoRequest());
  return info.balanceSats.toInt();
}

/// The amount a 100% Lightning send to an LNURL-pay / Lightning address
/// asks for: the whole balance, capped at what the recipient accepts.
/// The SDK's `feesIncluded` LNURL prepare refuses an amount above the
/// endpoint's `maxSendable` outright ("exceeds LNURL maximum"), so a
/// balance larger than that cap must be sent as the cap. The routing
/// fee still comes out of it, so the recipient gets cap less fee.
int lnurlDrainAmountSats(int balanceSats, BigInt maxSendableMsat) {
  final capSats = (maxSendableMsat ~/ BigInt.from(1000)).toInt();
  if (capSats <= 0) return balanceSats;
  return balanceSats < capSats ? balanceSats : capSats;
}

/// When [isDraining] is true, sends the whole balance with
/// [FeePolicy.feesIncluded], the SDK's own send-all: the fee comes out
/// of the balance rather than on top of it. This holds for an on-chain
/// exit too: with the whole balance, the SDK's fee quote reserves every
/// leaf, the same set the withdrawal then spends (`amount - fee` to the
/// address, `fee` to the operator), so the fee is priced on exactly the
/// coins that leave. [params.amountSats] is ignored while draining.
final prepareGenericPaymentProvider = FutureProvider.autoDispose.family<PrepareSendPaymentResponse,
    ({String destination, int amountSats, bool isDraining})>((ref, params) async {
  try {
    final binding = await _paymentSdkBinding(ref);
    final sdk = binding.sdk;

    final parsedInput = await sdk.parse(input: params.destination);

    if (parsedInput is! InputType_BitcoinAddress &&
        parsedInput is! InputType_SparkAddress &&
        parsedInput is! InputType_SparkInvoice) {
      throw Exception("Invalid address type. Expected Bitcoin or Spark address.");
    }

    BigInt amount = BigInt.from(params.amountSats);
    FeePolicy? feePolicy;

    // A fixed-amount Spark invoice dictates its own amount, so drain
    // semantics (full balance + feesIncluded) don't apply — the SDK
    // rejects that combination with "FeesIncluded is not supported
    // for invoices with a fixed amount". A stale Send-Max flag can
    // reach this path (MAX tapped before the invoice was scanned), so
    // resolve the conflict in the invoice's favor instead of erroring.
    final BigInt? sparkInvoiceFixedAmount =
        parsedInput is InputType_SparkInvoice ? parsedInput.field0.amount : null;

    if (sparkInvoiceFixedAmount != null &&
        sparkInvoiceFixedAmount > BigInt.zero) {
      amount = sparkInvoiceFixedAmount;
    } else if (params.isDraining) {
      // Bitcoin address, Spark address and amountless Spark invoice
      // alike: the whole balance, fees included. The previous on-chain
      // variant sent `balance - fee` with fees excluded; its quote was
      // priced on the leaves for that smaller amount while the
      // withdrawal then spent a different set (amount plus fee), and
      // the send came back as "not enough balance".
      final balance = await sparkDrainBalanceSats(sdk);
      if (balance <= 0) throw Exception('Insufficient funds');
      amount = BigInt.from(balance);
      feePolicy = FeePolicy.feesIncluded;
    }

    final req = PrepareSendPaymentRequest(
      paymentRequest: PaymentRequest.input(input: params.destination),
      amount: amount,
      feePolicy: feePolicy,
    );

    final prepared = await sdk.prepareSendPayment(request: req);
    binding.check(ref);
    _preparedPaymentBindings[prepared] = binding;
    return prepared;
  } catch (e) {
    handlePaymentException(e);
  }
});

/// Prepares a Spark payment of a TOKEN — today only the dollar token —
/// rather than of bitcoin. Deliberately a separate door from
/// [prepareGenericPaymentProvider]: the amount here is in the token's own
/// base units (the dollar token has six decimals), so it must never reach
/// a parameter, a variable or a log line spelled "sats", and nothing here
/// converts between the two units in either direction.
///
/// No drain support. `feesIncluded` is a bitcoin-balance idea, and a token
/// send whose fee came out of the token amount would deliver less than the
/// quote it is funding was struck on.
final prepareSparkTokenPaymentProvider = FutureProvider.autoDispose.family<
    PrepareSendPaymentResponse,
    ({
      String destination,
      BigInt amountBaseUnits,
      String tokenIdentifier,
    })>((ref, params) async {
  try {
    if (params.tokenIdentifier.trim().isEmpty) {
      throw Exception('Missing token identifier.');
    }
    if (params.amountBaseUnits <= BigInt.zero) {
      throw Exception('Enter an amount to send.');
    }
    final binding = await _paymentSdkBinding(ref);
    final sdk = binding.sdk;

    // Tokens live on Spark only. A Bitcoin address here would silently
    // mean a different rail, so it is refused rather than reinterpreted.
    final parsedInput = await sdk.parse(input: params.destination);
    if (parsedInput is! InputType_SparkAddress &&
        parsedInput is! InputType_SparkInvoice) {
      throw Exception('Invalid address type. Expected a Spark address.');
    }

    final prepared = await sdk.prepareSendPayment(
      request: PrepareSendPaymentRequest(
        paymentRequest: PaymentRequest.input(input: params.destination),
        amount: params.amountBaseUnits,
        tokenIdentifier: params.tokenIdentifier,
      ),
    );
    binding.check(ref);
    _preparedPaymentBindings[prepared] = binding;
    return prepared;
  } catch (e) {
    handlePaymentException(e);
  }
});

/// SDK does not support arbitrary fee rates for on-chain execution; accepts [speed] enum only.
final executeOnchainTransactionProvider = FutureProvider.autoDispose.family<SendPaymentResponse,
    ({PrepareSendPaymentResponse prepareResponse, OnchainConfirmationSpeed speed})>((ref, params) async {
  LedgerOperationScope.assertHotAllowed(HotSigningAction.onchainTransaction);
  try {
    final binding = _preparedPaymentBinding(ref, params.prepareResponse);
    final sdk = binding.sdk;

    final method = params.prepareResponse.paymentMethod;
    if (method is! SendPaymentMethod_BitcoinAddress) {
      throw Exception("Invalid payment method for on-chain execution.");
    }

    final req = SendPaymentRequest(
      prepareResponse: params.prepareResponse,
      options: SendPaymentOptions.bitcoinAddress(
        confirmationSpeed: params.speed,
      ),
    );

    final cache = ref.read(walletBalanceCacheProvider.notifier);
    final before = cache.shownSparkSats(binding.walletId);
    final response = await sdk.sendPayment(request: req);
    try {
      reflectAcceptedSparkSend(cache, sdk,
          walletId: binding.walletId,
          prepared: params.prepareResponse,
          paymentId: response.payment.id,
          balanceBeforeSats: before,
          speed: params.speed);
    } catch (_) {}
    return response;
  } catch (e) {
    handlePaymentException(e);
  }
});

final executeSparkTransactionProvider = FutureProvider.autoDispose.family<SendPaymentResponse,
    PrepareSendPaymentResponse>((ref, prepareResponse) async {
  LedgerOperationScope.assertHotAllowed(HotSigningAction.sparkTransaction);
  try {
    final binding = _preparedPaymentBinding(ref, prepareResponse);
    final sdk = binding.sdk;

    final method = prepareResponse.paymentMethod;
    if (method is! SendPaymentMethod_SparkAddress &&
        method is! SendPaymentMethod_SparkInvoice) {
      throw Exception("Invalid payment method for Spark execution.");
    }

    final req = SendPaymentRequest(
      prepareResponse: prepareResponse,
    );

    final cache = ref.read(walletBalanceCacheProvider.notifier);
    final before = cache.shownSparkSats(binding.walletId);
    final response = await sdk.sendPayment(request: req);
    try {
      reflectAcceptedSparkSend(cache, sdk,
          walletId: binding.walletId,
          prepared: prepareResponse,
          paymentId: response.payment.id,
          balanceBeforeSats: before);
    } catch (_) {}
    return response;
  } catch (e) {
    handlePaymentException(e);
  }
});

/// Uses an already-prepared response to avoid the double-prepare issue
/// where preparing twice could cause the payment to stay pending.
final executeLightningPaymentProvider = FutureProvider.autoDispose.family<void, dynamic>((ref, prepareResponse) async {
  LedgerOperationScope.assertHotAllowed(HotSigningAction.sparkTransaction);
  try {
    final binding = _preparedPaymentBinding(ref, prepareResponse);
    final sdk = binding.sdk;
    final cache = ref.read(walletBalanceCacheProvider.notifier);
    final before = cache.shownSparkSats(binding.walletId);

    String Function() paymentId;
    if (prepareResponse is PrepareSendPaymentResponse) {
      final response = await sdk.sendPayment(request: SendPaymentRequest(prepareResponse: prepareResponse));
      paymentId = () => response.payment.id;
    } else if (prepareResponse is PrepareLnurlPayResponse) {
      final response = await sdk.lnurlPay(request: LnurlPayRequest(prepareResponse: prepareResponse));
      paymentId = () => response.payment.id;
    } else {
      throw Exception("Invalid prepare response type for lightning payment");
    }
    // The payment went out; reading its id for the balance hold must
    // never turn that into a reported failure.
    try {
      reflectAcceptedSparkSend(cache, sdk,
          walletId: binding.walletId,
          prepared: prepareResponse,
          paymentId: paymentId(),
          balanceBeforeSats: before);
    } catch (_) {}
  } catch (e) {
    handlePaymentException(e);
  }
});

final prepareLightningPaymentProvider = FutureProvider.autoDispose.family<PrepareLightningPaymentResponse,
    ({String address, int amount, String? comment, bool isDraining})>((ref, params) async {
  try {
    final binding = await _paymentSdkBinding(ref);
    final sdk = binding.sdk;
    final parsedInput = await sdk.parse(input: params.address);

    dynamic prepareResponse;
    int networkFee = 0;

    // A fixed-amount Bolt11 invoice dictates its own amount, so drain
    // semantics (full balance + feesIncluded) don't apply — the SDK
    // rejects that combination with "FeesIncluded is not supported for
    // invoices with a fixed amount". A stale Send-Max flag can reach
    // this path (MAX tapped before the invoice was scanned), so pay
    // the invoice as-is instead of erroring.
    final bool bolt11FixedAmount = parsedInput is InputType_Bolt11Invoice &&
        parsedInput.field0.amountMsat != null;
    final bool effectiveDraining = params.isDraining && !bolt11FixedAmount;

    final feePolicy = effectiveDraining ? FeePolicy.feesIncluded : null;

    // When draining (Send Max), send the FULL wallet balance and let
    // `feesIncluded` deduct the routing fee exactly ONCE. The caller's
    // `params.amount` is the max-probe result that is ALREADY net of the
    // estimated fee, so passing it through with `feesIncluded` deducted
    // the fee a SECOND time and stranded it as dust (the ~128-sat
    // leftover bug). Mirrors `prepareGenericPaymentProvider`'s on-chain
    // drain at the top of this file.
    int sendAmount = params.amount;
    if (effectiveDraining) {
      sendAmount = await sparkDrainBalanceSats(sdk);
    }

    if (parsedInput is InputType_Bolt11Invoice) {
      final req = PrepareSendPaymentRequest(
        paymentRequest:
            PaymentRequest.input(input: parsedInput.field0.invoice.bolt11),
        // Fixed-amount invoice: omit the amount so the SDK takes it
        // from the invoice itself — immune to any stale UI amount.
        amount: bolt11FixedAmount
            ? null
            : (sendAmount > 0 ? BigInt.from(sendAmount) : null),
        feePolicy: feePolicy,
      );
      prepareResponse = await sdk.prepareSendPayment(request: req);
    } else if (parsedInput is InputType_Bolt12Offer) {
      final req = PrepareSendPaymentRequest(
        paymentRequest:
            PaymentRequest.input(input: parsedInput.field0.offer.offer),
        amount: sendAmount > 0 ? BigInt.from(sendAmount) : null,
        feePolicy: feePolicy,
      );
      prepareResponse = await sdk.prepareSendPayment(request: req);
    } else if (parsedInput is InputType_LightningAddress) {
      final payRequest = parsedInput.field0.payRequest;
      final req = PrepareLnurlPayRequest(
        payRequest: payRequest,
        amount: BigInt.from(effectiveDraining
            ? lnurlDrainAmountSats(sendAmount, payRequest.maxSendable)
            : sendAmount),
        comment: params.comment,
        validateSuccessActionUrl: true,
        feePolicy: feePolicy,
      );
      prepareResponse = await sdk.prepareLnurlPay(request: req);
      if (prepareResponse is PrepareLnurlPayResponse) {
        networkFee = prepareResponse.feeSats.toInt();
      }
    } else if (parsedInput is InputType_LnurlPay) {
      final req = PrepareLnurlPayRequest(
        payRequest: parsedInput.field0,
        amount: BigInt.from(effectiveDraining
            ? lnurlDrainAmountSats(sendAmount, parsedInput.field0.maxSendable)
            : sendAmount),
        comment: params.comment,
        validateSuccessActionUrl: true,
        feePolicy: feePolicy,
      );
      prepareResponse = await sdk.prepareLnurlPay(request: req);
      if (prepareResponse is PrepareLnurlPayResponse) {
        networkFee = prepareResponse.feeSats.toInt();
      }
    } else {
      throw Exception("Unsupported address type");
    }

    binding.check(ref);
    _preparedPaymentBindings[prepareResponse as Object] = binding;
    return PrepareLightningPaymentResponse(
        prepareResponse: prepareResponse, networkFee: networkFee);
  } catch (e) {
    handlePaymentException(e);
  }
});

final receivePaymentProvider = FutureProvider.family<ReceivePaymentResponse, ({BigInt amount, String description})>((ref, params) async {
  try {
    final sdkWrapper = await ref.watch(breezSDKProvider.future);
    final req = ReceivePaymentRequest(
      paymentMethod: ReceivePaymentMethod.bolt11Invoice(
        amountSats: params.amount,
        description: params.description,
      ),
    );
    return await sdkWrapper.instance!.receivePayment(request: req);
  } catch (e) {
    handlePaymentException(e);
  }
});

final getSparkBitcoinAddressProvider = FutureProvider<String>((ref) async {
  try {
    final sdkWrapper = await ref.watch(breezSDKProvider.future);
    // `newAddress: true` forces the SDK to generate a fresh deposit
    // address instead of returning the wallet's current "ready"
    // address. Without it, a re-imported wallet whose chain history
    // includes a prior deposit address would keep handing that
    // already-used address back from `receivePayment` — bad for
    // privacy and a "this is the same address you used before" UX
    // bug. The SDK exposes this via the `Option<bool> new_address`
    // field on the BitcoinAddress receive method (see Breez Spark
    // SDK `ReceivePaymentMethod_BitcoinAddress`).
    final req = const ReceivePaymentRequest(
      paymentMethod:
          ReceivePaymentMethod.bitcoinAddress(newAddress: true),
    );
    final response = await sdkWrapper.instance!.receivePayment(request: req);
    return response.paymentRequest;
  } catch (e) {
    handlePaymentException(e);
  }
});

final listSparkBitcoinPaymentsProvider = FutureProvider.family.autoDispose<List<Payment>, ListPaymentsRequest>((ref, req) async {
  final sdkWrapper = await ref.watch(breezSDKProvider.future);
  final response = await sdkWrapper.instance!.listPayments(request: req);
  return response.payments.toList();
});

final listSparkUnclaimedDepositsProvider = FutureProvider.autoDispose<List<DepositInfo>>((ref) async {
  final sdkWrapper = await ref.watch(breezSDKProvider.future);
  final response = await sdkWrapper.instance!.listUnclaimedDeposits(request: const ListUnclaimedDepositsRequest());
  return response.deposits;
});

final sparkDepositActionsProvider = Provider<SparkDepositActions>((ref) {
  return SparkDepositActions(
    currentWalletId: () => pickSpendingWallet(ref.read(settingsProvider))?.id,
    loadSdk: (walletId) async {
      final wrapper = await ref.read(breezSDKProvider.future);
      final sdk = wrapper.instance;
      if (sdk == null) {
        throw const SparkDepositActionException(
            SparkDepositActionReason.walletUnavailable);
      }
      if (pickSpendingWallet(ref.read(settingsProvider))?.id != walletId) {
        throw const SparkDepositActionException(
            SparkDepositActionReason.walletChanged);
      }
      return sdk;
    },
  );
});

final sparkBitcoinBalanceProvider = FutureProvider<BigInt>((ref) async {
  final sdkWrapper = await ref.watch(breezSDKProvider.future);
  final info = await sdkWrapper.instance!.getInfo(request: const GetInfoRequest());
  return info.balanceSats;
});

final breezPreferencesProvider = Provider((ref) => BreezPreferences());
final lnurlPayServiceProvider = Provider((ref) => LnUrlPayService());
final usernameResolverProvider = Provider((ref) => UsernameResolver(ref.watch(breezPreferencesProvider)));

final lnurlRegistrationManagerProvider = Provider((ref) {
  return LnUrlRegistrationManager(
    lnAddressService: ref.watch(lnurlPayServiceProvider),
    breezPreferences: ref.watch(breezPreferencesProvider),
    usernameResolver: ref.watch(usernameResolverProvider),
  );
});

final lnAddressProvider = StateNotifierProvider<LnAddressNotifier, AsyncValue<String?>>((ref) {
  final settings = ref.watch(settingsProvider);
  final walletId = settings.activeWalletId;
  return LnAddressNotifier(ref.watch(breezPreferencesProvider), walletId);
});

class LnAddressNotifier extends StateNotifier<AsyncValue<String?>> {
  final BreezPreferences _preferences;
  final String? _walletId;

  LnAddressNotifier(this._preferences, this._walletId) : super(const AsyncValue.loading()) {
    _loadInitialAddress();
  }

  Future<void> _loadInitialAddress() async {
    if (_walletId == null) {
      state = const AsyncValue.data(null);
      return;
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _preferences.getLnAddress(_walletId));
  }

  Future<void> updateLnAddress(String? address) async {
    if (_walletId == null) return;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _preferences.setLnAddress(_walletId, address);
      return address;
    });
  }
}

final createOrEditLnurlProvider = FutureProvider.family<Lnurl, String?>((ref, username) async {
  await ref.watch(breezSDKProvider.future);

  final settings = ref.read(settingsProvider);
  final walletId = settings.activeWalletId;

  if (walletId == null) {
    throw Exception("No active wallet selected");
  }

  final manager = ref.watch(lnurlRegistrationManagerProvider);

  final result = await manager.register(
    walletId: walletId,
    registrationType: RegistrationType.newRegistration,
    baseUsername: username,
  );

  if (result.lightningAddress != null) {
    await ref.read(lnAddressProvider.notifier).updateLnAddress(result.lightningAddress);
  }
  return result;
});

final setupLnAddressProvider = FutureProvider.autoDispose<Lnurl>((ref) async {
  final settings = ref.watch(settingsProvider);
  final walletId = settings.activeWalletId;

  if (walletId == null) {
    throw Exception("No active wallet");
  }

  final preferences = ref.read(breezPreferencesProvider);

  final isRegistered = await preferences.isLnUrlWebhookRegistered(walletId);

  if (isRegistered) {
    final username = await preferences.getLnAddressUsername(walletId);
    final address = await preferences.getLnAddress(walletId);
    final bech32 = await preferences.getLnUrlBech32(walletId);

    // If bech32 is missing (legacy registration), re-register to get it
    if (bech32 == null && username != null) {
      try {
        return await ref.watch(createOrEditLnurlProvider(username).future);
      } catch (_) {
        return Lnurl(
          username: username,
          lightningAddress: address,
        );
      }
    }

    return Lnurl(
      username: username,
      lightningAddress: address,
      lnurl: bech32,
    );
  } else {
    // Check if this is a restored wallet — try to recover existing address first
    final activeWallet = settings.activeWallet;
    if (activeWallet != null && activeWallet.isRestore) {
      try {
        final manager = ref.read(lnurlRegistrationManagerProvider);
        final result = await manager.registerOrRecover(walletId: walletId);
        if (result.lightningAddress != null) {
          await ref.read(lnAddressProvider.notifier).updateLnAddress(result.lightningAddress);
        }
        return result;
      } catch (e) {
        throw Exception("Initial setup failed: ${e.toString()}");
      }
    }

    try {
      return await ref.watch(createOrEditLnurlProvider(null).future);
    } catch (e) {
      throw Exception("Initial setup failed: ${e.toString()}");
    }
  }
});
