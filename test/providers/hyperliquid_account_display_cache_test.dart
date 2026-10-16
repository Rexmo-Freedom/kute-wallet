import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_account_cache.dart';

const _address = '0x1111111111111111111111111111111111111111';
const _key = 'wallet-a:bip39-sha512';
const _snapshot = HlAccountSnapshot(
  accountValue: 42,
  withdrawable: 9,
  totalMarginUsed: 30,
  crossMaintenanceMarginUsed: 2,
  activeDexes: {'xyz'},
  positions: [
    HlPerpPosition(
      coin: 'xyz:TSLA',
      szi: -2,
      entryPx: 15,
      positionValue: 32,
      unrealizedPnl: -2,
      returnOnEquity: -.1,
      liquidationPx: 20,
      marginUsed: 30,
      leverageType: 'isolated',
      leverageValue: 2,
      maxLeverage: 10,
      fundingSinceOpen: .2,
    ),
  ],
  spotBalances: [HlSpotBalance(coin: 'PURR', total: 4, hold: 1, entryNtl: 3)],
);

class _Account extends HlAccountNotifier {
  final pending = Completer<HlAccountSnapshot>();
  @override
  Future<HlAccountSnapshot> build() => pending.future;
  void publish(HlAccountSnapshot value) => state = AsyncData(value);
  void fail() => state = AsyncError(StateError('offline'), StackTrace.current);
}

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() =>
      Completer<HyperliquidTradingState>().future;
}

