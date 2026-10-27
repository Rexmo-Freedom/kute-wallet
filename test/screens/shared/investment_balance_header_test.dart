import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/screens/shared/pending_deposit_line.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/portfolio_arrow_glyph.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/venue_total_cache_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A bet funded through Investments, as the header names it.
const _bet = InFlightOrder(
    id: 'fo_bet',
    venue: OneBalanceVenue.predictions,
    orderUsd: 5,
    side: 'Yes',
    market: 'Lakers vs Celtics');

/// An Investing order funded through Investments.
const _order = InFlightOrder(
    id: 'fo_order',
    venue: OneBalanceVenue.investing,
    orderUsd: 7.25,
    side: 'Long',
    market: 'NVDA');

Future<void> _pump(WidgetTester tester, Widget child,
    {List<Override> overrides = const [],
    Locale? locale,
    List<WalletConfig> wallets = const [],
    int balancePrivacy = 0,
    bool settle = true}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              balancePrivacy: balancePrivacy,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: '',
              reviewDone: true,
              wallets: wallets,
            ))),
        pendingPredictionsDepositUsdProvider.overrideWith((_) => 0),
        pendingPredictionsWithdrawalUsdProvider.overrideWith((_) => 0),
        pendingTradingDepositUsdProvider.overrideWith((_) => 0),
        pendingTradingWithdrawalUsdProvider.overrideWith((_) => 0),
        ...overrides,
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              fontFamily: 'Inter',
              splashFactory: NoSplash.splashFactory,
              extensions: [AppColorsExtension.light()]),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(highContrast: true),
              child: child!),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      )));
  // A skeleton shimmers for as long as it is up: never settles.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf')))
        .load();
  });
  for (final product in InvestmentsProduct.values) {
    testWidgets(
        '${product.name} header keeps correct main balance and separate portfolio amount',
        (tester) async {
      await _pump(tester, InvestmentBalanceHeader(product: product),
          overrides: [
            investmentBalancesProvider(product).overrideWith((_) =>
                const InvestmentBalances(
                    available: 42,
                    portfolio: 58,
                    total: 100,
                    positions: 48,
                    committed: 10,
                    hasPortfolioContent: true)),
          ]);
      final header =
          tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
      // Both pools lead with the total and split it underneath: Investing
      // no longer leads with spendable cash alone.
      expect(header.amountText, r'$100.00');
      expect(
          header.totalLabel,
          product == InvestmentsProduct.predictions
              ? 'Predictions total'
              : 'Investing total');
      expect(header.investedText,
          product == InvestmentsProduct.predictions ? r'$48.00' : r'$58.00');
      expect(header.availableText, r'$42.00');
      // The venue's top button is Deposit; Portfolio lives in the dock.
      // Named for the venue and led by its mark, the way the Bitcoin and
      // Dollars top buttons are (Purchase Bitcoin, Dollar deposit).
      expect(find.byType(VenueDepositButton), findsOneWidget);
      final label = product == InvestmentsProduct.predictions
          ? 'Predictions deposit'
          : 'Investing deposit';
      expect(find.text(label), findsOneWidget);
      final button = tester.widget<AppButton>(find.descendant(
          of: find.byType(VenueDepositButton),
          matching: find.byType(AppButton)));
      expect(
          button.svgAsset,
          product == InvestmentsProduct.predictions
              ? 'lib/assets/polymarket-logo.svg'
              : 'lib/assets/hyperliquid-logo.svg');
      expect(button.icon, isNull);
      expect(button.height, isNull);
      expect(find.text('Deposit'), findsNothing);
      expect(find.text('Portfolio'), findsNothing);
      expect(find.text('Withdraw'), findsNothing);
      // Earn moved to the dollar balance and the Predictions Build shortcut
      // is hidden: the header carries no shortcut beside Deposit.
      expect(find.text('Earn'), findsNothing);
      expect(find.text('Build'), findsNothing);
      expect(find.textContaining('Updating'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('${product.name} cash only keeps Deposit available',
        (tester) async {
      await _pump(tester, InvestmentBalanceHeader(product: product),
          overrides: [
            investmentBalancesProvider(product).overrideWith((_) =>
                const InvestmentBalances(
                    available: 100,
                    portfolio: 0,
                    total: 100,
                    positions: 0,
                    committed: 0)),
          ]);
      expect(find.byType(VenueDepositButton), findsOneWidget);
    });
    testWidgets(
        '${product.name} full-screen header omits Deposit (the dock has it)',
        (tester) async {
      await _pump(tester,
          InvestmentBalanceHeader(product: product, showDepositButton: false),
          overrides: [
            investmentBalancesProvider(product).overrideWith((_) =>
                const InvestmentBalances(
                    available: 42,
                    portfolio: 58,
                    total: 100,
                    positions: 48,
                    committed: 10,
                    hasPortfolioContent: true)),
          ]);
      expect(find.byType(VenueDepositButton), findsNothing);
      expect(find.textContaining('deposit'), findsNothing);
    });
    testWidgets(
        '${product.name} dock carries Portfolio alone with no account read',
        (tester) async {
      await _pump(
          tester,
          Column(mainAxisSize: MainAxisSize.min, children: [
            InvestmentActionBar(product: product),
          ]));
      // Portfolio, and search in the square. No Withdraw: with one
      // balance money comes back to Dollars on its own.
      final bar =
          tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
      expect(bar.actions.map((a) => a.label), ['Portfolio']);
      expect(bar.actions.map((a) => a.trackingId), ['portfolio']);
      expect(bar.actions.every((a) => a.onTap != null), isTrue);
      expect(find.text('Deposit'), findsNothing);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.text('Ask Sal anything'), findsNothing);
      expect(find.textContaining('available'), findsNothing);
      expect(find.textContaining('Updating'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  group('one balance (the Investments hero)', () {
    const known = OneBalanceState(
        dollarsUsd: 42.5,
        investedUsd: 57.5,
        investingKnown: true,
        predictionsKnown: true);
    PoolBalanceHeader header(WidgetTester tester) =>
        tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));
    Future<void> pumpOne(WidgetTester tester, OneBalanceState state,
            {int balancePrivacy = 0,
            Locale? locale,
            VoidCallback? onTap,
            bool settle = true}) =>
        _pump(
            tester,
            InvestmentBalanceHeader(
                product: InvestmentsProduct.trading,
                oneBalance: true,
                onTap: onTap),
            balancePrivacy: balancePrivacy,
            locale: locale,
            settle: settle,
            overrides: [oneBalanceProvider.overrideWithValue(state)]);

    final chevron = find.byKey(const ValueKey('investments-balance-chevron'));

    testWidgets(
        'no title: the total alone, no "Invested" under it (Balances '
        'carries it, never twice), no Available, no deposit door',
        (tester) async {
      await pumpOne(tester, known);
      expect(header(tester).amountText, r'$100.00');
      expect(header(tester).totalLabel, isNull);
      expect(find.text('Investments total'), findsNothing);
      expect(find.text('Available '), findsNothing);
      expect(find.textContaining('Available'), findsNothing);
      // Not tappable without a door: no arrow, no press feedback.
      expect(chevron, findsNothing);
      expect(find.byKey(const ValueKey('investments-balance')), findsNothing);
      expect(header(tester).availableText, isNull);
      expect(header(tester).investedText, isNull);
      expect(find.textContaining('Invested'), findsNothing);
      expect(find.text(r'$57.50'), findsNothing);
      expect(header(tester).stale, isFalse);
      expect(header(tester).loading, isFalse);
      expect(header(tester).investedChild, isNull);
      expect(find.byType(VenueDepositButton), findsNothing);
      expect(find.textContaining('deposit'), findsNothing);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('Investing total'), findsNothing);
      expect(find.text('Predictions total'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a venue still to answer counts as zero and dims the figure',
        (tester) async {
      // A stale figure sweeps for as long as it is stale: never settles.
      await pumpOne(
          tester, known.copyWith(investedUsd: 0, predictionsKnown: false),
          settle: false);
      expect(header(tester).amountText, r'$42.50');
      expect(header(tester).stale, isTrue);
      expect(header(tester).loading, isFalse);
      expect(find.text('—'), findsNothing);
      // Dimmed and sweeping over the digits, which stay text.
      final shimmer = tester.widget<StaleShimmer>(find.descendant(
          of: find.byType(PoolBalanceHeader),
          matching: find.byType(StaleShimmer)));
      expect(shimmer.stale, isTrue);
      expect(find.text('4'), findsWidgets);
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets(
        'Dollars the SDK has not confirmed yet dim the figure: the ledger '
        'sum, sweeping, never a confident number', (tester) async {
      await _pump(
          tester,
          const InvestmentBalanceHeader(
              product: InvestmentsProduct.trading, oneBalance: true),
          settle: false,
          overrides: [
            oneBalanceProvider.overrideWithValue(known),
            usdBalanceUnknownProvider.overrideWithValue(true),
          ]);
      expect(header(tester).amountText, r'$100.00');
      expect(header(tester).stale, isTrue);
      expect(header(tester).loading, isFalse);
      final shimmer = tester.widget<StaleShimmer>(find.descendant(
          of: find.byType(PoolBalanceHeader),
          matching: find.byType(StaleShimmer)));
      expect(shimmer.stale, isTrue);
    });

    testWidgets(
        'money on a rail replaces the split with the in-flight lines, in '
        'order, and the total counts it', (tester) async {
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(kind: InFlightKind.incomingDollars, usd: 20),
            InFlightMove(
                kind: InFlightKind.fromVenue,
                venue: OneBalanceVenue.investing,
                usd: 12.4),
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.predictions,
                usd: 5,
                order: _bet),
          ], waiting: const {
            OneBalanceVenue.investing: 0.6
          }));
      // 42.5 + 57.5 + 5 + 12.4 + 20 + 0.6: the sweep home is counted, it
      // only has no line.
      expect(header(tester).amountText, r'$138.00');
      expect(header(tester).availableText, isNull);
      expect(header(tester).investedText, isNull);
      final lines = [
        r'Placing $5.00 on Yes · Lakers vs Celtics',
        r'Incoming $20.00',
        r'$0.60 unavailable until balancing completes',
      ];
      expect(find.byType(PendingDepositLine), findsNWidgets(3));
      expect(find.textContaining('coming back'), findsNothing);
      expect(find.textContaining('moving to'), findsNothing);
      double top(String line) => tester.getTopLeft(find.text(line)).dy;
      for (var i = 0; i < lines.length; i++) {
        expect(find.text(lines[i]), findsOneWidget, reason: lines[i]);
        if (i > 0) expect(top(lines[i]), greaterThan(top(lines[i - 1])));
      }
      expect(find.textContaining('arriving'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'dust left on a venue is part of the total, never an unavailable '
        'line', (tester) async {
      // The provider folds the sweeper's dust (the $0.06 CCTP reserve)
      // into the venue cash: in the total, like any venue cash; nothing
      // waits.
      await pumpOne(
          tester,
          known.copyWith(
              dollarsUsd: 6.20,
              investedUsd: 0,
              venueCash: const {OneBalanceVenue.investing: 0.06}));
      expect(header(tester).amountText, r'$6.26');
      expect(header(tester).availableText, isNull);
      expect(header(tester).investedText, isNull);
      expect(header(tester).investedChild, isNull);
      expect(find.textContaining('unavailable'), findsNothing);
    });

    testWidgets('each in-flight line on its own', (tester) async {
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.investing,
                usd: 7.25,
                order: _order),
          ]));
      expect(find.text(r'Opening $7.25 NVDA order'), findsOneWidget);
      expect(find.byType(PendingDepositLine), findsOneWidget);
      // Margin added to a position through Investments names the margin,
      // never an order.
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.investing,
                usd: 30,
                order: InFlightOrder(
                    id: 'fo_margin',
                    venue: OneBalanceVenue.investing,
                    orderUsd: 30,
                    side: 'Long',
                    market: 'TSLA',
                    margin: true)),
          ]));
      expect(find.text(r'Adding $30.00 margin to TSLA'), findsOneWidget);
      expect(find.textContaining('order'), findsNothing);
      // The Bitcoin leg of the same order (dollars arriving for it) and
      // its move into the venue: one line, the order's.
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.predictions,
                usd: 2,
                order: _bet),
            InFlightMove(
                kind: InFlightKind.incomingDollars, usd: 3.1, order: _bet),
          ]));
      expect(find.text(r'Placing $5.00 on Yes · Lakers vs Celtics'),
          findsOneWidget);
      expect(find.textContaining('Incoming'), findsNothing);
      expect(find.byType(PendingDepositLine), findsOneWidget);
      // The idle sweep home is plumbing: no line (and no Invested line:
      // Balances carries it).
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.fromVenue,
                venue: OneBalanceVenue.predictions,
                usd: 3),
          ]));
      expect(find.textContaining('coming back'), findsNothing);
      expect(find.byType(PendingDepositLine), findsNothing);
      expect(header(tester).investedText, isNull);
      expect(header(tester).investedChild, isNull);
      // Money moving to a venue for no order: no line either.
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.investing,
                usd: 4),
          ]));
      expect(find.byType(PendingDepositLine), findsNothing);
      await pumpOne(tester,
          known.copyWith(waiting: const {OneBalanceVenue.predictions: 0.8}));
      expect(find.text(r'$0.80 unavailable until balancing completes'),
          findsOneWidget);
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(kind: InFlightKind.incomingDollars, usd: 20),
          ]));
      expect(find.text(r'Incoming $20.00'), findsOneWidget);
    });

    testWidgets(
        'with the slip closed, each source of the order shows its own '
        'state under the order', (tester) async {
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.predictions,
                usd: 8,
                order: InFlightOrder(
                    id: 'fo_legs',
                    venue: OneBalanceVenue.predictions,
                    orderUsd: 15,
                    side: 'Yes',
                    market: 'Lakers',
                    legs: [
                      MoneyStep(
                          id: 'leg:bitcoin',
                          kind: MoneyStepKind.leg,
                          from: MoneyPlace.bitcoin,
                          usd: 8,
                          status: MoneyStepStatus.running),
                      MoneyStep(
                          id: 'leg:dollars',
                          kind: MoneyStepKind.leg,
                          from: MoneyPlace.dollars,
                          usd: 5,
                          status: MoneyStepStatus.done),
                      MoneyStep(
                          id: 'leg:investing',
                          kind: MoneyStepKind.leg,
                          from: MoneyPlace.investing,
                          usd: 2,
                          status: MoneyStepStatus.failed),
                    ])),
          ]));
      expect(find.text(r'Placing $15.00 on Yes · Lakers'), findsOneWidget);
      expect(find.text(r'Moving $8.00 from Bitcoin'), findsOneWidget);
      expect(find.text(r'Moved $5.00 from Dollars'), findsOneWidget);
      expect(find.text("\$2.00 from Investing didn't move"), findsOneWidget);
      expect(find.byType(PendingDepositLine), findsNWidgets(4));
    });

    testWidgets('the lines are in the app language', (tester) async {
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.predictions,
                usd: 5,
                order: _bet),
          ]),
          locale: const Locale('pt'));
      // The line's own translation lives in the ARB files.
      expect(find.textContaining('A colocar'), findsOneWidget);
      expect(find.textContaining('Placing'), findsNothing);
    });

    testWidgets(
        'the whole block is one tap, with the portfolio glyph right after '
        'the total', (tester) async {
      var taps = 0;
      await pumpOne(tester, known, onTap: () => taps++);
      expect(chevron, findsOneWidget);
      expect(tester.widget(chevron), isA<PortfolioArrowGlyph>());
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      // The arrow sits right after the big total, on its line.
      final total = find.byType(RollingNumberText).first;
      expect(tester.getTopLeft(chevron).dx,
          greaterThanOrEqualTo(tester.getTopRight(total).dx));
      expect(tester.getCenter(chevron).dy,
          lessThan(tester.getBottomLeft(total).dy));
      await tester.tap(total);
      await tester.pumpAndSettle();
      expect(taps, 1);
      await tester.tap(chevron);
      await tester.pumpAndSettle();
      expect(taps, 2);
    });

    testWidgets(
        'the in-flight lines are still part of the tap (no activity door of '
        'their own), the chevron beside them', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      var taps = 0;
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.predictions,
                usd: 5,
                order: _bet),
          ]),
          onTap: () => taps++);
      expect(chevron, findsOneWidget);
      expect(
          InvestmentBalanceHeader.showsInFlight(known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.predictions,
                usd: 5,
                order: _bet),
          ])),
          isTrue);
      // A sweep home alone has no line, so the split stays.
      expect(
          InvestmentBalanceHeader.showsInFlight(known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.fromVenue,
                venue: OneBalanceVenue.investing,
                usd: 5),
          ])),
          isFalse);
      expect(InvestmentBalanceHeader.showsInFlight(known), isFalse);
      expect(
          InvestmentBalanceHeader.showsInFlight(
              known.copyWith(waiting: const {OneBalanceVenue.investing: 0.6})),
          isTrue);
      await tester.tap(find.text(r'Placing $5.00 on Yes · Lakers vs Celtics'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(events.where((e) => e.$1 == 'activity_history_opened'), isEmpty);
    });

    testWidgets('hidden balances mask the total, the split and the lines',
        (tester) async {
      await pumpOne(
          tester,
          known.copyWith(inFlight: const [
            InFlightMove(
                kind: InFlightKind.toVenue,
                venue: OneBalanceVenue.predictions,
                usd: 5,
                order: _bet),
          ]),
          balancePrivacy: 1);
      expect(header(tester).amountText, '••••••');
      expect(find.text('Placing •••••• on Yes · Lakers vs Celtics'),
          findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
    });
  });

  testWidgets('the split line is in the app language, never English',
      (tester) async {
    await _pump(tester,
        const InvestmentBalanceHeader(product: InvestmentsProduct.predictions),
        locale: const Locale('pt'),
        overrides: [
          investmentBalancesProvider(InvestmentsProduct.predictions)
              .overrideWith((_) => const InvestmentBalances(
                  available: 1.95,
                  portfolio: 2.07,
                  total: 4.03,
                  positions: 2.07,
                  committed: 0,
                  hasPortfolioContent: true)),
        ]);
    expect(find.text('Disponível '), findsOneWidget);
    expect(find.text('Available '), findsNothing);
  });
  group('a total that cannot load is never a bare dash', () {
    late Directory hiveDir;
    final spending =
        WalletConfig(id: 'w1', name: 'Spending', sparkEnabled: true);

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('venue_total_cache');
      Hive.init(hiveDir.path);
      // In memory: a write from a build inside the test's fake clock never
      // waits on the disk.
      await Hive.openBox<double>(VenueTotalCacheService.boxName,
          bytes: Uint8List(0));
    });
    setUp(() => Hive.box<double>(VenueTotalCacheService.boxName).clear());
    tearDownAll(() async {
      await Hive.close();
      await hiveDir.delete(recursive: true);
    });

    PoolBalanceHeader header(WidgetTester tester) =>
        tester.widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader));

    testWidgets('nothing known yet: a skeleton of the figure, not a dash',
        (tester) async {
      await _pump(tester,
          const InvestmentBalanceHeader(product: InvestmentsProduct.trading),
          wallets: [spending],
          settle: false,
          overrides: [
            investmentBalancesProvider(InvestmentsProduct.trading)
                .overrideWith((_) => const InvestmentBalances()),
          ]);
      expect(header(tester).loading, isTrue);
      expect(find.byType(KuteSkeleton), findsOneWidget);
      expect(find.byType(RollingNumberText), findsNothing);
      expect(find.text('—'), findsNothing);
      expect(find.textContaining('Updating'), findsNothing);
    });

    for (final product in InvestmentsProduct.values) {
      testWidgets('${product.name}: a failed read keeps the last total, dimmed',
          (tester) async {
        final balances = StateProvider((_) => const InvestmentBalances(
            available: 42, portfolio: 58, total: 100, positions: 58));
        await _pump(tester, InvestmentBalanceHeader(product: product),
            wallets: [
              spending
            ],
            overrides: [
              investmentBalancesProvider(product)
                  .overrideWith((ref) => ref.watch(balances)),
            ]);
        expect(header(tester).amountText, r'$100.00');
        expect(header(tester).stale, isFalse);
        expect(
            VenueTotalCacheService.read(
                'w1',
                product == InvestmentsProduct.trading
                    ? 'trading'
                    : 'predictions'),
            100);

        // The next read fails: no fresh total.
        final container = ProviderScope.containerOf(
            tester.element(find.byType(InvestmentBalanceHeader)));
        container.read(balances.notifier).state = const InvestmentBalances();
        // Stale, the figure sweeps: it never settles.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(header(tester).loading, isFalse);
        expect(header(tester).amountText, r'$100.00');
        expect(header(tester).stale, isTrue);
        expect(header(tester).investedText, isNull);
        final figure = tester.widget<RollingNumberText>(find.descendant(
            of: find.byType(PoolBalanceHeader),
            matching: find.byType(RollingNumberText)));
        expect(figure.style.color, AppColorsExtension.light().textSecondary);
        expect(
            tester
                .widget<StaleShimmer>(find.descendant(
                    of: find.byType(PoolBalanceHeader),
                    matching: find.byType(StaleShimmer)))
                .stale,
            isTrue);
        expect(find.text('—'), findsNothing);

        // The next sync brings it back fresh.
        container.read(balances.notifier).state = const InvestmentBalances(
            available: 50, portfolio: 70, total: 120, positions: 70);
        await tester.pumpAndSettle();
        expect(header(tester).amountText, r'$120.00');
        expect(header(tester).stale, isFalse);
        // Fresh again: the sweep is gone and nothing is left ticking.
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    }

    testWidgets(
        'main Investments retains its total through refresh, with no '
        'Invested line', (tester) async {
      final state = StateProvider((_) => const OneBalanceState(
          dollarsUsd: 42,
          investedUsd: 58,
          investingKnown: true,
          predictionsKnown: true));
      await _pump(
          tester,
          const InvestmentBalanceHeader(
              product: InvestmentsProduct.trading, oneBalance: true),
          wallets: [
            spending
          ],
          overrides: [
            oneBalanceProvider.overrideWith((ref) => ref.watch(state)),
            usdBalanceUnknownProvider.overrideWithValue(false),
          ]);
      expect(header(tester).amountText, r'$100.00');
      expect(header(tester).investedText, isNull);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(InvestmentBalanceHeader)));
      container.read(state.notifier).state = const OneBalanceState(
          dollarsUsd: 0,
          investedUsd: 0,
          dollarsKnown: false,
          investingKnown: false,
          predictionsKnown: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(header(tester).amountText, r'$100.00');
      expect(header(tester).investedText, isNull);
      expect(header(tester).stale, isTrue);
      // A completed, genuinely empty read must replace the saved figure.
      container.read(state.notifier).state =
          const OneBalanceState(investingKnown: true, predictionsKnown: true);
      await tester.pumpAndSettle();
      expect(header(tester).amountText, r'$0.00');
      expect(header(tester).investedText, isNull);
      expect(header(tester).stale, isFalse);
    });

    test('main display snapshot is stored and scoped per wallet', () async {
      resolveInvestmentsDisplay(
          walletId: 'w1', total: 100, invested: 58, known: true);
      resolveInvestmentsDisplay(
          walletId: 'w2', total: 23, invested: 7, known: true);
      final saved = resolveInvestmentsDisplay(
          walletId: 'w1', total: 0, invested: 0, known: false);
      expect(saved, (total: 100.0, invested: 58.0, stale: true));
      expect(
          resolveInvestmentsDisplay(
              walletId: 'w2', total: 0, invested: 0, known: false),
          (total: 23.0, invested: 7.0, stale: true));
      expect(
          resolveInvestmentsDisplay(
                  walletId: 'new', total: 0, invested: 0, known: false)
              .total,
          0);
      expect(
          resolveInvestmentsDisplay(
                  walletId: null, total: 0, invested: 0, known: false)
              .total,
          0);
      await VenueTotalCacheService.deleteWallet('w1');
      expect(
          resolveInvestmentsDisplay(
                  walletId: 'w1', total: 0, invested: 0, known: false)
              .total,
          0);
      expect(
          resolveInvestmentsDisplay(
                  walletId: 'w2', total: 0, invested: 0, known: false)
              .total,
          23);
    });

    testWidgets("another wallet's total never stands in", (tester) async {
      VenueTotalCacheService.write('w2', 'predictions', 55);
      await _pump(
          tester,
          const InvestmentBalanceHeader(
              product: InvestmentsProduct.predictions),
          wallets: [spending],
          settle: false,
          overrides: [
            investmentBalancesProvider(InvestmentsProduct.predictions)
                .overrideWith((_) => const InvestmentBalances()),
          ]);
      expect(header(tester).loading, isTrue);
      expect(find.text(r'$55.00'), findsNothing);
    });

    test('a deleted wallet forgets its totals', () async {
      VenueTotalCacheService.write('w1', 'predictions', 10);
      VenueTotalCacheService.write('w1', 'trading', 20);
      VenueTotalCacheService.write('w10', 'trading', 30);
      await VenueTotalCacheService.deleteWallet('w1');
      expect(VenueTotalCacheService.read('w1', 'predictions'), isNull);
      expect(VenueTotalCacheService.read('w1', 'trading'), isNull);
      expect(VenueTotalCacheService.read('w10', 'trading'), 30);
    });
  });
  testWidgets('the venue Deposit button invokes its flow', (tester) async {
    var taps = 0;
    await _pump(
        tester,
        VenueDepositButton(
            product: InvestmentsProduct.trading,
            source: 'trading',
            onTap: () => taps++));
    await tester.tap(find.text('Investing deposit'));
    expect(taps, 1);
  });
  testWidgets('an unavailable venue Deposit renders disabled', (tester) async {
    await _pump(
        tester,
        const VenueDepositButton(
            product: InvestmentsProduct.trading,
            source: 'trading',
            onTap: null));
    await tester.tap(find.text('Investing deposit'));
    expect(find.text('Investing deposit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('the venue Deposit label is translated', (tester) async {
    await _pump(
        tester,
        VenueDepositButton(
            product: InvestmentsProduct.predictions,
            source: 'predictions',
            onTap: () {}),
        locale: const Locale('pt'));
    expect(find.text('Depósito em Previsões'), findsOneWidget);
  });
}
