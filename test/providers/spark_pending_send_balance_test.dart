// A send from the spending wallet that the Breez SDK accepted as pending
// must show in the balance at once, not when the SDK's cached
// `getInfo()` figure catches up (up to a minute or more later).
//
// Case from the phone: balance 11,459 sats (from "Withdraw from
// Investing"), Send Max to a Bitcoin address. The SDK sends the whole
// 11,459 with the fee taken out of it: 9,509 to the address, 1,950 to
// the exit. Home kept reading 11,459 while the send was pending.
import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: false,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

const _wallet = 'spending';
const _balance = 11459;
const _toAddress = 9509;
const _exitFee = 1950;

SendOnchainSpeedFeeQuote _speed(int userFee, int l1Fee) =>
    SendOnchainSpeedFeeQuote(
        userFeeSat: BigInt.from(userFee), l1BroadcastFeeSat: BigInt.from(l1Fee));

final _feeQuote = SendOnchainFeeQuote(
  id: 'quote',
  expiresAt: BigInt.from(4102444800),
  speedFast: _speed(1500, 450), // 1,950 in all
  speedMedium: _speed(1200, 300),
  speedSlow: _speed(1000, 200),
  isEstimate: false,
);

const _recipient = BitcoinAddressDetails(
  address: 'bc1qrecipient',
  network: BitcoinNetwork.bitcoin,
  source: PaymentRequestSource(),
);

/// The prepared 100% on-chain send: the whole balance, fees included.
PrepareSendPaymentResponse _maxOnchain() => PrepareSendPaymentResponse(
      paymentMethod: SendPaymentMethod.bitcoinAddress(
          address: _recipient, feeQuote: _feeQuote),
      amount: BigInt.from(_balance),
      feePolicy: FeePolicy.feesIncluded,
    );

Payment _payment(String id, PaymentStatus status, int amount, int fees) =>
    Payment(
      id: id,
      paymentType: PaymentType.send,
      status: status,
      amount: BigInt.from(amount),
      fees: BigInt.from(fees),
      timestamp: BigInt.one,
      method: PaymentMethod.withdraw,
    );

