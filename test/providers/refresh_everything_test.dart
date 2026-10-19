// Pull-to-refresh is "update everything" (refresh_everything_provider):
// one function for Home and every Investments pill. These cover:
//   * the reproduction on the Investing side: an account address that
//     could not be derived once (the phrase unreadable for a moment, as on
//     a restore) was cached as "none" for the whole process, so Investing
//     stayed empty through every pull and only a restart showed it;
//   * every part starts at once, and the spinner goes after the cap while
//     the work carries on;
//   * a pull while one runs joins it; a part that fails or hangs never
//     holds the others or a later pull;
//   * Home's pull is the same function (the mascot refreshing meanwhile);
//   * `pull_to_refresh_executed` carries the surface and the refresh mode,
//     never an id;
//   * a pull while a run is hung past the step limit starts a fresh one.
// The Bitcoin step as a hot restart (the SDK connected again) is in
// refresh_everything_reconnect_test.dart.
// Nothing is signed or sent.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/kute_state.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/kute_state_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/tracking_service.dart';

const _phrase =
    'panel custom call awesome sick ready hamster wool patch client reduce clay';

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'spend',
      wallets: [
        WalletConfig(
          id: 'spend',
          name: 'Spending Wallet',
          sparkEnabled: true,
          isRestore: true,
          evmDerivationVersion: EvmDerivationVersion.standardBip39,
        ),
      ],
    );

