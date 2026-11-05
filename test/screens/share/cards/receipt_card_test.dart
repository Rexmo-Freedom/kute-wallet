// A transaction receipt's own share card (cards/receipt_card.dart; founder,
// 5 November 2026: "All these transactions, next to View on the
// blockchain, should have the share and a special share card"): one card
// per kind of receipt in the family's frame, its colour, Sal's pose, the
// caps line and the edgy lines by kind; every kind and every line in its
// pool fits the card in English, German and Japanese; no figure is made
// up and no identifier is drawn. The PNGs are written only when asked:
//
//   RECEIPT_CARD_FRAMES=<dir> flutter test test/screens/share/cards/receipt_card_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/cards/receipt_card.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_cards.dart';
import 'package:kute/theme/app_theme.dart';

import '../share_test_harness.dart';
import 'share_card_fixtures.dart';
import 'share_card_test_fonts.dart';

final _en = AppLocalizationsEn();

const _market = 'Will Bitcoin close above \$150,000 on December 31, 2026?';

/// One card of every kind, with the figures a real receipt carries.
final Map<String, ReceiptCardData> receiptCards = {
  'sent_bitcoin': const ReceiptCardData(
      type: ReceiptCardKind.sent,
      asset: ReceiptCardAsset.bitcoin,
      amount: r'$9.40',
      bitcoin: '₿12,000',
      referralCode: kShareTestCode),
  'received_bitcoin': const ReceiptCardData(
      type: ReceiptCardKind.received,
      asset: ReceiptCardAsset.bitcoin,
      amount: r'$145.50',
      bitcoin: '₿150,000',
      referralCode: kShareTestCode),
  'incoming_bitcoin': const ReceiptCardData(
      type: ReceiptCardKind.incoming,
      asset: ReceiptCardAsset.bitcoin,
      amount: r'$48.50',
      bitcoin: '₿50,000',
      referralCode: kShareTestCode),
  'sent_dollars': const ReceiptCardData(
      type: ReceiptCardKind.sent,
      asset: ReceiptCardAsset.dollars,
      amount: r'$25.00',
      referralCode: kShareTestCode),
  'received_dollars': const ReceiptCardData(
      type: ReceiptCardKind.received,
      asset: ReceiptCardAsset.dollars,
      amount: r'$25.00',
      referralCode: kShareTestCode),
  'moved_to_bitcoin': const ReceiptCardData(
      type: ReceiptCardKind.moved,
      asset: ReceiptCardAsset.bitcoin,
      amount: r'$50.00',
      bitcoin: '₿51,500',
      from: 'Dollars',
      to: 'Bitcoin',
      referralCode: kShareTestCode),
  'moved_to_predictions': const ReceiptCardData(
      type: ReceiptCardKind.moved,
      asset: ReceiptCardAsset.predictions,
      amount: r'$20.00',
      from: 'Your wallet',
      to: 'Predictions',
      referralCode: kShareTestCode),
  'bought_bitcoin': const ReceiptCardData(
      type: ReceiptCardKind.bought,
      asset: ReceiptCardAsset.bitcoin,
      amount: '€50.00',
      bitcoin: '₿60,000',
      what: 'Bitcoin',
      referralCode: kShareTestCode),
  'sold_bitcoin': const ReceiptCardData(
      type: ReceiptCardKind.sold,
      asset: ReceiptCardAsset.bitcoin,
      amount: r'$97.00',
      bitcoin: '₿100,000',
      what: 'Bitcoin',
      referralCode: kShareTestCode),
  'predicted': const ReceiptCardData(
      type: ReceiptCardKind.predicted,
      asset: ReceiptCardAsset.predictions,
      amount: r'$10.00',
      title: _market,
      side: 'Yes',
      chance: 0.41,
      link: 'https://backend.kutewallet.com/m/predictions/btc-150k',
      referralCode: kShareTestCode),
  'predicted_named': const ReceiptCardData(
      type: ReceiptCardKind.predicted,
      asset: ReceiptCardAsset.predictions,
      amount: r'$10.00',
      title: 'LoL Worlds 2026 Final: Gen.G vs T1',
      side: 'Gen.G',
      chance: 0.62,
      referralCode: kShareTestCode),
  'cashed_out_up': const ReceiptCardData(
      type: ReceiptCardKind.cashedOut,
      asset: ReceiptCardAsset.predictions,
      amount: r'$14.20',
      result: r'+$4.20',
      pnl: 4.2,
      title: _market,
      side: 'No',
      referralCode: kShareTestCode),
  'cashed_out_down': const ReceiptCardData(
      type: ReceiptCardKind.cashedOut,
      asset: ReceiptCardAsset.predictions,
      amount: r'$4.37',
      result: r'−$0.09',
      pnl: -0.09,
      title: _market,
      side: 'No',
      referralCode: kShareTestCode),
  'lost': const ReceiptCardData(
      type: ReceiptCardKind.lost,
      asset: ReceiptCardAsset.predictions,
      amount: r'$10.00',
      result: r'−$10.00',
      pnl: -10,
      title: _market,
      side: 'Yes',
      referralCode: kShareTestCode),
  'paid_out': const ReceiptCardData(
      type: ReceiptCardKind.paidOut,
      asset: ReceiptCardAsset.predictions,
      amount: r'$30.00',
      result: r'+$30.00',
      pnl: 30,
      title: _market,
      side: 'Yes',
      referralCode: kShareTestCode),
  'opened_long': const ReceiptCardData(
      type: ReceiptCardKind.opened,
      asset: ReceiptCardAsset.investing,
      amount: r'$605.25',
      title: 'Tesla',
      ticker: 'TSLA',
      coin: 'TSLA',
      side: 'long',
      price: r'$242.10',
      size: '2.5 TSLA',
      referralCode: kShareTestCode),
  'closed_short_up': const ReceiptCardData(
      type: ReceiptCardKind.closed,
      asset: ReceiptCardAsset.investing,
      amount: r'$71.09',
      result: r'+$3.12',
      pnl: 3.12,
      title: 'OpenAI',
      ticker: 'OAI',
      coin: 'xyz:OAI',
      side: 'short',
      price: r'$142.18',
      size: '0.5 OAI',
      referralCode: kShareTestCode),
  'closed_long_down': const ReceiptCardData(
      type: ReceiptCardKind.closed,
      asset: ReceiptCardAsset.investing,
      amount: r'$71.09',
      result: r'−$0.03',
      pnl: -0.03,
      title: 'OpenAI',
      ticker: 'OAI',
      coin: 'xyz:OAI',
      side: 'long',
      price: r'$142.18',
      size: '0.5 OAI',
      referralCode: kShareTestCode),
  'spot_bought': const ReceiptCardData(
      type: ReceiptCardKind.opened,
      asset: ReceiptCardAsset.investing,
      amount: r'$120.00',
      title: 'Hyperliquid',
      ticker: 'HYPE',
      coin: 'HYPE',
      spot: true,
      price: r'$40.00',
      size: '3 HYPE',
      referralCode: kShareTestCode),
};

