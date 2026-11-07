// The Sal sheet opened from the bar on a market page (a context screen,
// kute_share_actions.dart): the market preview card, the two action rows
// in one card, "Ask Sal" as a row of chips; no filter pills, no
// "Recommended" label, and the keyboard down until the field is tapped.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show hlFriendlyName;
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/theme/app_theme.dart';

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Advisor extends AdvisorSessionNotifier {
  _Advisor(this.asked);
  final List<String> asked;
  @override
  AdvisorSessionState build() => const AdvisorSessionState();

  @override
  Future<void> ask(String query,
      {AdvisorContext? context,
      String input = 'typed',
      String? template,
      int? chipIndex,
      String? locale}) async {
    asked.add(query);
    state = AdvisorSessionState(turns: [AdvisorTurn(query: query)]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'a market context: preview card, one actions card, no chips, '
      'no pills, no Recommended, keyboard down', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final asked = <String>[];
    final tapped = <String>[];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiEnabledProvider.overrideWith((_) async => true),
        advisorSessionProvider.overrideWith(() => _Advisor(asked)),
        sportsLiveProvider.overrideWith(_Sports.new),
        unifiedSearchResultsProvider
            .overrideWith((_) async => UnifiedSearchResults.empty),
        globalMarketResultsProvider
            .overrideWith((_) => const AsyncValue.data([])),
        globalHyperliquidResultsProvider
            .overrideWith((_) => const AsyncValue.data([])),
        hyperliquidAllMarketsProvider.overrideWith((_) => []),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showKuteSearch(
                  context,
                  initialCategory: SearchCategory.predictions,
                  source: 'predictions',
                  barContext: KuteMarketBarContext(
                    label: 'Share with your friends',
                    preview: const KuteBarPreview(
                        title: 'Gemini Carbon', line: 'Yes 62%'),
                    prompts: const ['Explain the odds', "What's the risk?"],
                    category: SearchCategory.predictions,
                    actions: [
                      KuteMarketBarAction(
                        label: 'Share the market',
                        sublabel: 'A link they can open, with your code',
                        icon: Icons.ios_share_rounded,
                        onTap: (_) => tapped.add('share'),
                      ),
                      KuteMarketBarAction(
                        label: 'Send this prediction',
                        sublabel: 'They get your pick, ready to place',
                        salClip: 'share',
                        onTap: (_) => tapped.add('send'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();

    // The designed top: the preview, then the two send cards side by
    // side (founder, 1 November 2026), each saying what it sends at its
    // foot: the market's name on the link card, the pick on the other.
    expect(find.byKey(const ValueKey('context-preview-card')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('context-preview-card')),
            matching: find.text('Gemini Carbon')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('context-actions-card')), findsOneWidget);
    expect(find.text('Share the market'), findsOneWidget);
    expect(find.text('Send this prediction'), findsOneWidget);
    final link =
        find.byKey(const ValueKey('context-action-card-Share the market'));
    final pick =
        find.byKey(const ValueKey('context-action-card-Send this prediction'));
    expect(
        find.descendant(of: link, matching: find.text('Gemini Carbon')),
        findsOneWidget);
    expect(find.descendant(of: pick, matching: find.text('Yes 62%')),
        findsOneWidget);
    // Equal widths, 12 apart, on one row, equally tall, ~170 at least.
    final l = tester.getRect(link);
    final r = tester.getRect(pick);
    expect(l.top, moreOrLessEquals(r.top));
    expect(l.height, moreOrLessEquals(r.height));
    expect(l.width, moreOrLessEquals(r.width, epsilon: 0.5));
    expect(r.left - l.right, moreOrLessEquals(12 * 390 / 430, epsilon: 0.5));
    expect(l.height, greaterThanOrEqualTo(170));
    // No Ask Sal chips (founder, 31 October 2026).
    expect(find.text('Ask Sal'), findsNothing);
    expect(find.text('Explain the odds'), findsNothing);
    // Not search scoping, not the old label, no dollars wording.
    expect(find.byKey(const ValueKey('search-scope-chip')), findsNothing);
    expect(find.text('Recommended'), findsNothing);
    expect(find.textContaining('dollars'), findsNothing);
    // The keyboard stays down until the field is tapped.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an action row runs its action and closes the sheet',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tapped = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiEnabledProvider.overrideWith((_) async => false),
        sportsLiveProvider.overrideWith(_Sports.new),
        unifiedSearchResultsProvider
            .overrideWith((_) async => UnifiedSearchResults.empty),
        globalMarketResultsProvider
            .overrideWith((_) => const AsyncValue.data([])),
        globalHyperliquidResultsProvider
            .overrideWith((_) => const AsyncValue.data([])),
        hyperliquidAllMarketsProvider.overrideWith((_) => []),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showKuteSearch(
                  context,
                  source: 'trading',
                  barContext: KuteMarketBarContext(
                    label: 'Share with your friends',
                    preview: const KuteBarPreview(title: 'BTC', line: 'Long'),
                    actions: [
                      KuteMarketBarAction(
                        label: 'Send this investment',
                        salClip: 'share',
                        onTap: (_) => tapped.add('send'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    // Sal off: no chips, still the card.
    expect(find.text('Ask Sal'), findsNothing);
    await tester.tap(find.text('Send this investment'));
    await tester.pumpAndSettle();
    expect(tapped, ['send']);
    expect(find.text('Send this investment'), findsNothing);
    // The dog glyph's delayed glance exits after unmount.
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an Investing builder-dex market (Nasdaq 100, xyz:XYZ100): the '
      'preview and the link card show its display name with the ticker '
      'under it, and its logo as the page header draws it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late KuteMarketBarContext bar;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        // As the market page builds it (hyperliquid/market_detail_sheet).
        bar = marketBarContext(
          context,
          title: hlFriendlyName('XYZ100') ?? 'XYZ100',
          ticker: 'XYZ100',
          wireCoin: 'xyz:XYZ100',
          coinCategory: 'indices',
          venue: kMarketLinkInvesting,
          slug: 'XYZ100',
          price: '25,100.0',
          position: false,
          category: SearchCategory.perpetuals,
          searchHint: null,
          source: 'trading',
        ) as KuteMarketBarContext;
        return const SizedBox();
      }),
    ));
    await _pumpSheet(tester, bar);
    final card = find.byKey(const ValueKey('context-preview-card'));
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('context-preview-title')))
            .data,
        'Nasdaq 100');
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('context-preview-subtitle')))
            .data,
        'XYZ100');
    // The header's logo: HlCoinIcon with the wire coin and category, never
    // a letter tile of the raw ticker.
    final icon = tester.widget<HlCoinIcon>(
        find.descendant(of: card, matching: find.byType(HlCoinIcon)));
    expect(icon.coin, 'XYZ100');
    expect(icon.wireCoin, 'xyz:XYZ100');
    expect(icon.category, 'indices');
    // The link card names it the same way and wears the same logo.
    final linkCard = find.byKey(
        ValueKey('context-action-card-${bar.actions.first.label}'));
    expect(find.descendant(of: linkCard, matching: find.text('Nasdaq 100')),
        findsOneWidget);
    expect(find.descendant(of: linkCard, matching: find.byType(HlCoinIcon)),
        findsOneWidget);
    // Closed, as a person would: the sheet's own state goes with it.
    await tester.tap(find.byKey(
        ValueKey('context-action-card-${bar.actions.last.label}')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a long title and a long pick never overflow the preview row: the '
      'pick moves under the title, whole, instead of being cut',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpSheet(
      tester,
      KuteMarketBarContext(
        label: 'Send to a friend',
        preview: const KuteBarPreview(
          title: 'League of Legends World Championship Grand Final: '
              'Gen.G Esports vs Bilibili Gaming, best of five',
          line: 'Gen.G Esports Academy Challengers 47%',
        ),
        actions: [
          KuteMarketBarAction(
              label: 'Send this prediction', salClip: 'share', onTap: (_) {}),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    _expectPickBelow(tester, 'Gen.G Esports Academy Challengers 47%');
    await _closeSheet(tester);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [(390.0, 1.0), (375.0, 1.3)]) {
    Future<void> pumpAt(WidgetTester tester, String line) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpSheet(
        tester,
        KuteMarketBarContext(
          label: 'Send to a friend',
          preview: KuteBarPreview(title: 'Browns vs. Steelers', line: line),
          actions: [
            KuteMarketBarAction(
                label: 'Send this prediction',
                salClip: 'share',
                onTap: (_) {}),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    }

    testWidgets(
        'the preview row at $width pt, text x$scale: a long pick ("Spread: '
        'Steelers -3.5") moves under the title in textSecondary, whole, '
        'nothing overflows', (tester) async {
      await pumpAt(tester, 'Spread: Steelers -3.5');
      _expectPickBelow(tester, 'Spread: Steelers -3.5');
      final pick = tester.widget<Text>(
          find.byKey(const ValueKey('context-preview-figure')));
      expect(pick.style?.color, AppColorsExtension.light().textSecondary);
      await _closeSheet(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the preview row at $width pt, text x$scale: a short pick stays at '
        'the right, on the title\'s row, within 40%', (tester) async {
      // Short in the test font too (a glyph is 1 em wide there).
      await pumpAt(tester, '62%');
      final card =
          tester.getRect(find.byKey(const ValueKey('context-preview-card')));
      final title =
          tester.getRect(find.byKey(const ValueKey('context-preview-title')));
      final figure =
          tester.getRect(find.byKey(const ValueKey('context-preview-figure')));
      expect(figure.right, moreOrLessEquals(card.right, epsilon: 0.5));
      expect(figure.left, greaterThan(title.left));
      expect(figure.top, lessThan(title.bottom));
      expect(figure.width,
          lessThanOrEqualTo(card.width * kContextPreviewPickShare + 0.5));
      expect(
          tester
              .widget<Text>(find.descendant(
                  of: find.byKey(const ValueKey('context-preview-figure')),
                  matching: find.byType(Text)))
              .data,
          '62%');
      await _closeSheet(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'an event page (Michigan Senate Election Winner, several outcomes): '
      'the sheet holds one full-width "Send the market" card, no "Send '
      'this prediction", and the bar\'s line says what that card does',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _loadInter(tester);
    final bar = await _marketBar(tester, single: false);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(bar.actions.map((a) => a.label), [l10n.shareTheMarket]);
    expect(bar.sublabel, l10n.shareTheMarketSub);
    await _pumpSheet(tester, bar);
    expect(find.text(l10n.shareTheMarket), findsOneWidget);
    expect(find.text(l10n.sendAPrediction), findsNothing);
    final grid =
        tester.getRect(find.byKey(const ValueKey('context-actions-card')));
    final card =
        find.byKey(ValueKey('context-action-card-${l10n.shareTheMarket}'));
    expect(tester.getRect(card).width, moreOrLessEquals(grid.width));
    // The market's whole name at the foot.
    final sent =
        find.byKey(ValueKey('context-action-sent-${l10n.shareTheMarket}'));
    expect(tester.widget<Text>(sent).data, 'Michigan Senate Election Winner');
    expect(_lines(tester, sent).$2, isFalse);
    await _closeSheet(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a single prediction page (a Yes/No market, or an outcome drilled '
      'into): the same one "Send the market" card; a prediction is sent '
      'from its slip, never picked here (founder, 5 November 2026)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _loadInter(tester);
    final bar = await _marketBar(tester, single: true);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(bar.actions.map((a) => a.label), [l10n.shareTheMarket]);
    expect(bar.sublabel, l10n.shareTheMarketSub);
    // The page's buttons send the market at once.
    expect(bar.directAction, isNotNull);
    await _pumpSheet(tester, bar);
    expect(find.text(l10n.shareTheMarket), findsOneWidget);
    expect(find.text(l10n.sendAPrediction), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('context-preview-figure')),
            matching: find.text(l10n.shareMarketChance('64'))),
        findsOneWidget);
    await _closeSheet(tester);
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [Locale('en'), Locale('de')]) {
    testWidgets(
        'two cards side by side (${locale.languageCode}): a long market '
        'name at the foot wraps to two lines, never one line and an '
        'ellipsis; the titles and lines under them fit whole',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _loadInter(tester);
      final l10n = lookupAppLocalizations(locale);
      final bar = KuteMarketBarContext(
        label: l10n.barShareWithFriends,
        preview: const KuteBarPreview(
            title: 'Michigan Senate Election Winner',
            line: 'Abdul El-Sayed (D) 64%'),
        actions: [
          KuteMarketBarAction(
              label: l10n.shareTheMarket,
              sublabel: l10n.shareTheMarketSub,
              icon: Icons.ios_share_rounded,
              onTap: (_) {}),
          KuteMarketBarAction(
              label: l10n.sendAPrediction,
              sublabel: l10n.sendAPredictionSub,
              salClip: 'share',
              onTap: (_) {}),
        ],
      );
      await _pumpSheet(tester, bar, locale: locale);
      final sent =
          find.byKey(ValueKey('context-action-sent-${l10n.shareTheMarket}'));
      expect(tester.widget<Text>(sent).maxLines, 2);
      final (lines, cut) = _lines(tester, sent);
      expect(lines, 2, reason: 'the name takes its second line');
      expect(cut, isFalse, reason: 'and is whole');
      for (final a in bar.actions) {
        final card = find.byKey(ValueKey('context-action-card-${a.label}'));
        for (final text in [a.label, a.sublabel!]) {
          final t = find.descendant(of: card, matching: find.text(text));
          expect(_lines(tester, t).$2, isFalse, reason: '"$text" is whole');
        }
      }
      await _closeSheet(tester);
      expect(tester.takeException(), isNull);
    });
  }
}

/// The app's Inter, so a test measures lines as the phone does.
Future<void> _loadInter(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    });

/// The Michigan Senate event page's bar ([single] false: an event) or a
/// single Yes/No market's, as market_detail_sheet builds it.
Future<KuteMarketBarContext> _marketBar(WidgetTester tester,
    {required bool single}) async {
  late KuteMarketBarContext bar;
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (context) {
      bar = marketBarContext(
        context,
        title: single
            ? 'Will Abdul El-Sayed win the Michigan Senate election?'
            : 'Michigan Senate Election Winner',
        venue: kMarketLinkPredictions,
        slug: 'michigan-senate-election-winner',
        chance: single ? 64 : null,
        position: false,
        category: SearchCategory.predictions,
        searchHint: null,
        source: 'predictions',
      ) as KuteMarketBarContext;
      return const SizedBox();
    }),
  ));
  return bar;
}

/// The number of lines [finder]'s Text laid out in, and whether it was cut.
(int, bool) _lines(WidgetTester tester, Finder finder) {
  final p = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)).first);
  final length = p.text.toPlainText().length;
  final tops = {
    for (final b in p.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: length)))
      b.top.round(),
  };
  return (tops.length, p.didExceedMaxLines);
}

/// Closes the open sheet, as a person would, so the next test can open
/// one (the search opens once at a time).
Future<void> _closeSheet(WidgetTester tester) async {
  Navigator.of(
          tester.element(find.byKey(const ValueKey('context-preview-card'))))
      .pop();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 6));
}