GetInfoResponse _info(int sats) => GetInfoResponse(
    identityPubkey: 'id', balanceSats: BigInt.from(sats), tokenBalances: {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('balance cache while a send is pending', () {
    late DateTime now;
    late WalletBalanceCacheNotifier cache;
    int shown() => cache.shownSparkSats(_wallet);

    setUp(() {
      now = DateTime(2026, 10, 5, 16, 18);
      cache = WalletBalanceCacheNotifier(clock: () => now);
      // The Withdraw from Investing landed at 16:18; the send is at 16:54.
      cache.updateSparkBitcoinbalance(_wallet, _balance,
          source: BalanceSource.stream);
      now = DateTime(2026, 10, 5, 16, 54);
    });

    void holdMax() => cache.holdOutgoingSparkSend(
          _wallet,
          key: 'max-send',
          balanceBeforeSats: _balance,
          debitSats: _balance, // fees included: the whole balance leaves
          feeSats: _exitFee,
        );

    test('a pending Max send shows 0 at once', () {
      holdMax();
      expect(shown(), 0);
      expect(cache.hasSparkSendHold(_wallet), isTrue);
    });

    test('stale SDK re-reads of the pre-send figure keep it at 0', () {
      holdMax();
      // What getInfo() returns until its cache is refreshed: the old
      // figure, by poll and by the payment-pending stream read alike.
      cache.updateSparkBitcoinbalance(_wallet, _balance);
      expect(shown(), 0);
      cache.updateSparkBitcoinbalance(_wallet, _balance,
          source: BalanceSource.stream);
      expect(shown(), 0);
      now = now.add(const Duration(minutes: 4)); // 16:58 on the phone
      cache.updateSparkBitcoinbalance(_wallet, _balance);
      expect(shown(), 0);
    });

    test('once the SDK figure shows the send, it is trusted and stays', () {
      holdMax();
      cache.updateSparkBitcoinbalance(_wallet, 0);
      expect(shown(), 0);
      expect(cache.hasSparkSendHold(_wallet), isFalse);
      // Settles: payment completed, figures agree.
      cache.reconcileSparkSendHolds(_wallet,
          failed: {}, completed: {'max-send'});
      now = now.add(const Duration(hours: 1));
      cache.updateSparkBitcoinbalance(_wallet, 0);
      expect(shown(), 0);
    });

    test('a failed send restores the balance', () {
      holdMax();
      expect(shown(), 0);
      cache.reconcileSparkSendHolds(_wallet,
          failed: {'max-send'}, completed: {});
      expect(shown(), _balance);
      expect(cache.hasSparkSendHold(_wallet), isFalse);
    });

    test('a failed send after the SDK already deducted it comes back with '
        'the refund', () {
      holdMax();
      cache.updateSparkBitcoinbalance(_wallet, 0,
          source: BalanceSource.stream);
      cache.reconcileSparkSendHolds(_wallet,
          failed: {'max-send'}, completed: {});
      expect(shown(), 0);
      // The SDK re-syncs on PaymentFailed and reports the refund.
      cache.updateSparkBitcoinbalance(_wallet, _balance,
          source: BalanceSource.stream);
      expect(shown(), _balance);
    });

    test('Max after a pending send uses the reduced figure', () {
      // A partial send first: 5,000 to the address plus the 1,950 fee.
      cache.holdOutgoingSparkSend(_wallet,
          key: 'first',
          balanceBeforeSats: shown(),
          debitSats: 5000 + _exitFee,
          feeSats: _exitFee);
      expect(shown(), _balance - 5000 - _exitFee); // 4,509
      // What Send reads for Max / "Available" / the balance check.
      final available = shown();
      expect(available, 4509);
      // A second send starts from that reduced figure, never from the
      // 11,459 the SDK still reports.
      cache.holdOutgoingSparkSend(_wallet,
          key: 'second',
          balanceBeforeSats: available,
          debitSats: available,
          feeSats: _exitFee);
      expect(shown(), 0);
      cache.updateSparkBitcoinbalance(_wallet, _balance);
      expect(shown(), 0);
    });

    test('the SDK figure catching up for the first of two sends keeps the '
        'second held', () {
      cache.holdOutgoingSparkSend(_wallet,
          key: 'first',
          balanceBeforeSats: _balance,
          debitSats: 3000,
          feeSats: 100);
      cache.holdOutgoingSparkSend(_wallet,
          key: 'second',
          balanceBeforeSats: shown(),
          debitSats: 4000,
          feeSats: 100);
      expect(shown(), _balance - 7000);
      cache.updateSparkBitcoinbalance(_wallet, _balance - 3000);
      expect(shown(), _balance - 7000);
      cache.updateSparkBitcoinbalance(_wallet, _balance - 7000);
      expect(shown(), _balance - 7000);
      expect(cache.hasSparkSendHold(_wallet), isFalse);
    });

    test('a cheaper actual fee still counts as the SDK catching up', () {
      cache.holdOutgoingSparkSend(_wallet,
          key: 'partial',
          balanceBeforeSats: _balance,
          debitSats: 5000 + _exitFee,
          feeSats: _exitFee);
      // The re-quoted exit stepped down to a 1,200 fee.
      cache.updateSparkBitcoinbalance(_wallet, _balance - 5000 - 1200);
      expect(shown(), _balance - 6200);
      expect(cache.hasSparkSendHold(_wallet), isFalse);
    });

    test('nothing is held when the SDK figure already shows the send', () {
      cache.updateSparkBitcoinbalance(_wallet, 0,
          source: BalanceSource.stream);
      holdMax();
      expect(cache.hasSparkSendHold(_wallet), isFalse);
      expect(shown(), 0);
    });

    test('a post-sync SDK read settles the hold; a still-stale one does not',
        () {
      holdMax();
      cache.settleOutgoingSparkSend(_wallet, 'max-send', _balance);
      expect(shown(), 0);
      expect(cache.hasSparkSendHold(_wallet), isTrue);
      cache.settleOutgoingSparkSend(_wallet, 'max-send', 0);
      expect(shown(), 0);
      expect(cache.hasSparkSendHold(_wallet), isFalse);
    });

    test('an incoming payment the sync also picked up is not hidden', () {
      cache.holdOutgoingSparkSend(_wallet,
          key: 'partial',
          balanceBeforeSats: _balance,
          debitSats: 5000 + _exitFee,
          feeSats: _exitFee);
      // The post-send sync read: the send out, 20,000 received.
      cache.settleOutgoingSparkSend(
          _wallet, 'partial', _balance - 5000 - _exitFee + 20000);
      expect(shown(), _balance - 5000 - _exitFee + 20000);
    });

    test('a completed send stops holding after its grace', () {
      holdMax();
      cache.reconcileSparkSendHolds(_wallet,
          failed: {}, completed: {'max-send'});
      expect(shown(), 0);
      now = now.add(const Duration(seconds: 91));
      cache.updateSparkBitcoinbalance(_wallet, _balance);
      expect(shown(), _balance);
    });

    test('a hold never outlives its maximum age', () {
      holdMax();
      now = now.add(const Duration(minutes: 16));
      cache.updateSparkBitcoinbalance(_wallet, _balance);
      expect(shown(), _balance);
    });

    ({String id, int sats, DateTime at}) receive(String id, int sats,
            {DateTime? at}) =>
        (id: id, sats: sats, at: at ?? now);

    test('a receive while a send is pending shows at once', () {
      cache.noteSparkReceives(_wallet, [
        receive('withdraw-from-investing', _balance,
            at: DateTime(2026, 10, 5, 16, 18)),
      ]);
      cache.holdOutgoingSparkSend(_wallet,
          key: 'partial',
          balanceBeforeSats: _balance,
          debitSats: 5000 + _exitFee,
          feeSats: _exitFee);
      now = now.add(const Duration(seconds: 30));
      // The SDK refreshes on the incoming payment: its figure counts the
      // send and the 20,000 received.
      cache.updateSparkBitcoinbalance(
          _wallet, _balance - 5000 - _exitFee + 20000,
          source: BalanceSource.stream);
      cache.noteSparkReceives(_wallet, [
        receive('withdraw-from-investing', _balance,
            at: DateTime(2026, 10, 5, 16, 18)),
        receive('incoming', 20000),
      ]);
      expect(shown(), _balance - 5000 - _exitFee + 20000);
      expect(cache.hasSparkSendHold(_wallet), isFalse);
    });

    test('a receive the SDK adds to its stale figure keeps the send taken off',
        () {
      holdMax();
      now = now.add(const Duration(seconds: 30));
      // The SDK figure still counts the Max send and now the receive too.
      cache.updateSparkBitcoinbalance(_wallet, _balance + 20000,
          source: BalanceSource.stream);
      cache.noteSparkReceives(_wallet, [receive('incoming', 20000)]);
      expect(shown(), 20000);
      // Its next sync agrees.
      now = now.add(const Duration(minutes: 1));
      cache.updateSparkBitcoinbalance(_wallet, 20000);
      expect(shown(), 20000);
      expect(cache.hasSparkSendHold(_wallet), isFalse);
    });

    test('a receive that settled before the send is not counted again', () {
      holdMax();
      // Listed only now, but settled (and in the balance shown before
      // the send) a minute earlier.
      cache.noteSparkReceives(_wallet, [
        receive('earlier', 2000,
            at: now.subtract(const Duration(minutes: 1))),
      ]);
      expect(shown(), 0);
      // And a receive already seen never raises a later hold.
      cache.noteSparkReceives(_wallet, [
        receive('earlier', 2000,
            at: now.subtract(const Duration(minutes: 1))),
      ]);
      expect(shown(), 0);
    });

    test('a completed send ends its hold at once', () {
      cache.holdOutgoingSparkSend(_wallet,
          key: 'partial',
          balanceBeforeSats: _balance,
          debitSats: 5000 + _exitFee,
          feeSats: _exitFee);
      // The SDK figure moved (it counts a receive the list has not
      // shown yet), so it has refreshed since the send.
      cache.updateSparkBitcoinbalance(
          _wallet, _balance - 5000 - _exitFee + 3000,
          source: BalanceSource.stream);
      expect(shown(), _balance - 5000 - _exitFee);
      cache.reconcileSparkSendHolds(_wallet,
          failed: {}, completed: {'partial'});
      expect(shown(), _balance - 5000 - _exitFee + 3000);
      expect(cache.hasSparkSendHold(_wallet), isFalse);
    });

    test('a hold expires on time without another balance write', () {
      fakeAsync((async) {
        holdMax();
        expect(shown(), 0);
        now = now.add(const Duration(minutes: 15));
        async.elapse(const Duration(minutes: 15));
        expect(shown(), _balance);
        expect(cache.hasSparkSendHold(_wallet), isFalse);
      });
    });

    test('a completed send read before the SDK refreshed gives way on time',
        () {
      fakeAsync((async) {
        holdMax();
        cache.reconcileSparkSendHolds(_wallet,
            failed: {}, completed: {'max-send'});
        // The SDK still reports exactly the pre-send figure.
        expect(shown(), 0);
        now = now.add(const Duration(seconds: 30));
        async.elapse(const Duration(seconds: 30));
        expect(shown(), _balance);
      });
    });

    test('a failed send restores the balance at once, receives included', () {
      holdMax();
      cache.noteSparkReceives(_wallet, [receive('incoming', 2000)]);
      cache.updateSparkBitcoinbalance(_wallet, _balance + 2000,
          source: BalanceSource.stream);
      expect(shown(), 2000);
      cache.reconcileSparkSendHolds(_wallet,
          failed: {'max-send'}, completed: {});
      expect(shown(), _balance + 2000);
    });

    test('the post-receive zero guard never hides a Max send', () {
      final fresh = WalletBalanceCacheNotifier(clock: () => now);
      // A receive just landed (e.g. Withdraw from Investing)...
      fresh.updateSparkBitcoinbalance(_wallet, _balance,
          source: BalanceSource.stream);
      fresh.holdOutgoingSparkSend(_wallet,
          key: 'max-send',
          balanceBeforeSats: _balance,
          debitSats: _balance,
          feeSats: _exitFee);
      // ...and the SDK's poll 0 for the drain is applied (past the 5 s
      // window in which a poll may not undercut a stream value).
      now = now.add(const Duration(seconds: 6));
      fresh.updateSparkBitcoinbalance(_wallet, 0);
      expect(fresh.shownSparkSats(_wallet), 0);
      expect(fresh.hasSparkSendHold(_wallet), isFalse);
    });
  });

  group('sparkSendDebit', () {
    test('a fees-included Max send takes the whole amount', () {
      final debit = sparkSendDebit(_maxOnchain())!;
      expect(debit.debitSats, _balance);
      expect(debit.feeSats, _exitFee);
    });

    test('a fees-excluded send takes the amount plus the fee at its speed',
        () {
      final debit = sparkSendDebit(
          PrepareSendPaymentResponse(
            paymentMethod: SendPaymentMethod.bitcoinAddress(
                address: _recipient, feeQuote: _feeQuote),
            amount: BigInt.from(5000),
            feePolicy: FeePolicy.feesExcluded,
          ),
          speed: OnchainConfirmationSpeed.slow)!;
      expect(debit.debitSats, 5000 + 1200);
    });

    test('a dollar-token send holds nothing on the bitcoin balance', () {
      expect(
          sparkSendDebit(PrepareSendPaymentResponse(
            paymentMethod: SendPaymentMethod.sparkAddress(
                address: 'spark1x', fee: BigInt.zero, tokenIdentifier: 'usd'),
            amount: BigInt.from(1000000),
            tokenIdentifier: 'usd',
            feePolicy: FeePolicy.feesExcluded,
          )),
          isNull);
    });
  });

  group('executeOnchainTransactionProvider', () {
    late _Sdk sdk;
    late _Wrapper wrapper;
    late ProviderContainer container;
    late Completer<SyncWalletResponse> sync;
    late int sdkBalance;

    setUpAll(() {
      registerFallbackValue(PrepareSendPaymentRequest(
          paymentRequest: const PaymentRequest.input(input: 'x')));
      registerFallbackValue(SendPaymentRequest(prepareResponse: _maxOnchain()));
      registerFallbackValue(const SyncWalletRequest());
      registerFallbackValue(const GetInfoRequest());
    });

    setUp(() {
      sdk = _Sdk();
      wrapper = _Wrapper();
      sync = Completer<SyncWalletResponse>();
      sdkBalance = _balance;
      when(() => wrapper.instance).thenReturn(sdk);
      when(() => sdk.parse(input: any(named: 'input')))
          .thenAnswer((_) async => const InputType.bitcoinAddress(_recipient));
      when(() => sdk.prepareSendPayment(request: any(named: 'request')))
          .thenAnswer((_) async => _maxOnchain());
      when(() => sdk.syncWallet(request: any(named: 'request')))
          .thenAnswer((_) => sync.future);
      when(() => sdk.getInfo(request: any(named: 'request')))
          .thenAnswer((_) async => _info(sdkBalance));
      container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => _Settings()),
        breezSDKProvider.overrideWith((_) async => wrapper),
      ]);
      container
          .read(walletBalanceCacheProvider.notifier)
          .updateSparkBitcoinbalance(_wallet, _balance,
              source: BalanceSource.stream);
    });
    tearDown(() => container.dispose());

    Future<void> sendMaxPending({bool fails = false}) async {
      final prepared = await container.read(prepareGenericPaymentProvider((
        destination: 'bc1qrecipient',
        amountSats: 0,
        isDraining: true,
      )).future);
      // The drain prepare ran its own sync; the post-send one is next.
      sync = Completer<SyncWalletResponse>();
      when(() => sdk.sendPayment(request: any(named: 'request')))
          .thenAnswer((_) async => fails
              ? throw Exception('insufficient funds')
              : SendPaymentResponse(
                  payment: _payment(
                      'exit', PaymentStatus.pending, _toAddress, _exitFee)));
      await container.read(executeOnchainTransactionProvider((
        prepareResponse: prepared,
        speed: OnchainConfirmationSpeed.fast,
      )).future);
    }

    int shown() => container.read(balanceNotifierProvider).sparkBitcoinbalance;

    test('the balance drops to 0 as soon as the send is accepted', () async {
      // Unblock the drain prepare's own sync.
      sync.complete(const SyncWalletResponse());
      await sendMaxPending();
      // The SDK has not caught up yet: its sync is still running.
      expect(sync.isCompleted, isFalse);
      expect(shown(), 0);
      // Stale stream / poll reads of 11,459 change nothing.
      container
          .read(walletBalanceCacheProvider.notifier)
          .updateSparkBitcoinbalance(_wallet, _balance);
      expect(shown(), 0);
      // The forced sync finishes; getInfo() now shows the send.
      sdkBalance = 0;
      sync.complete(const SyncWalletResponse());
      await pumpEventQueue();
      expect(shown(), 0);
      expect(
          container
              .read(walletBalanceCacheProvider.notifier)
              .hasSparkSendHold(_wallet),
          isFalse);
    });

    test('a refused send leaves the balance alone', () async {
      sync.complete(const SyncWalletResponse());
      await expectLater(sendMaxPending(fails: true), throwsException);
      expect(shown(), _balance);
    });
  });
}