void main() {
  late ShareTestEnv env;
  setUp(() => env = setUpShareTest());
  tearDown(tearDownShareTest);

  Future<void> pumpCard(WidgetTester tester, ShareCardData data,
      {Locale locale = const Locale('en'), int seed = 0}) async {
    await tester.runAsync(loadShareCardFonts);
    await pumpShareWidget(
        tester,
        env,
        Builder(
            builder: (context) => Localizations.override(
                  context: context,
                  locale: locale,
                  child: Align(
                      alignment: Alignment.topLeft,
                      child: ShareCard(data: data, lineSeed: seed)),
                )));
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  Color background(WidgetTester tester) => (tester
          .widget<DecoratedBox>(find.byKey(const ValueKey('share-card-bg')))
          .decoration as BoxDecoration)
      .color!;

  group('copy', () {
    test('the caps line by kind', () {
      String caps(String k) => receiptCardTopLine(_en, receiptCards[k]!);
      expect(caps('sent_bitcoin'), 'Sent');
      expect(caps('received_dollars'), 'Received');
      expect(caps('incoming_bitcoin'), 'On its way');
      expect(caps('moved_to_bitcoin'), 'Moved');
      expect(caps('bought_bitcoin'), 'Bought · Bitcoin');
      expect(caps('sold_bitcoin'), 'Sold · Bitcoin');
      expect(caps('predicted'), "I'm on Yes");
      expect(caps('predicted_named'), "I'm on Gen.G");
      expect(caps('cashed_out_up'), 'Cashed out');
      expect(caps('lost'), 'Not this time');
      expect(caps('paid_out'), 'Paid out');
      expect(caps('opened_long'), 'Opened position · Long');
      expect(caps('closed_short_up'), 'Closed position · Short');
      expect(caps('spot_bought'), 'Bought');
    });

    test(
        'the edgy lines: deadpan by kind, a result by its sign, never '
        '"bet", never a promise', () {
      List<String> edges(String k) => receiptCardEdges(_en, receiptCards[k]!);
      expect(edges('sent_bitcoin'),
          ['No bank was harmed in this payment.', 'Sent. Next.']);
      expect(edges('received_dollars'),
          ['Landed. No forms were filled.', 'Consider this a flex.']);
      expect(edges('incoming_bitcoin'), ['On its way. Patience is a feature.']);
      expect(edges('moved_to_bitcoin'), ['Same money. Better spot.']);
      expect(edges('bought_bitcoin'), ['Stacked a little more.']);
      expect(edges('predicted'), [
        'Locked in. Now we wait.',
        'My call. On the record.',
        "41% says I'm early, not wrong.",
      ]);
      // The favourite is not "early".
      expect(edges('predicted_named'),
          ['Locked in. Now we wait.', 'My call. On the record.']);
      expect(edges('cashed_out_up'), ['Took the win and left.']);
      expect(edges('cashed_out_down'), ['Cut it. Moved on.']);
      expect(edges('lost'),
          ['Wrong today. Back tomorrow.', 'Lesson paid in full.']);
      expect(edges('paid_out'), ['Called it. Collected it.']);
      expect(edges('closed_long_down'), ['Cut it. Moved on.']);
      for (final d in receiptCards.values) {
        for (final l in receiptCardEdges(_en, d)) {
          expect(RegExp(r'\bbet(s|ting)?\b', caseSensitive: false).hasMatch(l),
              isFalse,
              reason: l);
          expect(l.toLowerCase(), isNot(contains('guarantee')), reason: l);
        }
      }
    });

    test('no headline on the message: the receipt\'s own text', () {
      for (final d in receiptCards.values) {
        expect(shareCardHeadline(_en, d), isNull);
        expect(d.kind, startsWith('receipt_'));
      }
      expect(receiptCards['cashed_out_up']!.kind, 'receipt_cashed_out');
      expect(receiptCards['paid_out']!.kind, 'receipt_paid_out');
    });
  });

  group('colour and pose', () {
    test(
        'bitcoin on the ink with the orange amount, dollars green, a '
        'prediction blue, a trade navy, a result by its sign', () {
      ShareCardPalette p(String k) => shareCardPalette(receiptCards[k]!);
      expect(p('sent_bitcoin'), ShareCardPalette.bitcoinClaim);
      expect(p('received_bitcoin'), ShareCardPalette.bitcoinClaim);
      expect(p('sent_dollars'), ShareCardPalette.dollars);
      expect(p('moved_to_predictions'), ShareCardPalette.prediction);
      expect(p('predicted'), ShareCardPalette.prediction);
      expect(p('cashed_out_up'), ShareCardPalette.win);
      expect(p('cashed_out_down'), ShareCardPalette.loss);
      expect(p('lost'), ShareCardPalette.loss);
      expect(p('paid_out'), ShareCardPalette.win);
      expect(p('opened_long'), ShareCardPalette.investment);
      expect(p('closed_short_up'), ShareCardPalette.win);
      expect(p('closed_long_down'), ShareCardPalette.loss);
    });

    test(
        "Sal's pose: hands it over on a send, the coin on a bitcoin "
        'receive, a squint at a call, the flop on a loss', () {
      ShareCardPose pose(String k) => shareCardPose(receiptCards[k]!);
      expect(pose('sent_bitcoin'), ShareCardPose.send);
      expect(pose('received_bitcoin'), ShareCardPose.claim);
      expect(pose('received_dollars'), ShareCardPose.win);
      expect(pose('moved_to_bitcoin'), ShareCardPose.flat);
      expect(pose('predicted'), ShareCardPose.predict);
      expect(pose('opened_long'), ShareCardPose.predict);
      expect(pose('cashed_out_up'), ShareCardPose.win);
      expect(pose('lost'), ShareCardPose.loss);
      expect(pose('closed_long_down'), ShareCardPose.loss);
    });
  });

  group('the card', () {
    testWidgets(
        'SENT bitcoin: the value huge, the bitcoin under it, ink and '
        'orange, Sal on the rule', (tester) async {
      await pumpCard(tester, receiptCards['sent_bitcoin']!);
      expect(find.byKey(const ValueKey('share-card-receipt_sent')),
          findsOneWidget);
      expect(text(tester, 'share-card-caps'), 'SENT');
      expect(text(tester, 'share-card-number'), r'$9.40');
      expect(text(tester, 'share-card-fact'), 'in bitcoin · ₿12,000');
      expect(text(tester, 'share-card-edge'),
          'No bank was harmed in this payment.');
      expect(background(tester), ShareCardPalette.bitcoinClaim.background);
      expect(find.byKey(const ValueKey('share-card-graphic')), findsNothing);
      expect(find.textContaining(kShareTestCode), findsOneWidget);
    });

    testWidgets('MOVED: the path under the money', (tester) async {
      await pumpCard(tester, receiptCards['moved_to_bitcoin']!);
      expect(text(tester, 'share-card-caps'), 'MOVED');
      expect(text(tester, 'share-card-fact'), 'in bitcoin · ₿51,500');
      expect(text(tester, 'share-card-plain'), 'Dollars → Bitcoin');
      await pumpCard(tester, receiptCards['moved_to_predictions']!);
      expect(text(tester, 'share-card-fact'), 'Your wallet → Predictions');
      expect(find.byKey(const ValueKey('share-card-plain')), findsNothing);
    });

    testWidgets(
        "I'M ON YES: the market, the speedometer at the entry, the "
        'stake on the side', (tester) async {
      await pumpCard(tester, receiptCards['predicted']!);
      expect(text(tester, 'share-card-caps'), "I'M ON YES");
      expect(find.byKey(const ValueKey('share-card-odds')), findsOneWidget);
      expect(find.text('41%'), findsOneWidget);
      expect(find.text('Chance when I got in'), findsOneWidget);
      expect(text(tester, 'share-card-plain'), r'$10.00 on Yes');
      expect(background(tester), ShareCardPalette.prediction.background);
    });

    testWidgets('CASHED OUT: the result huge, what it sold for under it',
        (tester) async {
      await pumpCard(tester, receiptCards['cashed_out_up']!);
      expect(text(tester, 'share-card-caps'), 'CASHED OUT');
      expect(text(tester, 'share-card-number'), r'+$4.20');
      expect(text(tester, 'share-card-fact'), r'Sold for $14.20');
      expect(background(tester), ShareCardPalette.win.background);
    });

    testWidgets('NOT THIS TIME: the stake, red, dry', (tester) async {
      await pumpCard(tester, receiptCards['lost']!);
      expect(text(tester, 'share-card-caps'), 'NOT THIS TIME');
      expect(text(tester, 'share-card-number'), r'−$10.00');
      expect(background(tester), ShareCardPalette.loss.background);
    });

    testWidgets('a trade: side, the market, the entry, the size',
        (tester) async {
      await pumpCard(tester, receiptCards['opened_long']!);
      expect(text(tester, 'share-card-caps'), 'OPENED POSITION · LONG');
      expect(text(tester, 'share-card-number'), r'$242.10');
      expect(text(tester, 'share-card-fact'), 'Entry');
      expect(text(tester, 'share-card-plain'), r'2.5 TSLA · $605.25');
      await pumpCard(tester, receiptCards['closed_short_up']!);
      expect(text(tester, 'share-card-number'), r'+$3.12');
      expect(text(tester, 'share-card-fact'), r'Exit price · $142.18');
      // A token bought: its price.
      await pumpCard(tester, receiptCards['spot_bought']!);
      expect(text(tester, 'share-card-caps'), 'BOUGHT');
      expect(text(tester, 'share-card-fact'), 'Price');
    });

    testWidgets('a figure the receipt does not have is left out',
        (tester) async {
      await pumpCard(
          tester,
          const ReceiptCardData(
              type: ReceiptCardKind.received,
              asset: ReceiptCardAsset.bitcoin,
              bitcoin: '₿2,100'));
      expect(text(tester, 'share-card-number'), '₿2,100');
      expect(find.byKey(const ValueKey('share-card-fact')), findsNothing);
      expect(find.textContaining('CODE'), findsNothing);
    });
  });

  group('fits', () {
    for (final locale in const [Locale('en'), Locale('de'), Locale('ja')]) {
      testWidgets(
          'every kind and every line of its pool lays out in '
          '${locale.languageCode}: no overflow, nothing cut', (tester) async {
        await tester.runAsync(loadShareCardSal);
        addTearDown(ShareCardSal.debugReset);
        for (final MapEntry(key: name, value: data) in receiptCards.entries) {
          final pool = receiptCardEdges(lookupAppLocalizations(locale), data);
          for (var seed = 0; seed < pool.length; seed++) {
            await pumpCard(tester, data, locale: locale, seed: seed);
            expect(tester.takeException(), isNull,
                reason: '$name overflowed in ${locale.languageCode}');
            for (final k in const [
              'share-card-caps',
              'share-card-edge',
              'share-card-fact',
              'share-card-plain',
              'share-card-title-head',
              'share-card-title-tail',
            ]) {
              final f = find.byKey(ValueKey(k));
              if (f.evaluate().isEmpty) continue;
              final para = tester.renderObject<RenderParagraph>(f);
              expect(para.didExceedMaxLines, isFalse,
                  reason: '${locale.languageCode} $name $k (seed $seed)');
            }
            expect(find.byKey(const ValueKey('share-card-footer')),
                findsOneWidget);
          }
        }
      });
    }
  });

  testWidgets('render the receipt cards to PNG', skip: _frames == null,
      (tester) async {
    await tester.runAsync(loadShareCardFonts);
    ShareCardSal.debugReset();
    addTearDown(ShareCardSal.debugReset);
    await tester.runAsync(loadShareCardSal);
    tester.view.physicalSize = const Size(1080, 1350);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final locale in const [Locale('en'), Locale('de'), Locale('ja')]) {
      for (final MapEntry(key: name, value: data) in receiptCards.entries) {
        if (locale.languageCode != 'en' &&
            !const {
              'sent_bitcoin',
              'predicted',
              'lost',
              'opened_long',
              'moved_to_bitcoin',
              'cashed_out_up'
            }.contains(name)) {
          continue;
        }
        final key = GlobalKey();
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: locale,
                  theme: ThemeData(
                      fontFamily: 'Inter',
                      extensions: [AppColorsExtension.light()]),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Align(
                    alignment: Alignment.topLeft,
                    child: RepaintBoundary(
                      key: key,
                      child: ShareCard(data: data, mark: ShareCardSal.peek()),
                    ),
                  ),
                )));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: name);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image =
              await boundary.toImage(pixelRatio: kShareCardPixelRatio);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(_frames!).createSync(recursive: true);
          File('$_frames/${locale.languageCode}_$name.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    }
    await writeReceiptCardSheets(tester);
  });
}

