// What the "Send now" sheet tests and renders run on: a fake wallet behind a
// real GiftFundingRunner, the leg landing when the test says so.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/gift_funding.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/runtime_capabilities_service.dart'
    show CapabilityDecision;

final giftSheetSettings = Settings(
  currency: 'USD',
  language: 'en',
  btcFormat: 'sats',
  backup: false,
  biometricsEnabled: false,
  bitcoinElectrumNode: '',
  nodeType: 'Blockstream',
  reviewDone: true,
);

ClaimedShareLink giftSheetClaim({int amountMinor = 2000}) => ClaimedShareLink(
      id: 'lnk_gift',
      kind: ShareLinkKind.dollars,
      amountMinor: amountMinor,
      claimDestination: 'sp1qfriend',
    );

/// A row a previous process left: the leg on its way, the send waiting.
GiftFundingRecord giftSheetRunningRecord({String ref = 'q_prev'}) {
  final at = DateTime.now();
  return GiftFundingRecord(
    startedAt: at,
    landsUsd: const {'leg:bitcoin': 15},
    steps: MoneyStepGraph([
      MoneyStep(
        id: 'leg:bitcoin',
        kind: MoneyStepKind.leg,
        from: MoneyPlace.bitcoin,
        to: MoneyPlace.dollars,
        usd: 15,
        route: MoneyRoute.viaDollars,
        status: MoneyStepStatus.running,
        startedAt: at,
        ref: ref,
      ),
      const MoneyStep(
        id: kGiftFundingSendId,
        kind: MoneyStepKind.leg,
        from: MoneyPlace.dollars,
        usd: 20,
        route: MoneyRoute.direct,
        after: ['leg:bitcoin'],
      ),
    ]),
  );
}

class GiftSheetWallet {
  double dollars = 5;
  double bitcoinLandUsd = 40;
  CapabilityDecision? denied;
  bool failLeg = false;
  bool failPayment = false;
  int legs = 0;
  final payments = <BigInt>[];

  /// Held open, the leg stays on its way; completed, it lands.
  Completer<void>? landing;
  bool _landed = false;

  GiftFundingRunner runner() => GiftFundingRunner(GiftFundingEnv(
        walletId: () => 'w1',
        dollarsNow: () => dollars,
        freshDollars: () async => dollars,
        bitcoinDenied: () async => denied,
        venueSources: () async => const [],
        decide: ({
          required double fundUsd,
          required double dollarsUsd,
          required double otherVenueUsd,
          required bool investmentsCover,
        }) async {
          final short = fundUsd - dollarsUsd;
          if (short <= 0) return const OrderSources(OrderSourceRoute.dollars);
          if (short > bitcoinLandUsd) {
            return const OrderSources(OrderSourceRoute.insufficient);
          }
          return OrderSources(OrderSourceRoute.bitcoin,
              bitcoinUsd: short,
              plan: BitcoinLegPlan(
                dollarsShortUsd: short,
                targetUsd: short,
                sats: 25000,
                maxSats: 26250,
                usdPerBtc: 60000,
              ));
        },
        ownSpark: () async => 'sp1qown',
        sendBitcoin: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required stepUp,
          required void Function() onSending,
        }) async {
          legs++;
          if (failLeg) throw StateError('no route');
          onSending();
          _target = plan.targetUsd;
          return BitcoinLegTicket(
            quoteId: 'q_btc',
            sats: plan.sats,
            estimatedOutUsd: plan.targetUsd,
            minOutUsd: plan.targetUsd,
          );
        },
        pullVenue: (plan, {required onStarted, required onLeg}) =>
            throw UnimplementedError(),
        legState: (ref) async {
          _maybeLand();
          return _landed ? GiftLegState.delivered : GiftLegState.onItsWay;
        },
        payDollars: (destination, amount) async {
          if (failPayment) throw StateError('refused');
          payments.add(amount);
          dollars -= amount.toDouble() / 1e6;
          return 'pay_${payments.length}';
        },
        sessionUnlocked: () => true,
        sleep: (_) => Future<void>.delayed(const Duration(milliseconds: 1)),
        pollEvery: const Duration(milliseconds: 1),
        landingWait: const Duration(hours: 1),
      ));

  double _target = 15;

  void _maybeLand() {
    if (_landed || !(landing?.isCompleted ?? true)) return;
    _landed = true;
    dollars += _target;
  }

  List<Override> overrides() =>
      [giftFundingRunnerProvider.overrideWithValue(runner())];

  /// What "Send now" runs in place of the real one: everything but the OS
  /// prompt.
  Future<String?> pay(
          BuildContext context, WidgetRef ref, ClaimedShareLink claim) =>
      ref.read(giftFundingRunnerProvider).pay(claim,
          approve: (intent) async =>
              AuthGrants.issue(intent, method: AuthGrantMethod.biometric));
}
