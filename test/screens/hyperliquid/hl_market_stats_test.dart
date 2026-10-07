// The Stats block of an Investing market: which pairs a perp and a spot
// token show, what is left out when the venue has not given it, and the
// two-column layout.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_stats.dart';
import 'package:kute/theme/app_theme.dart';

HlMarket _market({
  HlMarketKind kind = HlMarketKind.perp,
  int maxLeverage = 40,
  double markPx = 85971,
  double dayNtlVlm = 730314331,
  double? funding = 0.0000125,
  double? openInterest = 38031.32,
}) =>
    HlMarket(
      coin: 'BTC',
      wireCoin: kind == HlMarketKind.spot ? '@142' : 'BTC',
      assetId: 0,
      kind: kind,
      szDecimals: 5,
      maxLeverage: maxLeverage,
      onlyIsolated: false,
      markPx: markPx,
      midPx: markPx,
      prevDayPx: 84661,
      dayNtlVlm: dayNtlVlm,
      funding: funding,
      openInterest: openInterest,
    );

Future<AppLocalizations> _pump(WidgetTester tester, List<HlStat> stats,
    {bool dark = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(
        fontFamily: 'Inter',
        extensions: [
          dark ? AppColorsExtension.dark() : AppColorsExtension.light()
        ],
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(0.5)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: HlStatsSection(title: 'Stats', stats: stats),
        ),
      ),
    ),
  ));
  await tester.pump();
  return AppLocalizations.of(tester.element(find.byType(Scaffold)));
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  List<(String, String)> pairs(HlMarket m) =>
      [for (final s in hlMarketStats(l10n, m)) (s.label, s.value)];

  test('a perp: volume, open interest, funding, leverage, mark', () {
    expect(pairs(_market()), [
      ('24h Volume', '\$730.3M'),
      ('Open interest', '\$3.3B'),
      ('Funding', '+0.0013%'),
      ('Maximum leverage', '40×'),
      ('Mark', '\$85,971'),
    ]);
  });

  test('a spot token: volume and mark, nothing a perp alone has', () {
    final spot = _market(
        kind: HlMarketKind.spot,
        maxLeverage: 1,
        markPx: 335.61,
        dayNtlVlm: 0,
        funding: null,
        openInterest: null);
    // No trade in a day is a fact, so the volume still shows.
    expect(pairs(spot), [('24h Volume', '\$0'), ('Mark', '\$335.61')]);
    // A spot row never carries perp numbers, even if the model had them.
    final odd = _market(kind: HlMarketKind.spot, maxLeverage: 1);
    expect(pairs(odd).map((p) => p.$1), ['24h Volume', 'Mark']);
  });

  test('what the venue has not given is left out, not shown as zero', () {
    final bare = _market(
        funding: null, openInterest: null, maxLeverage: 1, markPx: 0);
    expect(pairs(bare), [('24h Volume', '\$730.3M')]);
    expect(formatHlFundingRate(-0.0001), '-0.0100%');
    expect(formatHlFundingRate(0), '+0.0000%');
  });

  testWidgets('two columns; an odd count leaves the last cell empty',
      (tester) async {
    final l = await _pump(tester, const [
      HlStat('24h Volume', '\$730.3M'),
      HlStat('Open interest', '\$3.3B'),
      HlStat('Funding', '+0.0013%'),
    ]);
    expect(l.investingStats, 'Stats');
    expect(find.text('Stats'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Row one: two cells side by side, the second right of the first.
    final volume = tester.getTopLeft(find.text('24h Volume'));
    final oi = tester.getTopLeft(find.text('Open interest'));
    final funding = tester.getTopLeft(find.text('Funding'));
    expect(oi.dy, volume.dy);
    expect(oi.dx, greaterThan(volume.dx + 100));
    // Row two starts under row one, in the first column, alone.
    expect(funding.dx, volume.dx);
    expect(funding.dy, greaterThan(volume.dy));
    // Each value sits right of its label, at its column's right edge.
    final value = tester.getTopRight(find.text('\$730.3M'));
    expect(value.dx, lessThan(oi.dx));
    expect(value.dx, greaterThan(volume.dx + 100));
    // The two columns are the same width.
    final right = tester.getTopRight(find.text('\$3.3B')).dx;
    expect(right - oi.dx, closeTo(value.dx - volume.dx, 0.5));
  });

  testWidgets('no pairs, no section; dark mode draws the same block',
      (tester) async {
    await _pump(tester, const []);
    expect(find.text('Stats'), findsNothing);

    await _pump(tester, const [HlStat('Mark', '\$85,971')], dark: true);
    expect(find.text('Stats'), findsOneWidget);
    expect(find.text('\$85,971'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
