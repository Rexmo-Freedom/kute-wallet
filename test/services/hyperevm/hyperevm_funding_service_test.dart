import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_vault.dart';
import 'package:kute/services/hyperevm/hyperevm_withdrawal.dart';
import 'package:kute/services/release/route_pause_policy.dart';

import 'hyperevm_fakes.dart';

const _spark = 'sprt1pgssx9exampleexampleexampleexampleexampleexampleexampleexample';

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
          reviewDone: true,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

void main() {
  late ProviderContainer container;
  late FakeReader reader;
  late MemoryHyperEvmTxJournal journal;
  var runnerAsked = 0;
  var floatBought = <String>[];
  SparkFloatBalances balances = (usdMicros: usdcMicros(30), sats: 100000);

  setUp(() {
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => _Settings()),
      hyperliquidAddressProvider.overrideWith((_) async => kEoa),
      sparkSelfAddressProvider.overrideWith((_) async => _spark),
    ]);
    addTearDown(container.dispose);
    reader = FakeReader()..perpUsdc = coreUsdc(25);
    journal = MemoryHyperEvmTxJournal();
    runnerAsked = 0;
    floatBought = [];
    balances = (usdMicros: usdcMicros(30), sats: 100000);
  });

  SparkHypercoreFundingService service({bool paused = false}) =>
      SparkHypercoreFundingService(
        container.read,
        pausePolicy: RoutePausePolicy(readFlag: (_) async => paused),
        reader: reader,
        journal: journal,
        // A runner is only ever asked once something may be quoted; these
        // tests stop before that, so asking for one is a failure.
        runner: () async {
          runnerAsked++;
          throw StateError('runner asked');
        },
        openSigner: (_, __) async => FakeSigner(reader),
        buyFloat: (source,
            {required eoa, required sparkAddress, required trigger}) async {
          floatBought.add('${source.analytics}:$trigger');
        },
        sparkBalances: () async => balances,
        usdPerBtc: () => 100000,
        sweepSoon: (_) {},
        sleep: noSleep,
      );

  test('availability: the flag and the pause switch stop before anything',
      () async {
    final off = SparkHypercoreFundingService(container.read, enabled: false);
    expect(await off.tryDirect(deposit: true), isFalse);
    expect(await off.tryDirect(deposit: false), isFalse);
    await expectLater(
        service(paused: true).ensureAvailable(deposit: false),
        throwsA(isA<HypercoreFundingUnavailable>().having((e) => e.reason,
            'reason', HypercoreFundingUnavailableReason.paused)));
    expect(await service().tryDirect(deposit: true), isTrue);
  });

  test('withdraw: no float and nothing to buy it with stops before any money',
      () async {
    reader
      ..evmHypeWei = BigInt.zero
      ..spotHype = BigInt.zero;
    balances = (usdMicros: usdcMicros(0.5), sats: 1000);
    await expectLater(
        service().withdrawToSpark(usd: 10, stepUp: (_) async => true),
        throwsA(isA<HypercoreFundingUnavailable>()
            .having((e) => e.reason, 'reason',
                HypercoreFundingUnavailableReason.floatUnavailable)
            .having((e) => e.needsFloatFunds, 'needs funds', isTrue)));
    expect(runnerAsked, 0);
    expect(floatBought, isEmpty);
  });

  test('deposit: the float comes out of what is left after the deposit',
      () async {
    reader
      ..evmHypeWei = BigInt.zero
      ..spotHype = BigInt.zero;
    balances = (usdMicros: usdcMicros(11), sats: 0);
    // $10.50 leaves only $0.50: no float, nothing moves.
    await expectLater(
        service().depositFromSpark(
            asset: SparkFundingAsset.dollars,
            amountBaseUnits: usdcMicros(10.5)),
        throwsA(isA<HypercoreFundingUnavailable>().having((e) => e.reason,
            'reason', HypercoreFundingUnavailableReason.floatUnavailable)));
    expect(runnerAsked, 0);
    // Bitcoin would pay when Dollars cannot.
    balances = (usdMicros: usdcMicros(11), sats: 50000);
    await expectLater(
        service().depositFromSpark(
            asset: SparkFundingAsset.dollars,
            amountBaseUnits: usdcMicros(10.5)),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'runner asked')));
  });

  test('a gas spike stops before any money, both ways', () async {
    reader.gasPrice = gwei(6);
    for (final call in [
      () => service().withdrawToSpark(usd: 10, stepUp: (_) async => true),
      () => service().depositFromSpark(
          asset: SparkFundingAsset.bitcoin, amountBaseUnits: BigInt.from(50000)),
    ]) {
      await expectLater(
          call(),
          throwsA(isA<HypercoreFundingUnavailable>().having((e) => e.reason,
              'reason', HypercoreFundingUnavailableReason.gasSpike)));
    }
    expect(runnerAsked, 0);
  });

  test('an unreadable account never moves money', () async {
    reader.failure = StateError('rpc down');
    await expectLater(
        service().withdrawToSpark(usd: 10, stepUp: (_) async => true),
        throwsA(isA<HypercoreFundingUnavailable>().having((e) => e.reason,
            'reason', HypercoreFundingUnavailableReason.accountUnavailable)));
    expect(runnerAsked, 0);
  });

  test('a healthy float reaches the runner', () async {
    await expectLater(
        service().withdrawToSpark(usd: 10, stepUp: (_) async => true),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'runner asked')));
    expect(floatBought, isEmpty);
  });

  test('what the HyperEVM steps throw reads as "not available, nothing sent"',
      () {
    final stop = SparkHypercoreFundingService.withdrawalStop;
    expect(stop(const HyperEvmCoreTransferRefused('x'))!.reason,
        HypercoreFundingUnavailableReason.coreTransferRefused);
    expect(stop(const HyperEvmArrivalTimeout())!.reason,
        HypercoreFundingUnavailableReason.arrivalTimeout);
    expect(stop(const HyperEvmGasSpike())!.reason,
        HypercoreFundingUnavailableReason.gasSpike);
    expect(stop(const HyperEvmGasShort())!.reason,
        HypercoreFundingUnavailableReason.floatPending);
    expect(stop(const HyperEvmFloatUnavailable('gas_spike'))!.reason,
        HypercoreFundingUnavailableReason.gasSpike);
    expect(stop(const HyperEvmFloatUnavailable('pending'))!.reason,
        HypercoreFundingUnavailableReason.floatPending);
    expect(stop(StateError('other')), isNull);
    expect(stop(const SettlementStopped(SettlementStopReason.declined)),
        isNull);
  });

  test('withdrawal amounts: six decimals, never above the balance read', () {
    expect(hyperEvmUsdcMicros(19.99), BigInt.from(19990000));
    expect(hyperEvmUsdcMicros(0.29), BigInt.from(290000));
    expect(hyperEvmUsdcMicros(12.1234567), BigInt.from(12123456));
    expect(hyperEvmUsdcMicros(0), BigInt.zero);
    expect(hyperEvmUsdcMicros(double.nan), BigInt.zero);
  });

  test('the live routes are HyperEVM USDC legs the catalogue must list', () {
    expect(SparkFundingAsset.dollars.hypercoreRoute.toChain, 'hyperevm');
    expect(SparkFundingAsset.bitcoin.sparkWithdrawRoute.fromChain, 'hyperevm');
    expect(SparkFundingAsset.dollars.sparkWithdrawRouteVersion,
        startsWith('hypercore_to_spark'));
    expect(SparkFundingAsset.bitcoin.hypercoreRouteVersion,
        startsWith('spark_to_hypercore'));
  });
}
