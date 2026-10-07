import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/providers/bitcoin_provider.dart';
import 'package:kute/providers/bitcoin_software_send_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/onchain/bitcoin_software_send.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

const _destination = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
const _destinationScript = '0014751e76e8199196d454941c45d1b3a323f1433bd6';

Psbt _psbt(
        {bool signed = false,
        int amount = 50000,
        int fee = 300,
        int outputs = 1,
        bool details = true,
        String? script}) =>
    Psbt.fromMap({
      'psbt': 'cHNidP8A',
      'feeSats': fee,
      'signed': signed,
      'tx': {
        'txid': 'ab' * 32,
        'vsize': 140,
        'inputCount': 1,
        'outputCount': outputs,
        if (details)
          'inputs': [
            {
              'previousOutput': {'txid': 'cd' * 32, 'vout': 0},
            }
          ],
        if (details)
          'outputs': List.generate(
              outputs,
              (_) => {
                    'value': amount,
                    'scriptPubkey': script ?? _destinationScript,
                  }),
      },
    });

// The preview builds through `buildPsbtWhenIdle`, which waits on the
// wallet's native slot. An idle service with no transport answers that
// wait at once; the build itself still goes to the fake model below.
class _Session implements NativeWalletSession {
  @override
  final NativeOnchainService service = NativeOnchainService(
      transport: (method, _) async => throw StateError('unexpected $method'));
  @override
  final String walletId = 'test-wallet';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BitcoinConfig implements Bitcoin {
  _BitcoinConfig(this.network);
  @override
  final Network network;
  @override
  final NativeWalletSession session = _Session();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _spendableCoin = LocalOutput.fromMap({
  'outpoint': {'txid': 'cd' * 32, 'vout': 0},
  'txout': {'value': 100000, 'scriptPubkey': _destinationScript},
  'keychain': 'external',
  'isSpent': false,
  'derivationIndex': 0,
  'chainPosition': {
    'height': 900000,
    'confirmationTime': 1750000000,
    'blockHash': 'ef' * 32,
    'lastSeen': null,
  },
});

class _Wallet implements BitcoinModel {
  _Wallet({Network network = Network.bitcoin})
      : config = _BitcoinConfig(network);
  @override
  final Bitcoin config;
  final calls = <String>[];
  bool signs = true;
  int drainAmount = 49700;
  void Function(String)? after;
  Future<void> Function()? beforeSignCompletes;
  Psbt? signedOverride;
  Psbt? toSign;
  Psbt? broadcast;
  TransactionBuilder? built;
  @override
  List<LocalOutput> listUnspent() => [_spendableCoin];

  @override
  Future<Psbt> buildBitcoinTransaction(TransactionBuilder transaction) async {
    calls.add('build');
    built = transaction;
    after?.call('build');
    return _psbt(amount: transaction.amount);
  }

  @override
  Future<Psbt> drainWalletBitcoinTransaction(
      TransactionBuilder transaction) async {
    calls.add('drain');
    built = transaction;
    after?.call('drain');
    return _psbt(amount: drainAmount);
  }

  @override
  Future<Psbt> signBitcoinTransaction(Psbt psbt) async {
    calls.add('sign');
    toSign = psbt;
    after?.call('sign');
    await beforeSignCompletes?.call();
    return signedOverride ?? Psbt.fromMap({...psbt.toMap(), 'signed': signs});
  }

  @override
  Future<String> broadcastBitcoinTransaction(Psbt psbt) async {
    calls.add('broadcast');
    broadcast = psbt;
    return 'ab' * 32;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('ordinary send builds, signs and broadcasts on the captured model',
      () async {
    final wallet = _Wallet();
    final tx = TransactionBuilder(50000, _destination, 2);
    final result = await BitcoinSoftwareSend.send(
        model: wallet, transaction: tx, drain: false, isCurrent: () => true);
    expect(wallet.calls, ['build', 'sign', 'broadcast']);
    expect(wallet.built, same(tx));
    expect(result.recipientSats, 50000);
    expect(result.feeSats, 300);
  });

  test('testnet sends validate the destination on the captured wallet network',
      () async {
    final wallet = _Wallet(network: Network.testnet);
    final preview =
        _psbt(script: '76a914243f1394f44554f4ce3fd68649c19adc483ce92488ac');
    final result = await BitcoinSoftwareSend.send(
      model: wallet,
      transaction:
          TransactionBuilder(50000, 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn', 2),
      drain: false,
      reviewedPsbt: preview,
      isCurrent: () => true,
    );
    expect(result.recipientSats, 50000);
    expect(wallet.calls, ['sign', 'broadcast']);
  });

  test('signs exact approved preview without building a new transaction',
      () async {
    final wallet = _Wallet();
    final preview = _psbt();
    await BitcoinSoftwareSend.send(
        model: wallet,
        transaction: TransactionBuilder(50000, _destination, 2),
        drain: false,
        reviewedPsbt: preview,
        isCurrent: () => true);
    expect(wallet.calls, ['sign', 'broadcast']);
    expect(wallet.toSign, same(preview));
  });

  test('MAX uses actual output and never deducts its fee a second time',
      () async {
    final wallet = _Wallet();
    final result = await BitcoinSoftwareSend.send(
        model: wallet,
        transaction: TransactionBuilder(49700, _destination, 2),
        drain: true,
        isCurrent: () => true);
    expect(wallet.calls, ['drain', 'sign', 'broadcast']);
    expect(result.recipientSats, 49700);
    expect(result.feeSats, 300);
  });

  for (final preview in [
    _psbt(script: '0014${'cd' * 20}'),
    _psbt(amount: 49999),
    _psbt(outputs: 2),
    _psbt(details: false),
  ]) {
    test(
        'a stale or mismatched preview cannot authorize a payment ${preview.toMap()}',
        () async {
      final wallet = _Wallet();
      await expectLater(
        BitcoinSoftwareSend.send(
          model: wallet,
          transaction: TransactionBuilder(50000, _destination, 2),
          drain: false,
          reviewedPsbt: preview,
          isCurrent: () => true,
        ),
        throwsA(isA<OnchainException>()),
      );
      expect(wallet.calls, isEmpty);
    });
  }

  test('changed MAX output requires a fresh review before signing', () async {
    final wallet = _Wallet()..drainAmount = 60000;
    await expectLater(
        BitcoinSoftwareSend.send(
            model: wallet,
            transaction: TransactionBuilder(49700, _destination, 2),
            drain: true,
            isCurrent: () => true),
        throwsA(isA<OnchainException>()));
    expect(wallet.calls, ['drain']);
  });

  for (final preview in [
    _psbt(outputs: 2),
    _psbt(details: false),
    _psbt(amount: 0)
  ]) {
    test('unverifiable MAX output is rejected ${preview.toMap()}', () {
      expect(() => BitcoinSoftwareSend.drainRecipientSats(preview),
          throwsA(isA<OnchainException>()));
    });
  }

  test('changed review before preparation cannot build or sign', () async {
    final wallet = _Wallet();
    await expectLater(
        BitcoinSoftwareSend.send(
            model: wallet,
            transaction: TransactionBuilder(50000, _destination, 2),
            drain: false,
            isCurrent: () => false),
        throwsA(isA<OnchainException>()));
    expect(wallet.calls, isEmpty);
  });

  for (final step in ['build', 'sign']) {
    test('changing wallet, fee or coins after $step aborts before broadcasting',
        () async {
      var current = true;
      final wallet = _Wallet()
        ..after = (event) {
          if (event == step) current = false;
        };
      await expectLater(
          BitcoinSoftwareSend.send(
              model: wallet,
              transaction: TransactionBuilder(50000, _destination, 2),
              drain: false,
              isCurrent: () => current),
          throwsA(isA<OnchainException>()));
      expect(wallet.calls, isNot(contains('broadcast')));
      if (step == 'build') expect(wallet.calls, isNot(contains('sign')));
    });
  }

  test('incomplete signature cannot be broadcast', () async {
    final wallet = _Wallet()..signs = false;
    await expectLater(
        BitcoinSoftwareSend.send(
            model: wallet,
            transaction: TransactionBuilder(50000, _destination, 2),
            drain: false,
            isCurrent: () => true),
        throwsA(isA<OnchainException>()));
    expect(wallet.calls, ['build', 'sign']);
  });

  for (final changed in ['recipient', 'amount', 'wallet']) {
    test(
        'a $changed provider change during asynchronous signing prevents broadcast',
        () async {
      final selectedWallet = StateProvider<String>((ref) => 'wallet-1');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateAddress(_destination);
      notifier.updateAmount(50000);
      final signStarted = Completer<void>();
      final finishSigning = Completer<void>();
      final wallet = _Wallet()
        ..beforeSignCompletes = () async {
          signStarted.complete();
          await finishSigning.future;
        };
      final pending = BitcoinSoftwareSend.send(
        model: wallet,
        transaction: TransactionBuilder(50000, _destination, 2),
        drain: false,
        reviewedPsbt: _psbt(),
        isCurrent: () =>
            container.read(selectedWallet) == 'wallet-1' &&
            container.read(sendTxProvider).address == _destination &&
            container.read(sendTxProvider).amount == 50000,
      );
      final rejected = expectLater(pending, throwsA(isA<OnchainException>()));
      await signStarted.future;
      switch (changed) {
        case 'recipient':
          notifier.updateAddress('1BoatSLRHtKNngkdXEeobR76b53LETtpyT');
        case 'amount':
          notifier.updateAmount(60000);
        case 'wallet':
          container.read(selectedWallet.notifier).state = 'wallet-2';
      }
      finishSigning.complete();
      await rejected;
      expect(wallet.calls, ['sign']);
      expect(wallet.broadcast, isNull);
    });
  }

  for (final altered in [
    _psbt(signed: true, amount: 49999),
    _psbt(signed: true, script: '0014${'cd' * 20}'),
    _psbt(signed: true, fee: 301),
  ]) {
    test('signing cannot change the approved payment ${altered.toMap()}',
        () async {
      final wallet = _Wallet()..signedOverride = altered;
      await expectLater(
          BitcoinSoftwareSend.send(
              model: wallet,
              transaction: TransactionBuilder(50000, _destination, 2),
              drain: false,
              isCurrent: () => true),
          throwsA(isA<OnchainException>()));
      expect(wallet.calls, ['build', 'sign']);
    });
  }

  test(
      'preview uses requested wallet and invalidates with fees and coin selection',
      () async {
    final first = _Wallet();
    final second = _Wallet();
    final container = ProviderContainer(overrides: [
      bitcoinModelForWalletProvider('first').overrideWith((ref) async => first),
      bitcoinModelForWalletProvider('second')
          .overrideWith((ref) async => second),
      getCustomFeeRateProvider
          .overrideWith((ref) async => ref.watch(customFeeRateProvider) ?? 2),
    ]);
    addTearDown(container.dispose);
    const request = (
      walletId: 'second',
      address: _destination,
      amount: 50000,
      drain: false
    );
    final provider = bitcoinSoftwareSendPreviewProvider(request);
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    expect(first.calls, isEmpty);
    expect(second.built!.fee, 2);
    final coin = OutPoint(txid: Txid.fromString(hex: '12' * 32), vout: 1);
    container.read(selectedUtxosProvider.notifier).state = [coin];
    container.read(customFeeRateProvider.notifier).state = 4;
    await container.read(provider.future);
    expect(second.built!.fee, 4);
    expect(second.built!.selectedUtxos, [coin]);
    expect(first.calls, isEmpty);
  });

  test('late completion for a different wallet stays isolated from its preview',
      () async {
    final ready = Completer<BitcoinModel>();
    final first = _Wallet();
    final second = _Wallet();
    final container = ProviderContainer(overrides: [
      bitcoinModelForWalletProvider('first')
          .overrideWith((ref) => ready.future),
      bitcoinModelForWalletProvider('second')
          .overrideWith((ref) async => second),
      getCustomFeeRateProvider.overrideWith((ref) async => 2),
    ]);
    addTearDown(container.dispose);
    final oldProvider = bitcoinSoftwareSendPreviewProvider((
      walletId: 'first',
      address: 'first-destination',
      amount: 10000,
      drain: false
    ));
    final newProvider = bitcoinSoftwareSendPreviewProvider((
      walletId: 'second',
      address: 'second-destination',
      amount: 20000,
      drain: false
    ));
    final old = container.listen(oldProvider, (_, __) {});
    final current = container.listen(newProvider, (_, __) {});
    addTearDown(old.close);
    addTearDown(current.close);
    final preview = await container.read(newProvider.future);
    ready.complete(first);
    await container.read(oldProvider.future);
    expect(container.read(newProvider).requireValue, same(preview));
    expect(second.built!.amount, 20000);
    expect(second.built!.outAddress, 'second-destination');
  });
}
