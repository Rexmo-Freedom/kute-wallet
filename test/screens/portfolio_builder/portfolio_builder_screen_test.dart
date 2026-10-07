import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';
import 'package:kute/screens/shared/portfolio_builder/portfolio_builder_screen.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The runtime policy and the venue's location answer, as the test sets
/// them. Everything is allowed until a capability is put in [denied] or
/// the venue is [venueRestricted].
class _Policy extends Fake implements RuntimeCapabilitiesService {
  final Map<String, CapabilityDecision> denied = {};
  bool venueRestricted = false;
  bool fails = false;
  final List<List<String>> checks = [];

  @override
  CapabilityDecision decision(String id) =>
      denied[id] ?? const CapabilityDecision(allowed: true);
  @override
  bool allows(String id) => decision(id).allowed;
  @override
  String? blockReason(String id) =>
      decision(id).allowed ? null : decision(id).message;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {
    checks.add(ids.toList());
    if (fails) throw StateError('offline');
    if (venueRestricted) {
      throw const ProviderAvailabilityException(ProviderAvailability(
          InvestmentProvider.polymarket,
          ProviderAvailabilityStatus.restricted));
    }
    for (final id in ids) {
      if (!decision(id).allowed) {
        throw CapabilityUnavailableException(id, decision(id));
      }
    }
  }
}

const _countryBlocked =
    CapabilityDecision(allowed: false, reason: 'country_blocked');

const _event = PolymarketEvent(
    id: 'rain',
    slug: 'rain',
    title: 'Will it rain tomorrow?',
    volume: 100,
    liquidity: 100,
    category: 'weather',
    conditionId: 'condition',
    outcomes: [
      PolymarketOutcome(name: 'Yes', price: .6, tokenId: 'yes'),
      PolymarketOutcome(name: 'No', price: .4, tokenId: 'no')
    ]);
// An event with many outcomes, each a Yes/No market of its own.
const _race = PolymarketEvent(
    id: 'race',
    slug: 'race',
    title: 'Who wins the race?',
    volume: 2500000,
    liquidity: 100,
    category: 'politics',
    conditionId: 'race-condition',
    outcomes: [
      PolymarketOutcome(
          name: 'Ana',
          price: .5,
          tokenId: 'ana-yes',
          noTokenId: 'ana-no',
          conditionId: 'ana-c'),
      PolymarketOutcome(
          name: 'Bruno',
          price: .3,
          tokenId: 'bruno-yes',
          noTokenId: 'bruno-no',
          conditionId: 'bruno-c'),
      PolymarketOutcome(
          name: 'Carla',
          price: .15,
          tokenId: 'carla-yes',
          noTokenId: 'carla-no',
          conditionId: 'carla-c'),
      PolymarketOutcome(name: 'Duarte', price: .05),
    ]);

// A game whose two sides are the market's own outcomes.
const _game = PolymarketEvent(
    id: 'game',
    slug: 'game',
    title: 'Lions vs Tigers',
    volume: 100,
    liquidity: 100,
    category: 'sports',
    conditionId: 'game-condition',
    teams: [
      PolymarketTeam(name: 'Lions'),
      PolymarketTeam(name: 'Tigers'),
    ],
    outcomes: [
      PolymarketOutcome(name: 'Lions', price: .7, tokenId: 'lions'),
      PolymarketOutcome(name: 'Tigers', price: .3, tokenId: 'tigers'),
    ]);

const _market = HlMarket(
    coin: 'BTC',
    wireCoin: 'BTC',
    assetId: 0,
    kind: HlMarketKind.perp,
    szDecimals: 5,
    maxLeverage: 20,
    onlyIsolated: false,
    markPx: 60000,
    midPx: 60000,
    prevDayPx: 59000,
    dayNtlVlm: 100000);

