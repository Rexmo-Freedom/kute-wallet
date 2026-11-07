// "Check connection" on the order ticket (founder decision, October 2026):
// a region refusal makes the ticket's one button "Check connection", never
// a dead one. A tap asks the venues and Kute's policy again; allowed now,
// the refusal goes and the button is the order, ready to place; still
// restricted, the refusal stays with a soft failure tap.
//
// NO SHARE BUTTON ON THE TICKET (founder, 7 November 2026: "just keep it
// on the send"). In SEND MODE (opened from Send; slip_share.dart,
// send_pick_session.dart) the ticket's one primary is the send: "Send $25
// · Long Bitcoin" sends THIS investment (Long, the amount), never an
// order; refused here, "Send the market", the market's card only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/share/slip_share.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/shell_bar_harness.dart';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 60000});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

/// Kute's policy, placing the connection where the test says: a region
/// denial for new positions while [blocked].
class _Policy extends Fake implements RuntimeCapabilitiesService {
  bool blocked = true;
  static const _region =
      CapabilityDecision(allowed: false, reason: 'country_blocked');
  @override
  CapabilityDecision decision(String id) => blocked && id == 'hyperliquid.trade'
      ? _region
      : const CapabilityDecision(allowed: true);
  @override
  bool allows(String id) => decision(id).allowed;
  @override
  String? blockReason(String id) =>
      decision(id).allowed ? null : decision(id).message;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {
    for (final id in ids) {
      if (!decision(id).allowed) {
        throw CapabilityUnavailableException(id, decision(id));
      }
    }
  }

  @override
  Future<bool> networkChanged() async => true;
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

/// The Investing account, answered when the test says so.
class _Account extends HlAccountNotifier {
  _Account(this.answer);
  final Future<HlAccountSnapshot> answer;
  @override
  Future<HlAccountSnapshot> build() => answer;
}

HlAccountSnapshot _snapshot(double withdrawable) => HlAccountSnapshot(
      accountValue: withdrawable,
      withdrawable: withdrawable,
      totalMarginUsed: 0,
      positions: const [],
      spotBalances: const [],
    );

const _market = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

Future<void> _pumpSlip(WidgetTester tester, Future<HlAccountSnapshot> account,
    _Policy policy, {double? initialUsd, SendPickSession? sendPick}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: false,
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountProvider.overrideWith(() => _Account(account)),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      usdBalanceProvider.overrideWith((_) => 0),
    ],
    // The bar over the slip is the slip's button (shell_bar_harness.dart).
    child: shellBarApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: HlOrderSlipSheet(
              market: _market,
              initialIsLong: true,
              initialUsd: initialUsd,
              sendPick: sendPick),
        ),
      ),
    ),
  ));
  await _frames(tester);
}

/// The loading dots animate for as long as they wait: pump, never settle.
Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}


const _regionSentence =
    'This feature is restricted in the region your internet connection '
    'appears to be in. If this isn\'t where you are, check your VPN '
    'settings.';

