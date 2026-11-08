// The Who step's own rules (send_recipient_step.dart, fw50): which inputs
// only bitcoin pays (the input decides the rail), which words name an own
// account (the search's escape hatch, "Move to your Dollars"), and the
// "Another crypto" card's one line ("USDC, ETH and more"; founder, 7
// November 2026), from the coins the sheet behind it lists. And the field
// itself (founder, 8 November 2026: "the search bar should be like the ai
// search bar"): the AI bar's line with Paste, Scan and the clear at its
// right, and the logos of what it takes, only what the policy really leaves
// open.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_routes_model.dart'
    show OrchestraReceiveOption, OrchestraRoutesCatalog;
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/screens/search/components/search_composer.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/send/send_recipient_step.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../../helpers/runtime_policy_fixture.dart';

final _l10n = AppLocalizationsEn();

CoinAssetGroup _coin(String symbol) => CoinAssetGroup(
      key: symbol,
      displayName: symbol,
      displaySymbol: symbol,
      options: [
        OrchestraReceiveOption(
          assetCode: symbol,
          displayName: symbol,
          displaySymbol: symbol,
          chain: 'ethereum',
          chainDisplayName: 'Ethereum',
          decimals: 6,
        ),
      ],
    );

OrchestraReceiveOption _row(String symbol, String chain) =>
    OrchestraReceiveOption(
      assetCode: symbol,
      displayName: symbol,
      displaySymbol: symbol,
      chain: chain,
      chainDisplayName: chain,
      decimals: 6,
    );

/// A send's destinations: stablecoins, altcoins, and what the row never
/// shows (bitcoin itself, the person's own dollars).
List<OrchestraReceiveOption> _rows() => [
      _row('ZEC', 'zcash'),
      _row('BNB', 'bsc'),
      _row('SOL', 'solana'),
      _row('USDT', 'tron'),
      _row('ETH', 'ethereum'),
      _row('USDC', 'base'),
      _row('USDC', 'solana'),
      _row('BTC', 'bitcoin'),
      _row('USD', 'spark'),
    ];

Future<void> _policy(
    {Set<String> blocked = const {},
    Map<String, String> reasons = const {}}) async {
  AffiliateService.debugSessionToken = 'test-session';
  final p = runtimePolicyFixture(blocked: blocked, reasons: reasons);
  RuntimeCapabilitiesService.debugInstance = p;
  await p.refresh();
}