Future<ProviderContainer> _pump(WidgetTester tester,
    {BuilderPool pool = BuilderPool.predictions,
    double available = 100,
    double width = 390,
    double textScale = 1,
    bool dark = false,
    _Policy? policy,
    List<PolymarketEvent> events = const [_event],
    List<PolymarketEvent> crypto = const []}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rules = policy ?? _Policy();
  RuntimeCapabilitiesService.debugInstance = rules;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  final scope = ProviderContainer(overrides: [
    runtimeCapabilitiesProvider.overrideWithValue(rules),
    polymarketEventsProvider('breaking').overrideWith((_) async => events),
    polymarketEventsProvider('crypto').overrideWith((_) async => crypto),
    polymarketBalanceProvider.overrideWithValue(available),
    hyperliquidBrowseUniverseProvider
        .overrideWithValue(const AsyncData([_market])),
    hyperliquidWithdrawableProvider.overrideWithValue(available),
    hyperliquidSpotBalancesProvider.overrideWithValue([]),
  ]);
  addTearDown(scope.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: scope,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [
              dark ? AppColorsExtension.dark() : AppColorsExtension.light()
            ]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: PortfolioBuilderScreen(pool: pool),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return scope;
}

Future<void> _select(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue · 1 selected'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('prediction selection and shared amount controls survive Back',
      (tester) async {
    final scope = await _pump(tester);
    expect(find.widgetWithText(AppBar, 'Build portfolio'), findsOneWidget);
    expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Select markets'))
            .onPressed,
        isNull);
    await _select(tester, _event.title);
    expect(find.widgetWithText(AppBar, 'Set amounts'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.tap(find.text('Amount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'$50'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set amount'));
    await tester.pumpAndSettle();
    expect(scope.read(builderPredictionLegsProvider).single.amountUsd, 50);
    expect(scope.read(builderPredictionLegsProvider).single.isNo, isTrue);
    await tester.tap(find.text('Review portfolio'));
    await tester.pumpAndSettle();
    expect(find.text('Place 1 prediction'), findsOneWidget);
    await tester.tap(find.byType(KuteBackButton));
    await tester.pumpAndSettle();
    expect(find.text(r'$50.00'), findsWidgets);
    expect(scope.read(builderPredictionLegsProvider).single.isNo, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unfunded review offers Deposit instead of placement',
      (tester) async {
    final scope = await _pump(tester, available: 0);
    await _select(tester, _event.title);
    scope.read(builderPredictionLegsProvider.notifier).setAmount('rain', 10);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review portfolio'));
    await tester.pumpAndSettle();
    expect(find.text('Deposit to Predictions'), findsOneWidget);
    expect(find.text('Place 1 prediction'), findsNothing);
    expect(find.text(r'Add $10.00 to continue.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trading retains side and amount on small screen with large text',
      (tester) async {
    final scope = await _pump(tester,
        pool: BuilderPool.trading, width: 320, textScale: 1.3);
    await _select(tester, 'Bitcoin');
    await tester.tap(find.text('Short'));
    scope.read(builderTradeLegsProvider.notifier).setAmount('BTC|perp', 25);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review portfolio'));
    await tester.pumpAndSettle();
    expect(scope.read(builderTradeLegsProvider).single.isLong, isFalse);
    expect(find.text('SHORT'), findsOneWidget);
    expect(find.text('Place 1 order'), findsOneWidget);
    // The run's fee sits in the order slip's own row.
    expect(find.byType(HyperliquidFeeSummary), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pick card writes its title whole and shows the chance',
      (tester) async {
    const long = PolymarketEvent(
        id: 'long',
        slug: 'long',
        title: 'Will the candidate finish in third place in the first round '
            'of the next presidential election?',
        volume: 100,
        liquidity: 100,
        category: 'politics',
        conditionId: 'long-c',
        outcomes: [
          PolymarketOutcome(name: 'Yes', price: .96, tokenId: 'y'),
          PolymarketOutcome(name: 'No', price: .04, tokenId: 'n')
        ]);
    await _pump(tester, events: [long]);
    final title = tester.widget<Text>(find.text(long.title));
    expect(title.maxLines, isNull);
    final painter = tester.renderObject<RenderParagraph>(find.text(long.title));
    expect(painter.didExceedMaxLines, isFalse);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('96% chance'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an event with many outcomes takes the outcome tapped',
      (tester) async {
    final scope = await _pump(tester, events: [_race]);
    // The two most likely, as the list card shows them.
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Carla'), findsNothing);
    expect(find.text('+2 more'), findsOneWidget);

    await tester.tap(find.text('Bruno'));
    await tester.pumpAndSettle();
    var leg = scope.read(builderPredictionLegsProvider).single;
    expect(leg.title, 'Who wins the race?: Bruno');
    expect(leg.yesTokenId, 'bruno-yes');
    expect(leg.noTokenId, 'bruno-no');
    expect(leg.conditionId, 'bruno-c');
    expect(leg.yesPrice, .3);
    expect(find.text('Continue · 1 selected'), findsOneWidget);

    // Another outcome of the same event takes the first one's place.
    await tester.tap(find.text('+2 more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carla'));
    await tester.pumpAndSettle();
    leg = scope.read(builderPredictionLegsProvider).single;
    expect(leg.yesTokenId, 'carla-yes');

    // An outcome with no token of its own cannot be a leg.
    await tester.tap(find.text('Duarte'));
    await tester.pumpAndSettle();
    expect(scope.read(builderPredictionLegsProvider).single.yesTokenId,
        'carla-yes');

    // The picked outcome again removes the leg.
    await tester.tap(find.text('Carla'));
    await tester.pumpAndSettle();
    expect(scope.read(builderPredictionLegsProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a game takes the team tapped', (tester) async {
    final scope = await _pump(tester, events: [_game]);
    expect(find.text('Lions vs Tigers'), findsNothing);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    await tester.tap(find.text('Tigers'));
    await tester.pumpAndSettle();
    final leg = scope.read(builderPredictionLegsProvider).single;
    expect(leg.title, 'Lions vs Tigers: Tigers');
    expect(leg.yesTokenId, 'tigers');
    expect(leg.yesPrice, .3);
    expect(leg.isNo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a category pill lists that category', (tester) async {
    await _pump(tester, crypto: [_game]);
    expect(find.text(_event.title), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);
    await tester.ensureVisible(find.text('Crypto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crypto'));
    await tester.pumpAndSettle();
    expect(find.text(_event.title), findsNothing);
    expect(find.text('Tigers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'every stage fits a small screen with large text '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      final scope = await _pump(tester,
          events: [_event, _race, _game],
          width: 320,
          textScale: 1.3,
          dark: dark);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(_event.title));
      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue · 2 selected'));
      await tester.pumpAndSettle();
      expect(find.text('Who wins the race?: Ana'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final legs = scope.read(builderPredictionLegsProvider.notifier);
      legs.setAmount('rain', 10);
      legs.setAmount('race', 15);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review portfolio'));
      await tester.pumpAndSettle();
      expect(find.text('Place 2 predictions'), findsOneWidget);
      // Side and chance under the title, the amount on the right.
      expect(find.text(' · 60%'), findsOneWidget);
      expect(find.text(r'$15.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('availability', () {
    void expectNoBuilder() {
      expect(find.byType(TextField), findsNothing);
      expect(find.text(_event.title), findsNothing);
      expect(find.text('Select markets'), findsNothing);
      expect(find.textContaining('Continue'), findsNothing);
    }

    testWidgets('the venue restricts the region: blocked, nothing to pick',
        (tester) async {
      final policy = _Policy()..venueRestricted = true;
      await _pump(tester, policy: policy);
      // The bet slip's gate, asked once on opening.
      expect(policy.checks.single, contains('polymarket.trade'));
      expect(find.text('Not available in your region'), findsOneWidget);
      expect(
          find.textContaining('Polymarket is restricted in the region'),
          findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Close'), findsOneWidget);
      expectNoBuilder();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the policy denies placing predictions: blocked',
        (tester) async {
      final policy = _Policy()..denied['polymarket.trade'] = _countryBlocked;
      await _pump(tester, policy: policy);
      expect(find.text('Not available in your region'), findsOneWidget);
      expect(find.textContaining('restricted in the region'), findsOneWidget);
      expectNoBuilder();
    });

    testWidgets('a kill switch names Predictions and its reason',
        (tester) async {
      final policy = _Policy()
        ..denied['polymarket.trade'] = const CapabilityDecision(
            allowed: false, serverMessage: 'Predictions are paused.');
      await _pump(tester, policy: policy);
      expect(find.text('Predictions unavailable'), findsOneWidget);
      expect(find.text('Predictions are paused.'), findsOneWidget);
      expectNoBuilder();
    });

    testWidgets('a check that cannot be made allows nothing', (tester) async {
      await _pump(tester, policy: _Policy()..fails = true);
      expect(find.text('Predictions unavailable'), findsOneWidget);
      expectNoBuilder();
    });

    testWidgets('a draft from before the block cannot be reached either',
        (tester) async {
      final policy = _Policy();
      final scope = await _pump(tester, policy: policy);
      await _select(tester, _event.title);
      expect(find.widgetWithText(AppBar, 'Set amounts'), findsOneWidget);
      // The policy is withdrawn while the Builder is up.
      policy.denied['polymarket.trade'] = _countryBlocked;
      scope.invalidate(runtimeCapabilitiesProvider);
      await tester.pumpAndSettle();
      expect(find.text('Not available in your region'), findsOneWidget);
      expect(find.text('Review portfolio'), findsNothing);
      expect(find.text('Amount'), findsNothing);
    });

    testWidgets('placing re-checks the gate and places nothing when refused',
        (tester) async {
      final policy = _Policy();
      final scope = await _pump(tester, policy: policy);
      await _select(tester, _event.title);
      scope.read(builderPredictionLegsProvider.notifier).setAmount('rain', 10);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review portfolio'));
      await tester.pumpAndSettle();
      // The venue's answer changes after the slip was built.
      policy.venueRestricted = true;
      policy.checks.clear();
      await tester.tap(find.text('Place 1 prediction'));
      await tester.pumpAndSettle();
      expect(policy.checks.single, contains('polymarket.trade'));
      expect(find.text('Not available in your region'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      // Nothing ran: the leg is still a draft and no run started.
      expect(scope.read(builderPredictionLegsProvider), hasLength(1));
      expect(find.text('Portfolio submissions'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a hidden category has no pill and no markets',
        (tester) async {
      final policy = _Policy()..denied['polymarket.sports'] = _countryBlocked;
      await _pump(tester, policy: policy, events: [_event, _game]);
      expect(find.text('Sports'), findsNothing);
      expect(find.text('Tigers'), findsNothing);
      expect(find.text(_event.title), findsOneWidget);
    });
  });
}
