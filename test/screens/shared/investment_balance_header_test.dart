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
import 'package:kute/providers/pending_pool_deposits_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/services/venue_total_cache_service.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {List<Override> overrides = const [],
    Locale? locale,
    List<WalletConfig> wallets = const [],
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
              balancePrivacy: 0,
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
        '${product.name} dock carries Portfolio and Withdraw with no account read',
        (tester) async {
      await _pump(
          tester,
          Column(mainAxisSize: MainAxisSize.min, children: [
            InvestmentActionBar(product: product),
          ]));
      // Portfolio on the left (the venue's top button is Deposit), Withdraw
      // on the right, search in the square.
      final bar =
          tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
      expect(bar.actions.map((a) => a.label), ['Portfolio', 'Withdraw']);
      expect(bar.actions.map((a) => a.trackingId), ['portfolio', 'withdraw']);
      expect(bar.actions.every((a) => a.onTap != null), isTrue);
      expect(find.text('Deposit'), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.text('Ask Sal anything'), findsNothing);
      expect(find.textContaining('available'), findsNothing);
      expect(find.textContaining('Updating'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('${product.name} portfolio screen dock is Deposit and Withdraw',
        (tester) async {
      await _pump(
          tester,
          Column(mainAxisSize: MainAxisSize.min, children: [
            InvestmentActionBar(product: product, onPortfolio: true),
          ]));
      final bar =
          tester.widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
      expect(bar.actions.map((a) => a.label), ['Deposit', 'Withdraw']);
      expect(find.text('Portfolio'), findsNothing);
    });
  }
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
        await tester.pumpAndSettle();
        expect(header(tester).loading, isFalse);
        expect(header(tester).amountText, r'$100.00');
        expect(header(tester).stale, isTrue);
        expect(header(tester).investedText, isNull);
        final figure = tester.widget<RollingNumberText>(find.descendant(
            of: find.byType(PoolBalanceHeader),
            matching: find.byType(RollingNumberText)));
        expect(figure.style.color, AppColorsExtension.light().textSecondary);
        expect(find.text('—'), findsNothing);

        // The next sync brings it back fresh.
        container.read(balances.notifier).state = const InvestmentBalances(
            available: 50, portfolio: 70, total: 120, positions: 70);
        await tester.pumpAndSettle();
        expect(header(tester).amountText, r'$120.00');
        expect(header(tester).stale, isFalse);
      });
    }

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