/// The pick sits under the title, left-aligned with it, whole.
void _expectPickBelow(WidgetTester tester, String pick) {
  final title =
      tester.getRect(find.byKey(const ValueKey('context-preview-title')));
  final figureFinder = find.byKey(const ValueKey('context-preview-figure'));
  final figure = tester.getRect(figureFinder);
  expect(figure.top, greaterThanOrEqualTo(title.bottom - 0.5));
  expect(figure.left, moreOrLessEquals(title.left, epsilon: 0.5));
  expect(tester.widget<Text>(figureFinder).data, pick);
  final card =
      tester.getRect(find.byKey(const ValueKey('context-preview-card')));
  expect(figure.right, lessThanOrEqualTo(card.right + 0.5));
}

/// Opens the Sal sheet with [barContext] (Sal off).
Future<void> _pumpSheet(WidgetTester tester, KuteMarketBarContext barContext,
    {Locale? locale}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      aiEnabledProvider.overrideWith((_) async => false),
      sportsLiveProvider.overrideWith(_Sports.new),
      unifiedSearchResultsProvider
          .overrideWith((_) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
      globalHyperliquidResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
      hyperliquidAllMarketsProvider.overrideWith((_) => []),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKuteSearch(context,
                  source: 'predictions', barContext: barContext),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open search'));
  await tester.pumpAndSettle();
}