/// The badge poll, counted instead of read.
class _CountingBadge extends HlOpenPositionsCountNotifier {
  static var refreshes = 0;
  @override
  int build() => 0;
  @override
  Future<void> refreshNow() async => refreshes++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    RefreshEverything.spinnerCap = const Duration(milliseconds: 200);
    RefreshEverything.stepLimit = const Duration(seconds: 30);
    _CountingBadge.refreshes = 0;
  });
  tearDown(() {
    TrackingService.debugTrackObserver = null;
    RefreshEverything.spinnerCap = const Duration(seconds: 4);
    RefreshEverything.stepLimit = const Duration(seconds: 30);
  });

  ProviderContainer spending({Map<String, RefreshStep>? steps}) {
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
      sessionAuthProvider.overrideWith((ref) =>
          SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026))),
      sessionUnlockedProvider.overrideWith((ref) => true),
      hyperliquidOpenPositionsCountProvider.overrideWith(_CountingBadge.new),
      if (steps != null)
        refreshEverythingProvider
            .overrideWith((ref) => RefreshEverything(ref, steps: steps)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('Investing (reproduction)', () {
    test(
        'an address that could not be derived once stays "none" through the '
        'old pull, a restart shows it, and the shared pull derives it again',
        () async {
      // The phrase cannot be read at first (the keystore did not answer).
      FlutterSecureStorage.setMockInitialValues({});
      final c = spending();
      expect(await c.read(hyperliquidAddressProvider.future), isNull);

      // It can now.
      FlutterSecureStorage.setMockInitialValues(
          {'v2:wallet:spend.mnemonic': _phrase});
      // The Investing pill's old pull invalidated the markets and the
      // account snapshot, never the address: still none.
      c.invalidate(hyperliquidAccountProvider);
      expect(await c.read(hyperliquidAddressProvider.future), isNull);

      // A restart (a new process) derives it at once.
      final restart = spending();
      final cold = await restart.read(hyperliquidAddressProvider.future);
      expect(cold, isNotNull);

      // The shared pull's Investing part does what the restart did.
      await c.read(refreshEverythingProvider).steps['investing']!();
      expect(await c.read(hyperliquidAddressProvider.future), cold);
      expect(_CountingBadge.refreshes, 1,
          reason: 'the badge poll (free USDC, held positions) read now');
    });

    test('a known address is kept: the signer and trading state stay',
        () async {
      FlutterSecureStorage.setMockInitialValues(
          {'v2:wallet:spend.mnemonic': _phrase});
      final c = spending();
      final address = await c.read(hyperliquidAddressProvider.future);
      expect(address, isNotNull);
      var rebuilds = 0;
      c.listen(hyperliquidAddressProvider, (_, next) {
        if (next.isLoading) rebuilds++;
      });
      await c.read(refreshEverythingProvider).steps['investing']!();
      expect(rebuilds, 0);
      expect(c.read(hyperliquidAddressProvider).valueOrNull, address);
    });
  });

  test('every part of the refresh is one of the shared steps', () {
    final c = spending();
    expect(c.read(refreshEverythingProvider).steps.keys,
        containsAll(['bitcoin', 'sync', 'predictions', 'investing',
            'portfolio']));
  });

  test(
      'every part starts at once; the spinner goes at the cap while the '
      'work carries on', () async {
    final started = <String>[];
    final release = Completer<void>();
    var finished = 0;
    RefreshStep step(String name) => () async {
          started.add(name);
          await release.future;
          finished++;
        };
    final c = spending(steps: {
      for (final name in ['a', 'b', 'c']) name: step(name),
    });
    final refresh = c.read(refreshEverythingProvider);
    final clock = Stopwatch()..start();
    await refresh(const RefreshTrigger('usd', tab: 'predictions'));
    // The spinner resolved at the cap, with every part already running.
    expect(clock.elapsed, greaterThanOrEqualTo(RefreshEverything.spinnerCap));
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    expect(started, unorderedEquals(['a', 'b', 'c']));
    expect(finished, 0, reason: 'the work goes on behind the spinner');
    release.complete();
    await refresh.run();
    expect(finished, 3);
  });

  test('a pull that finishes inside the cap resolves at once', () async {
    final c = spending(steps: {'quick': () async {}});
    final clock = Stopwatch()..start();
    await c.read(refreshEverythingProvider)(RefreshTrigger.home);
    expect(clock.elapsed, lessThan(RefreshEverything.spinnerCap));
  });

  test('a pull while one runs joins it rather than reading twice', () async {
    var runs = 0;
    final release = Completer<void>();
    final c = spending(steps: {
      'slow': () async {
        runs++;
        await release.future;
      },
    });
    final refresh = c.read(refreshEverythingProvider);
    final first = refresh.run();
    final second = refresh.run();
    expect(identical(first, second), isTrue);
    release.complete();
    await first;
    expect(runs, 1);
    // Done: the next pull reads again.
    await refresh.run();
    expect(runs, 2);
  });

  test(
      'a part that fails or hangs holds neither the others nor a later '
      'pull', () async {
    RefreshEverything.stepLimit = const Duration(milliseconds: 100);
    var good = 0;
    var hung = 0;
    final c = spending(steps: {
      'fails': () async => throw StateError('offline'),
      'hangs': () {
        hung++;
        return Completer<void>().future;
      },
      'good': () async => good++,
    });
    final refresh = c.read(refreshEverythingProvider);
    await refresh.run();
    expect(good, 1);
    await refresh.run();
    expect(good, 2);
    expect(hung, 2, reason: 'the hung part never blocked the next pull');
  });

  test(
      'a second pull while a run is hung joins it inside the step limit '
      'and starts a fresh run after it', () async {
    RefreshEverything.stepLimit = const Duration(milliseconds: 100);
    var runs = 0;
    final c = spending(steps: {
      'hangs': () {
        runs++;
        return Completer<void>().future;
      },
    });
    final refresh = c.read(refreshEverythingProvider);
    final first = refresh.run();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(identical(refresh.run(), first), isTrue,
        reason: 'a young run is joined');
    expect(runs, 1);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final second = refresh.run();
    expect(identical(second, first), isFalse);
    expect(runs, 2, reason: 'never joined forever: a fresh run reads again');
  });

  test(
      "Home's pull is the same function: reported as home, the mascot "
      'refreshing until the spinner goes', () async {
    final release = Completer<void>();
    var runs = 0;
    final c = spending(steps: {
      'all': () async {
        runs++;
        await release.future;
      },
    });
    final pull = c.read(refreshEverythingProvider).home();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(kuteStateProvider), KuteState.refreshing);
    await pull;
    expect(c.read(kuteStateProvider), isNot(KuteState.refreshing));
    expect(runs, 1);
    release.complete();
    final pulls = [
      for (final e in events)
        if (e.$1 == 'pull_to_refresh_executed') e.$2
    ];
    expect(pulls, [
      {'screen': 'home', 'refresh_mode': 'sync'}
    ]);
  });

  test('pull_to_refresh_executed carries the surface and the pill only',
      () async {
    final c = spending(steps: {'quick': () async {}});
    await c.read(refreshEverythingProvider)(
        const RefreshTrigger('usd', tab: 'investing'));
    final pull =
        events.singleWhere((e) => e.$1 == 'pull_to_refresh_executed').$2;
    expect(pull, {'screen': 'usd', 'tab': 'investing', 'refresh_mode': 'sync'},
        reason: 'no SDK connection read yet: nothing to reconnect');
  });
}
