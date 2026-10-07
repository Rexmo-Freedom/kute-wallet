// A first prediction runs the account's one-time setup before its price is
// read. That wait used to be unbounded and its failure unnamed; now it is
// bounded and both outcomes say "setup", so the slip can say which and
// offer a retry. Fakes only: nothing is signed or sent.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket/placement_waits.dart';

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.setup);
  final Future<void> Function() setup;
  var setupCalls = 0;

  @override
  Future<PolymarketTradingState> build() async =>
      PolymarketTradingState(usdcBalance: 100);

  @override
  String? get signingWalletId => 'spending';

  @override
  Future<void> enableTrading({
    void Function(String status)? onProgress,
    bool force = false,
  }) {
    setupCalls++;
    return setup();
  }
}

const _intent = PendingBetIntent(
  tokenId: '1',
  amount: 10,
  slippagePct: 2,
  marketQuestion: 'Will it rain?',
  outcomeName: 'Yes',
  expectedPrice: 0.5,
);

Future<T> _offline<T>(Future<T> Function() body) => http.runWithClient(
    body, () => MockClient((_) async => http.Response('offline', 503)));

void main() {
  late Duration saved;
  setUp(() => saved = PolymarketPlacementWaits.setup);
  tearDown(() => PolymarketPlacementWaits.setup = saved);

  ProviderContainer containerWith(_Trading trading) {
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('setup that does not finish in time ends the wait with a setup timeout',
      () async {
    PolymarketPlacementWaits.setup = const Duration(milliseconds: 200);
    final never = Completer<void>();
    final trading = _Trading(() => never.future);
    final container = containerWith(trading);
    await container.read(polymarketTradingProvider.future);
    await _offline(() => expectLater(
          container.read(polymarketBetControllerProvider).prepareIntent(_intent),
          throwsA(isA<PolymarketSetupIncomplete>()
              .having((e) => e.timedOut, 'timedOut', isTrue)),
        ));
    expect(trading.setupCalls, 1);
  });

  test('setup that fails is named as setup, with its cause', () async {
    final trading =
        _Trading(() async => throw StateError('approvals batch refused'));
    final container = containerWith(trading);
    await container.read(polymarketTradingProvider.future);
    await _offline(() => expectLater(
          container.read(polymarketBetControllerProvider).prepareIntent(_intent),
          throwsA(isA<PolymarketSetupIncomplete>()
              .having((e) => e.timedOut, 'timedOut', isFalse)
              .having((e) => e.cause, 'cause', isA<StateError>())),
        ));
  });
}
