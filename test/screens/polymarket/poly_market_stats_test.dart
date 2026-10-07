// A Predictions market's stats and its Rules and resolution sheet: only
// the pairs with data, written on the sheet's detail rows under their own
// heading, above the rules text and how the market resolves.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/poly_market_stats.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/theme/app_theme.dart';

String _money(double v) => '\$${v.round()}';

Future<AppLocalizations> _l10n([String code = 'en']) =>
    AppLocalizations.delegate.load(Locale(code));

Future<void> _pump(WidgetTester tester, Widget child,
    {bool dark = false}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
        fontFamily: 'Inter',
        extensions: [
          dark ? AppColorsExtension.dark() : AppColorsExtension.light()
        ],
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [child]),
        ),
      ),
    ),
  ));
  await tester.pump();
}

PolymarketEvent _event({String? description, DateTime? endDate}) =>
    PolymarketEvent(
      id: 'not-a-number',
      slug: 'will-it-happen',
      title: 'Will it happen?',
      volume: 3100000,
      volume24hr: 307800,
      liquidity: 17900000,
      category: 'politics',
      conditionId: 'cond',
      description: description,
      endDate: endDate,
      outcomes: const [
        PolymarketOutcome(name: 'Yes', price: 0.45, tokenId: 'yes'),
        PolymarketOutcome(name: 'No', price: 0.55, tokenId: 'no'),
      ],
    );

void main() {
  // The app loads these with its Material localizations.
  setUpAll(initializeDateFormatting);

  group('pairs', () {
    test('all four, in order, with the app money format and a short date',
        () async {
      final stats = polyMarketStats(
        await _l10n(),
        volume24hr: 307800,
        volume: 3100000,
        liquidity: 17900000,
        endDate: DateTime(2027, 4, 5, 12),
        ended: false,
        money: _money,
        locale: 'en',
      );
      expect([for (final s in stats) s.label],
          ['24h Volume', 'Total volume', 'Liquidity', 'Ends']);
      expect([for (final s in stats) s.value],
          ['\$307800', '\$3100000', '\$17900000', 'Apr 5, 2027']);
    });

    test('a figure Polymarket has not given is left out', () async {
      final stats = polyMarketStats(
        await _l10n(),
        volume24hr: 0,
        volume: 5200,
        liquidity: 0,
        endDate: null,
        ended: false,
        money: _money,
      );
      expect([for (final s in stats) s.label], ['Total volume']);
      expect(
          polyMarketStats(
            await _l10n(),
            volume24hr: 0,
            volume: 0,
            liquidity: 0,
            endDate: null,
            ended: false,
            money: _money,
          ),
          isEmpty);
    });

    test('a resolved market reads "Ended" with its date', () async {
      final stats = polyMarketStats(
        await _l10n(),
        volume24hr: 0,
        volume: 10,
        liquidity: 0,
        endDate: DateTime(2026, 1, 2, 12),
        ended: true,
        money: _money,
        locale: 'en',
      );
      expect(stats.last.label, 'Ended');
      expect(stats.last.value, 'Jan 2, 2026');
    });

    test('Portuguese labels', () async {
      final l10n = await _l10n('pt');
      expect(l10n.polyStatsTitle, 'Estatísticas');
      expect(l10n.polyRulesAndResolution, 'Regras e resolução');
      final stats = polyMarketStats(
        l10n,
        volume24hr: 1,
        volume: 1,
        liquidity: 1,
        endDate: DateTime(2027, 4, 5, 12),
        ended: false,
        money: _money,
      );
      expect([for (final s in stats) s.label],
          ['Volume 24h', 'Volume total', 'Liquidez', 'Termina']);
    });
  });

  group('on the rules sheet', () {
    const stats = [
      PolyStat('24h Volume', '\$307.8K'),
      PolyStat('Total volume', '\$3.1M'),
      PolyStat('Liquidity', '\$17.9M'),
    ];

    testWidgets('the stats lead the sheet on its own rows, under "Stats"',
        (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPolyRulesSheet(
              context,
              _event(
                description: 'Resolves to Yes if it happens by the date.',
                endDate: DateTime(2027, 4, 5, 12),
              ),
              stats: stats,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Stats'), findsOneWidget);
      // Three stat rows plus the four resolution rows, all the same row.
      expect(find.byType(SheetDetailRow), findsNWidgets(7));
      for (final stat in stats) {
        final row = find.ancestor(
            of: find.text(stat.label), matching: find.byType(SheetDetailRow));
        expect(row, findsOneWidget, reason: stat.label);
        expect(find.descendant(of: row, matching: find.text(stat.value)),
            findsOneWidget);
      }
      // Stats first, then the rules text, then how it resolves.
      final statsY = tester.getTopLeft(find.text('Stats')).dy;
      final aboutY = tester.getTopLeft(find.text('About')).dy;
      expect(
          tester.getTopLeft(find.text('24h Volume')).dy, greaterThan(statsY));
      expect(aboutY, greaterThan(tester.getTopLeft(find.text('Liquidity')).dy));
      expect(tester.getTopLeft(find.text('Market closes')).dy,
          greaterThan(aboutY));
      expect(find.text('Apr 5, 2027'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no stats, no heading', (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPolyRulesSheet(context, _event()),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Stats'), findsNothing);
      expect(find.byType(SheetDetailRow), findsNWidgets(4));
    });
  });

  group('rules and resolution', () {
    testWidgets('the row opens the sheet', (tester) async {
      var opened = 0;
      await _pump(tester, PolyRulesRow(onTap: () => opened++));
      expect(find.text('Rules and resolution'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Rules and resolution'));
      expect(opened, 1);
    });

    testWidgets('the sheet holds the rules text and how the market resolves',
        (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPolyRulesSheet(
              context,
              _event(
                description: 'Resolves to Yes if it happens by the date.',
                endDate: DateTime(2027, 4, 5, 12),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Rules and resolution'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Resolves to Yes if it happens by the date.'),
          findsOneWidget);
      expect(find.text('Resolution'), findsNWidgets(2));
      expect(find.byType(SheetDetailRow), findsNWidgets(4));
      expect(find.text('Market closes'), findsOneWidget);
      expect(find.text('Apr 5, 2027'), findsOneWidget);
      expect(find.text('Winners paid \$1.00 per share'), findsOneWidget);
    });

    testWidgets('a market with no rules text and no date still reads',
        (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPolyRulesSheet(context, _event()),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('About'), findsNothing);
      expect(find.text('Date TBD'), findsOneWidget);
    });
  });
}