void main() {
  late _Policy policy;
  late List<String> triggers;
  late List<ContinuousHapticsCall> haptics;
  late InvestmentProviderAvailability venues;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    policy = _Policy();
    RuntimeCapabilitiesService.debugInstance = policy;
    triggers = [];
    haptics = ContinuousHaptics.debugLog = [];
    KuteHaptics.debugReset();
    KuteHaptics.debugForeground = () => true;
    venues = InvestmentProviderAvailability(
      client: MockClient((request) async => request.url.host ==
              'api.hyperliquid.xyz'
          ? http.Response(
              '{"acceptedTerms":true,"userAllowed":true,"restrictions":"n"}',
              200)
          : http.Response('{"blocked":false}', 200)),
      report: ({
        required String venue,
        required String trigger,
        required bool changed,
        required String result,
      }) =>
          triggers.add('$venue:$trigger'),
    );
    RegionFreshness.debugVenues = venues;
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    RegionFreshness.debugVenues = null;
    ContinuousHaptics.debugLog = null;
    ContinuousHaptics.debugReset();
    KuteHaptics.debugReset();
    venues.dispose();
  });

  Future<void> tapCheck(WidgetTester tester) async {
    expect(barPrimaryLabel(tester), 'Check connection');
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 20);
  }

  testWidgets('a region refusal: the button is "Check connection", live',
      (tester) async {
    await _pumpSlip(tester, Future.value(_snapshot(500)), policy);
    expect(find.widgetWithText(CapabilityBlockNote, _regionSentence),
        findsOneWidget);
    expect(barPrimaryLabel(tester), 'Check connection');
    expect(barPrimaryEnabled(tester), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('now allowed: the refusal lifts and the order is ready',
      (tester) async {
    await _pumpSlip(tester, Future.value(_snapshot(500)), policy);
    policy.blocked = false;
    await tapCheck(tester);
    expect(find.byType(CapabilityBlockNote), findsNothing);
    expect(barPrimaryLabel(tester), startsWith('Long '));
    expect(barPrimaryEnabled(tester), isTrue);
    expect(triggers, containsAll(['polymarket:manual', 'hyperliquid:manual']));
    expect(haptics.where((c) => c.method == 'softTap'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('still restricted: the refusal stays, with a failure tap',
      (tester) async {
    await _pumpSlip(tester, Future.value(_snapshot(500)), policy);
    await tapCheck(tester);
    expect(find.widgetWithText(CapabilityBlockNote, _regionSentence),
        findsOneWidget);
    expect(barPrimaryLabel(tester), 'Check connection');
    expect(barPrimaryBusy(tester), isFalse);
    expect(barPrimaryEnabled(tester), isTrue);
    expect(haptics.where((c) => c.method == 'softTap'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  final share = find.byKey(const ValueKey('kute-bar-share'));

  testWidgets('the ordinary ticket has no share button', (tester) async {
    policy.blocked = false;
    await _pumpSlip(tester, Future.value(_snapshot(500)), policy,
        initialUsd: 25);
    expect(share, findsNothing);
    expect(find.byKey(const ValueKey('send-pick-chip')), findsNothing);
    expect(barPrimaryLabel(tester), isNot(startsWith('Send ')));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('send mode', () {
    late List<(SlipSendRoute, SlipSharePick)> sends;
    setUp(() {
      sends = [];
      SlipShare.debugRoute = (r, p) => sends.add((r, p));
      SlipShare.debugOpen = false;
    });
    tearDown(() {
      SlipShare.debugRoute = null;
      SlipShare.debugOpen = true;
    });

    SendPickSession session() =>
        SendPickSession(entrySource: 'dollar_send', recipientName: 'Ana');

    testWidgets(
        'the primary is the send: it sends THIS investment, Long and the '
        'amount; the chip says who it is for', (tester) async {
      policy.blocked = false;
      await _pumpSlip(tester, Future.value(_snapshot(500)), policy,
          initialUsd: 25, sendPick: session());
      expect(barPrimaryLabel(tester), r'Send $25 · Long Bitcoin');
      expect(barPrimaryEnabled(tester), isTrue);
      expect(share, findsNothing);
      expect(find.text('For Ana'), findsOneWidget);
      await tapBarPrimary(tester, settle: false);
      await _frames(tester, 2);
      final (route, pick) = sends.single;
      expect(route, SlipSendRoute.pick);
      expect(pick.investing, isTrue);
      expect(pick.slug, 'BTC');
      expect(pick.outcome, 'Long');
      expect(pick.side, 'long');
      expect(pick.amountUsd, 25);
      expect(pick.blocked, isFalse);
      expect(pick.entrySource, kSendModeSlipSource);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('nothing typed: disabled, it says to enter an amount',
        (tester) async {
      policy.blocked = false;
      await _pumpSlip(tester, Future.value(_snapshot(500)), policy,
          sendPick: session());
      expect(barPrimaryEnabled(tester), isFalse);
      expect(barPrimaryContext(tester).disabledLabel,
          'Enter an amount to send');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('refused here: "Send the market", the market\'s card only',
        (tester) async {
      await _pumpSlip(tester, Future.value(_snapshot(500)), policy,
          initialUsd: 25, sendPick: session());
      expect(barPrimaryLabel(tester), 'Send the market');
      await tapBarPrimary(tester, settle: false);
      await _frames(tester, 2);
      expect(sends.single.$1, SlipSendRoute.market);
      expect(sends.single.$2.investing, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