void main() {
  setUp(() {
    HyperliquidAccountCache.debugReset();
    HyperliquidAccountCache.memoryOnly = true;
  });
  tearDown(HyperliquidAccountCache.debugReset);

  test('wallet deletion removes its formats and rejects late writes', () async {
    const cached = HlCachedAccount(address: _address, snapshot: _snapshot);
    await HyperliquidAccountCache.write(_key, cached);
    await HyperliquidAccountCache.write('wallet-a:legacy-sha256', cached);
    await HyperliquidAccountCache.write('wallet-b:bip39-sha512', cached);
    await HyperliquidAccountCache.deleteWallet('wallet-a');
    await HyperliquidAccountCache.write(_key, cached);
    expect(await HyperliquidAccountCache.open(_key), isNull);
    expect(await HyperliquidAccountCache.open('wallet-a:legacy-sha256'), isNull);
    expect(await HyperliquidAccountCache.open('wallet-b:bip39-sha512'), isNotNull);
  });

  test('disk roundtrip retains positions, spot cost basis and HIP-3 dexes',
      () async {
    final directory = await Directory.systemTemp.createTemp('hl-display-cache');
    Hive.init(directory.path);
    HyperliquidAccountCache.memoryOnly = false;
    try {
      await HyperliquidAccountCache.write(
          _key, const HlCachedAccount(address: _address, snapshot: _snapshot));
      await Hive.close();
      HyperliquidAccountCache.debugReset();
      final restored = await HyperliquidAccountCache.open(_key);
      expect(restored?.address, _address);
      expect(hlAccountSnapshotEquals(restored!.snapshot, _snapshot), isTrue);
      final position = restored.snapshot.positions.single;
      expect(position.maxLeverage, 10);
      expect(position.fundingSinceOpen, .2);
      expect(restored.snapshot.spotBalances.single.entryNtl, 3);
      expect(
          await HyperliquidAccountCache.open('wallet-b:bip39-sha512'), isNull);
      expect(
          await HyperliquidAccountCache.open('wallet-a:legacy-sha256'), isNull);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  test('cached display never initializes live account or execution state',
      () async {
    await HyperliquidAccountCache.write(
        _key, const HlCachedAccount(address: _address, snapshot: _snapshot));
    final account = _Account();
    final container = ProviderContainer(overrides: [
      hyperliquidDisplayCacheKeyProvider.overrideWithValue(_key),
      hyperliquidAddressProvider.overrideWith((_) async => _address),
      hyperliquidAccountProvider.overrideWith(() => account),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(hyperliquidDisplayTradingProvider, (_, __) {});
    addTearDown(sub.close);
    await container
        .read(hyperliquidDisplayAccountSnapshotProvider(_key).future);
    await pumpEventQueue();
    final display =
        container.read(hyperliquidDisplayTradingProvider).requireValue;
    expect(display.positions.single.coin, 'xyz:TSLA');
    expect(display.withdrawable, 9);
    expect(container.read(hyperliquidAccountProvider).isLoading, isTrue);
    expect(container.read(hyperliquidTradingProvider).isLoading, isTrue);

    account.fail();
    await pumpEventQueue();
    expect(
        container
            .read(hyperliquidDisplayTradingProvider)
            .requireValue
            .withdrawable,
        9);
    expect(container.read(hyperliquidAccountProvider).hasError, isTrue);

    account.publish(HlAccountSnapshot.empty);
    await pumpEventQueue();
    final empty =
        container.read(hyperliquidDisplayTradingProvider).requireValue;
    expect(empty.positions, isEmpty);
    expect(empty.withdrawable, 0);
    expect((await HyperliquidAccountCache.open(_key))?.snapshot.positions,
        isEmpty);
  });

  test('wallet changes and mismatched account addresses cannot reuse positions',
      () async {
    await HyperliquidAccountCache.write(
        _key, const HlCachedAccount(address: _address, snapshot: _snapshot));
    final key = StateProvider<String?>((_) => _key);
    final account = _Account();
    final container = ProviderContainer(overrides: [
      hyperliquidDisplayCacheKeyProvider.overrideWith((ref) => ref.watch(key)),
      hyperliquidAddressProvider.overrideWith((_) async => _address),
      hyperliquidAccountProvider.overrideWith(() => account),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(hyperliquidDisplayAccountProvider, (_, __) {});
    addTearDown(sub.close);
    expect(
        (await container
                .read(hyperliquidDisplayAccountSnapshotProvider(_key).future))
            .positions,
        isNotEmpty);
    container.read(key.notifier).state = 'wallet-b:bip39-sha512';
    await pumpEventQueue();
    // Riverpod may retain previous data while rebuilding; the current result
    // must remain loading until this wallet has its own authoritative answer.
    expect(container.read(hyperliquidDisplayAccountProvider).isLoading, isTrue);
    expect(
        container.read(hyperliquidDisplayAccountProvider).valueOrNull, isNull);
    account.publish(HlAccountSnapshot.empty);
    await pumpEventQueue();
    expect(
        container
            .read(hyperliquidDisplayAccountProvider)
            .requireValue
            .positions,
        isEmpty);
  });

  test('a resolved different account rejects cached figures', () async {
    await HyperliquidAccountCache.write(
        _key, const HlCachedAccount(address: _address, snapshot: _snapshot));
    final container = ProviderContainer(overrides: [
      hyperliquidDisplayCacheKeyProvider.overrideWithValue(_key),
      hyperliquidAddressProvider.overrideWith(
          (_) async => '0x2222222222222222222222222222222222222222'),
      hyperliquidAccountProvider.overrideWith(_Account.new),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(hyperliquidDisplayAccountProvider, (_, __) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    expect(container.read(hyperliquidDisplayAccountProvider).isLoading, isTrue);
    expect(
        container.read(hyperliquidDisplayAccountProvider).valueOrNull, isNull);
  });

  test('cache serialization rejects incomplete or non-finite figures', () {
    final json =
        const HlCachedAccount(address: _address, snapshot: _snapshot).toJson();
    expect(HlCachedAccount.fromJson({...json, 'withdrawable': double.nan}),
        isNull);
    expect(HlCachedAccount.fromJson({...json, 'positions': 'invalid'}), isNull);
    expect(HlCachedAccount.fromJson({...json, 'v': 2}), isNull);
  });
}