final String? _frames = Platform.environment['RECEIPT_CARD_FRAMES'];

/// Contact sheets of the cards, four across, for a look at a glance
/// (written with the frames).
Future<void> writeReceiptCardSheets(WidgetTester tester) async {
  final groups = <String, (Locale, List<String>)>{
    'sheet_en_money': (
      const Locale('en'),
      [
        'sent_bitcoin',
        'received_bitcoin',
        'incoming_bitcoin',
        'sent_dollars',
        'received_dollars',
        'moved_to_bitcoin',
        'moved_to_predictions',
        'bought_bitcoin',
      ]
    ),
    'sheet_en_markets': (
      const Locale('en'),
      [
        'sold_bitcoin',
        'predicted',
        'predicted_named',
        'cashed_out_up',
        'cashed_out_down',
        'lost',
        'paid_out',
        'opened_long',
      ]
    ),
    'sheet_en_trades': (
      const Locale('en'),
      ['closed_short_up', 'closed_long_down', 'spot_bought']
    ),
    'sheet_de': (
      const Locale('de'),
      [
        'sent_bitcoin',
        'moved_to_bitcoin',
        'predicted',
        'cashed_out_up',
        'lost',
        'opened_long',
        'closed_short_up',
        'bought_bitcoin',
      ]
    ),
    'sheet_ja': (
      const Locale('ja'),
      [
        'sent_bitcoin',
        'moved_to_bitcoin',
        'predicted',
        'cashed_out_up',
        'lost',
        'opened_long',
        'closed_short_up',
        'bought_bitcoin',
      ]
    ),
  };
  tester.view.physicalSize = const Size(4 * 370.0, 2 * 460.0);
  tester.view.devicePixelRatio = 1;
  for (final MapEntry(key: name, value: (locale, kinds)) in groups.entries) {
    final key = GlobalKey();
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: locale,
              theme: ThemeData(
                  fontFamily: 'Inter',
                  extensions: [AppColorsExtension.light()]),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final k in kinds)
                        ShareCard(
                            data: receiptCards[k]!, mark: ShareCardSal.peek()),
                    ]),
                  ),
                ),
              ),
            )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: name);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_frames/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }
}