Widget _host(Widget child) => ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SalSpriteCache.debugSetManifest(null);
  });

  tearDown(() {
    SalSpriteCache.debugReset();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  group('the coins under the field', () {
    List<String> keys(List<CoinAssetGroup> groups) =>
        [for (final g in groups) g.key];

    test('the open coins, the best known first, never bitcoin nor the own '
        'dollars', () async {
      await _policy();
      expect(keys(sendAcceptedCoinGroups(_rows(), otherLegAsset: 'BTC')),
          ['USDC', 'ETH', 'USDT', 'SOL', 'BNB', 'ZEC']);
    });

    test('a region block empties the row: no tap here to say why', () async {
      await _policy(
          blocked: {'orchestra.swap'},
          reasons: {'orchestra.swap': 'country_blocked'});
      expect(sendAcceptedCoinGroups(_rows(), otherLegAsset: 'BTC'), isEmpty);
      expect(sendAcceptedCoinGroups(_rows(), otherLegAsset: 'USDB'), isEmpty);
    });

    test('the swap switched off empties it too', () async {
      await _policy(blocked: {'orchestra.swap'});
      expect(sendAcceptedCoinGroups(_rows(), otherLegAsset: 'BTC'), isEmpty);
    });

    test('altcoins blocked: bitcoin reaches the stablecoins only, dollars '
        'answer to the master switch alone', () async {
      await _policy(
          blocked: {'orchestra.swap.altcoins'},
          reasons: {'orchestra.swap.altcoins': 'country_blocked'});
      expect(keys(sendAcceptedCoinGroups(_rows(), otherLegAsset: 'BTC')),
          ['USDC', 'USDT']);
      expect(keys(sendAcceptedCoinGroups(_rows(), otherLegAsset: 'USDB')),
          ['USDC', 'ETH', 'USDT', 'SOL', 'BNB', 'ZEC']);
    });

    List<String> shown(WidgetTester tester) => [
          for (final e in find.byType(AssetIcon).evaluate())
            (e.widget as AssetIcon).assetCode
        ];

    testWidgets('the Dollars Send shows the networks, then Bitcoin and '
        'Lightning; blocked, just those two', (tester) async {
      await tester.runAsync(_policy);
      expect(
          [
            for (final o in sendAcceptedChains(_rows(), otherLegAsset: 'USD'))
              o.chain
          ],
          ['ethereum', 'base', 'solana', 'tron', 'bsc', 'zcash']);
      await tester.pumpWidget(_host(SendAcceptedCoins(
          chains: true,
          otherLegAsset: 'USD',
          rows: (OrchestraRoutesCatalog _, __) => _rows())));
      await tester.pump();
      expect(find.byKey(const ValueKey('send-accepted-chain-ethereum')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('send-accepted-chain-spark')),
          findsNothing);
      expect(find.byKey(const ValueKey('send-accepted-chain-bitcoin')),
          findsNothing);
      expect(shown(tester), ['BTC', 'Lightning']);

      await tester.runAsync(() => _policy(
          blocked: {'orchestra.swap'},
          reasons: {'orchestra.swap': 'country_blocked'}));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(SendAcceptedCoins(
          chains: true,
          otherLegAsset: 'USD',
          rows: (OrchestraRoutesCatalog _, __) => _rows())));
      await tester.pump();
      expect(find.byKey(const ValueKey('send-accepted-chain-ethereum')),
          findsNothing);
      expect(shown(tester), ['BTC', 'Lightning']);
      await tester.runAsync(_policy);
    });

    testWidgets('Bitcoin and Lightning first, then the coins; blocked, just '
        'those two', (tester) async {
      await tester.runAsync(_policy);
      await tester.pumpWidget(_host(SendAcceptedCoins(
          otherLegAsset: 'BTC', rows: (OrchestraRoutesCatalog _, __) => _rows())));
      await tester.pump();
      expect(shown(tester),
          ['BTC', 'Lightning', 'USDC', 'ETH', 'USDT', 'SOL', 'BNB', 'ZEC']);
      expect(find.byKey(const ValueKey('send-accepted-coins-more')),
          findsNothing);

      await tester.runAsync(() => _policy(
          blocked: {'orchestra.swap'},
          reasons: {'orchestra.swap': 'country_blocked'}));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(SendAcceptedCoins(
          otherLegAsset: 'BTC', rows: (OrchestraRoutesCatalog _, __) => _rows())));
      await tester.pump();
      expect(shown(tester), ['BTC', 'Lightning']);
    });

    testWidgets('a cold source pays plain bitcoin: Bitcoin alone',
        (tester) async {
      await tester.runAsync(_policy);
      await tester.pumpWidget(_host(SendAcceptedCoins(
          lightning: false,
          otherLegAsset: 'BTC',
          rows: (OrchestraRoutesCatalog _, __) => const [])));
      await tester.pump();
      expect(shown(tester), ['BTC']);
    });

    testWidgets('past eight logos a quiet +N, on one line at 320 pt',
        (tester) async {
      tester.view.physicalSize = const Size(320, 693);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(_policy);
      final many = [
        ..._rows(),
        for (final s in ['XRP', 'TRX', 'LTC', 'ADA', 'DOT', 'NEAR'])
          _row(s, 'ethereum'),
      ];
      await tester.pumpWidget(_host(SizedBox(
        width: 290,
        child: SendAcceptedCoins(
            otherLegAsset: 'BTC', rows: (OrchestraRoutesCatalog _, __) => many),
      )));
      await tester.pump();
      expect(shown(tester), hasLength(SendAcceptedCoins.maxMarks));
      // 12 coins and the two rails, eight shown.
      expect(find.text('+6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the field', () {
    late TextEditingController controller;
    late List<String> calls;

    setUp(() {
      controller = TextEditingController();
      calls = [];
    });

    tearDown(() => controller.dispose());

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => SendRecipientSearchField(
          controller: controller,
          hintText: 'Name, phone or any crypto address',
          onChanged: (v) => setState(() => calls.add('changed:$v')),
          onPaste: () => calls.add('paste'),
          onScan: () => calls.add('scan'),
          onSubmitted: (v) => calls.add('done:$v'),
        ),
      )));
      await tester.pump();
    }

    TextField field(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField));

    testWidgets('is the AI bar\'s line: its sprite, its text styles, its '
        'hairline, no fill', (tester) async {
      await pump(tester);
      final composer = find.byKey(const ValueKey('send-recipient-search'));
      expect(tester.widget(composer), isA<KuteSearchComposer>());
      expect(tester.getSize(composer).height, KuteSearchComposer.height);
      final sal = tester.widget<SalSprite>(find.byType(SalSprite));
      expect(sal.size, KuteSearchComposer.spriteSize);
      final context = tester.element(composer);
      expect(field(tester).style, KuteSearchComposer.textStyle(context));
      final box = tester.widget<Container>(find
          .descendant(of: composer, matching: find.byType(Container))
          .first);
      expect(box.decoration, KuteSearchComposer.decoration(context));
    });

    testWidgets('takes an address, not prose: Done, nothing rewrites it',
        (tester) async {
      await pump(tester);
      final f = field(tester);
      expect(f.textInputAction, TextInputAction.done);
      expect(f.autocorrect, isFalse);
      expect(f.enableSuggestions, isFalse);
      expect(f.smartDashesType, SmartDashesType.disabled);
      expect(f.smartQuotesType, SmartQuotesType.disabled);
      expect(f.keyboardType, TextInputType.text);
    });

    testWidgets('Paste and Scan while empty, the clear once filled; Done '
        'hands the text on', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('send-field-paste')));
      await tester.tap(find.byKey(const ValueKey('send-field-scan')));
      expect(calls, ['paste', 'scan']);
      expect(find.byKey(const ValueKey('send-field-clear')), findsNothing);
      // Neither took the focus.
      expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
          isFalse);

      calls.clear();
      await tester.enterText(find.byType(TextField), 'bc1qabc');
      await tester.pumpAndSettle();
      expect(calls, ['changed:bc1qabc']);
      expect(find.byKey(const ValueKey('send-field-paste')), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(calls.last, 'done:bc1qabc');

      await tester.tap(find.byKey(const ValueKey('send-field-clear')));
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(calls.last, 'changed:');
      expect(find.byKey(const ValueKey('send-field-paste')), findsOneWidget);
    });

    testWidgets('a long address at a large text size stays in the line',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      controller.text = 'lnbc1500n0qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4qw508d6';
      await pump(tester);
      expect(tester.takeException(), isNull);
      expect(
          tester
              .getSize(find.byKey(const ValueKey('send-recipient-search')))
              .height,
          KuteSearchComposer.height);
    });

    testWidgets('a tap on Sal focuses the line', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(SalSprite));
      await tester.pump();
      expect(field(tester).focusNode!.hasFocus, isTrue);
    });
  });

  group('sendIsBitcoinRail', () {
    test('bitcoin, Spark and Lightning destinations are bitcoin\'s', () {
      for (final text in [
        'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
        'bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.1',
        'lnbc2500u1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu',
        'lightning:lnbc2500u1pvjluezpp5qqqsyqcyq5rqwz',
        'lnurl1dp68gurn8ghj7um9wfmxjcm99e3k7mf0v9cxj0m385ekvcenxc6r2c35xvukxefcv5mkvv34x5ekzd3ev56nyd3hxqurzepexejxxepnxscrvwfnv9nxzcn9xq6xyefhvgcxxcmyxymnserxfq5fns',
        'alice@getalby.com',
        'joana@paykute.com',
      ]) {
        expect(sendIsBitcoinRail(text), isTrue, reason: text);
      }
    });

    test('a coin address, a name, a number or nothing is not', () {
      for (final text in [
        '0x742d35cc6634c0532925a3b844bc454e4438f44e',
        'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        'maria',
        '+351 912 345 678',
        '',
        'two words',
      ]) {
        expect(sendIsBitcoinRail(text), isFalse, reason: text);
      }
    });
  });

  group('sendOwnAccountMatches', () {
    test('a word that starts an account\'s name finds it', () {
      expect(sendOwnAccountMatches(_l10n, 'dollars'), [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(_l10n, 'my dollars'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(_l10n, 'Dol'), [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(_l10n, 'usd'), [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(_l10n, 'bitcoin'), [SendOwnAccount.bitcoin]);
      expect(sendOwnAccountMatches(_l10n, 'my btc'), [SendOwnAccount.bitcoin]);
      expect(sendOwnAccountMatches(_l10n, 'sats'), [SendOwnAccount.bitcoin]);
    });

    test('the localized names count too, accents folded', () {
      expect(sendOwnAccountMatches(l10nForLanguage('pt'), 'meus dolares'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(l10nForLanguage('el'), 'δολάρια'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(l10nForLanguage('bg'), 'долари'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(l10nForLanguage('ja'), 'ドル'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(l10nForLanguage('ja'), 'ビットコイン'),
          [SendOwnAccount.bitcoin]);
    });

    test('an address, a coin ticker, a name or two letters find nothing', () {
      for (final text in [
        '0x742d35cc6634c0532925a3b844bc454e4438f44e',
        'usdc',
        'maria',
        'do',
        '',
        'alice@getalby.com',
      ]) {
        expect(sendOwnAccountMatches(_l10n, text), isEmpty, reason: text);
      }
    });
  });

  group('the Another crypto card', () {
    List<CoinAssetGroup> coins(List<String> symbols) =>
        [for (final s in symbols) _coin(s)];

    test('names the two best known, USDC then ETH, wherever they sit, and '
        'says there are more without a count', () {
      final groups = coins(['USDT', 'SOL', 'ETH', 'BNB', 'USDC', 'XRP']);
      expect(
          anotherCryptoNamedCoins(groups).map((g) => g.displaySymbol),
          ['USDC', 'ETH']);
      expect(anotherCryptoLine(_l10n, groups), 'USDC, ETH and more');
      expect(anotherCryptoLine(_l10n, groups), isNot(contains('+')));
    });

    test('without USDC or ETH, the next best known, then the list\'s own '
        'order', () {
      expect(anotherCryptoLine(_l10n, coins(['BNB', 'USDT', 'XRP'])),
          'USDT, BNB and more');
      expect(anotherCryptoLine(_l10n, coins(['BNB', 'XRP', 'TRX'])),
          'BNB, XRP and more');
    });

    test('only what there is: two coins both named, one alone; bitcoin is '
        'never named but counts as more', () {
      expect(anotherCryptoLine(_l10n, coins(['ETH', 'USDC'])), 'USDC and ETH');
      expect(anotherCryptoLine(_l10n, coins(['USDT'])), 'USDT');
      expect(anotherCryptoLine(_l10n, coins(['BTC', 'USDC'])),
          'USDC and more');
      expect(anotherCryptoLine(_l10n, coins(['BTC', 'USDC', 'ETH'])),
          'USDC, ETH and more');
    });

    test('no coin but bitcoin: no line and no coin to show', () {
      expect(anotherCryptoLine(_l10n, const []), isEmpty);
      expect(anotherCryptoLine(_l10n, coins(['BTC'])), isEmpty);
      expect(anotherCryptoNamedCoins(coins(['BTC'])), isEmpty);
    });

    test('the card: "Another crypto", the line, the named coins\' marks',
        () {
      final card = anotherCryptoCard(_l10n,
          key: const ValueKey('another'),
          groups: coins(['USDT', 'ETH', 'USDC', 'SOL']),
          onTap: () {});
      expect(card.title, 'Another crypto');
      expect(card.subtitle, 'USDC, ETH and more');
      final marks = card.visual as AnotherCryptoMarks;
      expect(marks.coins.map((g) => g.displaySymbol), ['USDC', 'ETH']);
    });

    test('every language says it in one short line', () {
      final groups = coins(['USDC', 'USDT', 'ETH', 'SOL']);
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = l10nForLanguage(locale.languageCode);
        final line = anotherCryptoLine(l10n, groups);
        expect(line, contains('USDC'), reason: locale.languageCode);
        expect(line, contains('ETH'), reason: locale.languageCode);
        expect(line.length, lessThanOrEqualTo(24),
            reason: '${locale.languageCode}: $line');
      }
    });
  });
}
