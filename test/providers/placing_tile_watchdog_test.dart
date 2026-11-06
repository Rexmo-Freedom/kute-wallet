// The Portfolio's "placing" tiles never say an order failed because a
// timer ran out. Founder, on device: "sometimes it says the investment
// failed but it didn't really fail". The watchdog used to mark a
// prediction's tile "Placement failed" after 25 s (60 s from the slip)
// while the placement was still running: a deposit converting, a live
// game's delay, an answer that came late. The order then filled.
//
// Now the watchdog turns the tile into "Confirming with Polymarket…" (or
// "…with the exchange…" for Investing), it stays until the position lands
// or the placement settles it, and only an explicit markFailed (a venue
// verdict) shows a failure. The watchdog counts foreground time only: a
// Face ID sheet (the app inactive) does not run it down. Fakes only.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/placing_hyperliquid_order_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/foreground_timer.dart';

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'spending',
      wallets: [WalletConfig(id: 'spending', name: 'Spending Wallet')],
    );

ProviderContainer _container() {
  final c = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => SettingsModel(_settings())),
    polymarketActivePositionsProvider
        .overrideWithValue(const <PolymarketPosition>[]),
  ]);
  addTearDown(c.dispose);
  return c;
}

String _placeBet(ProviderContainer c,
        {Duration watchdog = const Duration(seconds: 25)}) =>
    c.read(placingPolymarketBetProvider.notifier).markPlacing(
          tokenId: 't1',
          marketQuestion: 'Lakers vs Celtics',
          outcomeName: 'Lakers',
          amount: 5,
          shares: 10,
          avgPrice: 0.5,
          watchdogDuration: watchdog,
          stepLabel: 'Placing prediction…',
        );

String _placeHl(ProviderContainer c) =>
    c.read(placingHyperliquidOrderProvider.notifier).markPlacing(
          coin: 'BTC',
          marketLabel: 'BTC · Perp',
          isLong: true,
          marginUsd: 10,
          leverage: 1,
          sizeRequested: 0.0001,
        );

void main() {
  var foreground = true;
  setUp(() {
    foreground = true;
    ForegroundTimer.debugForeground = () => foreground;
  });
  tearDown(() => ForegroundTimer.debugForeground = null);

  group('Predictions tile', () {
    test('the watchdog says confirming, never failed', () {
      fakeAsync((async) {
        final c = _container();
        final id = _placeBet(c);
        async.elapse(const Duration(seconds: 26));
        final tile = c.read(placingPolymarketBetProvider).single;
        expect(tile.placementId, id);
        // Before: PlacingBetStatus.failed ("Placement failed" on the row).
        expect(tile.status, PlacingBetStatus.placing);
        expect(tile.stepLabel, 'Confirming with Polymarket…');
        expect(tile.errorMessage, isNull);
      });
    });

    test('a placement that succeeds after the watchdog shows the bridge', () {
      fakeAsync((async) {
        final c = _container();
        final id = _placeBet(c, watchdog: const Duration(seconds: 60));
        async.elapse(const Duration(seconds: 90));
        final tiles = c.read(placingPolymarketBetProvider.notifier);
        tiles.markSucceeded(id, holdUntilPositionArrives: true);
        final tile = c.read(placingPolymarketBetProvider).single;
        expect(tile.status, PlacingBetStatus.succeeded);
        expect(tile.stepLabel, 'Confirmed. Appearing in your predictions…');
      });
    });

    test('confirming is bounded and ends quietly, never as a failure', () {
      fakeAsync((async) {
        final c = _container();
        _placeBet(c);
        final seen = <PlacingBetStatus>{};
        c.listen<List<PlacingBet>>(placingPolymarketBetProvider, (_, next) {
          for (final b in next) {
            seen.add(b.status);
          }
        });
        async.elapse(const Duration(seconds: 25) +
            kPlacingConfirmingBound +
            const Duration(seconds: 2));
        expect(c.read(placingPolymarketBetProvider), isEmpty);
        expect(seen, isNot(contains(PlacingBetStatus.failed)));
      });
    });

    test('a venue verdict still shows the failure', () {
      fakeAsync((async) {
        final c = _container();
        final id = _placeBet(c);
        c
            .read(placingPolymarketBetProvider.notifier)
            .markFailed(id, 'No sellers were left at your price');
        expect(c.read(placingPolymarketBetProvider).single.status,
            PlacingBetStatus.failed);
      });
    });

    test('time with the app inactive (Face ID up) is not counted', () {
      fakeAsync((async) {
        final c = _container();
        _placeBet(c);
        // The approval sheet is up for a minute: the app is inactive.
        foreground = false;
        async.elapse(const Duration(seconds: 60));
        expect(c.read(placingPolymarketBetProvider).single.stepLabel,
            'Placing prediction…');
        // Back on screen: the 25 s count resumes from where it was.
        foreground = true;
        async.elapse(const Duration(seconds: 20));
        expect(c.read(placingPolymarketBetProvider).single.stepLabel,
            'Placing prediction…');
        async.elapse(const Duration(seconds: 6));
        expect(c.read(placingPolymarketBetProvider).single.stepLabel,
            'Confirming with Polymarket…');
      });
    });
  });

  group('Investing tile', () {
    test('the watchdog says confirming, never failed', () {
      fakeAsync((async) {
        final c = _container();
        _placeHl(c);
        // A builder-dex order waits up to 30 s for its cash before it is
        // sent: past the old 25 s watchdog that marked it failed.
        async.elapse(const Duration(seconds: 31));
        final tile = c.read(placingHyperliquidOrderProvider).single;
        expect(tile.status, PlacingHlOrderStatus.placing);
        expect(tile.stepLabel, 'Confirming with the exchange…');
        expect(tile.errorMessage, isNull);
      });
    });

    test('a fill after the watchdog still settles the tile', () {
      fakeAsync((async) {
        final c = _container();
        final id = _placeHl(c);
        c.read(placingHyperliquidOrderProvider.notifier).attachCloid(id, '0xc1');
        async.elapse(const Duration(seconds: 40));
        c
            .read(placingHyperliquidOrderProvider.notifier)
            .markSucceededByFill(coin: 'BTC', cloid: '0xc1');
        expect(c.read(placingHyperliquidOrderProvider).single.status,
            PlacingHlOrderStatus.succeeded);
      });
    });

    test('confirming is bounded and ends quietly', () {
      fakeAsync((async) {
        final c = _container();
        _placeHl(c);
        async.elapse(const Duration(seconds: 25) +
            kHlPlacingConfirmingBound +
            const Duration(seconds: 2));
        expect(c.read(placingHyperliquidOrderProvider), isEmpty);
      });
    });
  });
}
