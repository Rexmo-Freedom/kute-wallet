// "Challenge them" (founder, 4 November 2026: "Entice users on sharing
// predictions to pick the other side on the share. 'I think Bitcoin will
// win, wanna fight me?'"): the dare's copy (four deadpan PG variants built
// from the sender's side, never "bet"), its two sides, the card (both
// sides, the sender's marked; every line whole in all 23 languages), the
// link's flag (create body, URL, router, parked claim, OneLink, the
// backend's own field; old parsing unaffected), the sender's switch, and
// the recipient's Claim screen: two explicit choices once the money is in,
// nothing preselected, the slip on the side picked.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/app_router.dart';
import 'package:kute/l10n/generated/app_localizations_de.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlMarket;
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidPerpMarketsProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider, polymarketMarketHistoryProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/cards/share_cards.dart';
import 'package:kute/screens/share/claim_screen.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_challenge.dart';
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/share_link_claims.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../helpers/kute_bar_test_support.dart';
import 'brag/brag_fixtures.dart';
import 'cards/share_card_fixtures.dart';
import 'cards/share_card_test_fonts.dart';
import 'share_test_harness.dart';

final _en = AppLocalizationsEn();
final _de = AppLocalizationsDe();

/// "Will Bitcoin hit $150k by March 2026?", Yes at 62%.
const _btc = PolymarketEvent(
  id: 'e-btc',
  slug: 'btc-150k',
  title: 'Will Bitcoin hit \$150k by March 2026?',
  volume: 1000,
  liquidity: 1000,
  category: 'crypto',
  conditionId: 'c-btc',
  outcomes: [
    PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'btc-yes'),
    PolymarketOutcome(name: 'No', price: 0.38, tokenId: 'btc-no'),
  ],
);

/// Three candidates: no single other side (a category every policy
/// offers).
const _election = PolymarketEvent(
  id: 'e-br',
  slug: 'brazil-2026',
  title: 'Who wins the 2026 Ballon d\'Or?',
  volume: 1000,
  liquidity: 1000,
  category: 'culture',
  conditionId: 'c-br',
  outcomes: [
    PolymarketOutcome(name: 'Lula', price: 0.41, tokenId: 'lula'),
    PolymarketOutcome(name: 'Tarcísio', price: 0.31, tokenId: 'tar'),
    PolymarketOutcome(name: 'Flávio', price: 0.19, tokenId: 'fla'),
  ],
);

ShareLink _link({
  String market = 'btc-150k',
  String outcome = 'Yes',
  int outcomeIndex = 0,
  bool challenge = true,
  ShareLinkStatus status = ShareLinkStatus.open,
}) =>
    ShareLink(
      id: 'lnk_1',
      kind: ShareLinkKind.dollars,
      amountMinor: 1250,
      senderLabel: 'Ana',
      marketSlug: market,
      venue: 'polymarket',
      outcome: outcome,
      outcomeIndex: outcomeIndex,
      side: 'buy',
      status: status,
      rawStatus: status.name,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      challenge: challenge,
    );

void main() {
  late ShareTestEnv env;

  setUp(() => env = setUpShareTest());
  tearDown(() {
    tearDownShareTest();
    ClaimScreen.debugDestination = null;
    ClaimScreen.debugOpenPick = null;
  });

  group('the copy', () {
    test('four dares built from the sender\'s side, PG, never "bet"', () {
      expect(challengeEdges(_en, fakeChallenge()), [
        "I'm on Yes. Think I'm wrong? Take the other side.",
        'I say Yes. Wanna fight me?',
        'Yes. Prove me wrong.',
        'I picked Yes. Your move.',
      ]);
      expect(challengeEdges(_en, fakeChallengeNamed()).first,
          "I'm on Gen.G. Think I'm wrong? Take the other side.");
      // The side in the card's language.
      expect(challengeEdges(_de, fakeChallenge()).first, contains('Ja'));
      // The card's pool is the dares, the seed picks one.
      expect(shareCardEdges(_en, fakeChallenge()),
          challengeEdges(_en, fakeChallenge()));
      for (var seed = 0; seed < 8; seed++) {
        expect(shareCardEdge(_en, fakeChallenge(), seed),
            isIn(challengeEdges(_en, fakeChallenge())));
      }
      for (final l in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(l);
        for (final line in [
          ...challengeEdges(l10n, fakeChallenge()),
          l10n.shareEdgePredictionDare,
          l10n.shareMessageChallengeNamed('Ana', 'Yes', 'Q', r'$10', 'u'),
        ]) {
          if (l.languageCode == 'en') {
            expect(line.toLowerCase(), isNot(contains('bet')), reason: line);
          }
          expect(line, isNot(contains('{')), reason: '$l: $line');
        }
      }
      // The plain pick's dare line no longer says bet either.
      expect(_en.shareEdgePredictionDare, 'Take the other side. I dare you.');
    });

    test('the caps line dares, the recipient\'s too', () {
      expect(shareCardTopLine(_en, fakeChallenge()), 'Ana, I dare you');
      expect(shareCardTopLine(_en, fakeChallenge(name: null)), 'I dare you');
      expect(shareCardTopLine(_en, fakeChallenge().asRecipient()),
          'Ana, a friend dares you');
      expect(shareCardTopLine(_en, fakeChallenge(name: null).asRecipient()),
          'A friend dares you');
      // A plain pick keeps its own.
      expect(shareCardTopLine(_en, fakeBinaryPick()), 'Ana, a pick for you');
    });

    test('the two sides: the other of Yes and No, else the rival', () {
      var s = challengeSides(_en, fakeChallenge());
      expect((s.mine.tag, s.mine.name, s.mine.chance),
          ('My side', 'Yes', '62%'));
      expect((s.theirs.tag, s.theirs.name, s.theirs.chance),
          ('Your side?', 'No', '38%'));
      s = challengeSides(_en, fakeChallenge(outcome: 'No', chance: 30));
      expect((s.mine.name, s.theirs.name, s.theirs.chance),
          ('No', 'Yes', '70%'));
      s = challengeSides(_en, fakeChallengeNamed());
      expect((s.mine.name, s.mine.chance, s.theirs.name, s.theirs.chance),
          ('Gen.G', '47%', 'T1', '53%'));
      // A named market not read yet: "?" for the other side, no chance.
      s = challengeSides(
          _en,
          const PredictionCardData(
              question: 'Q',
              outcome: 'Gen.G',
              binary: false,
              picked: true,
              challenge: true));
      expect((s.theirs.name, s.theirs.chance), ('?', null));
      expect(s.mine.chance, isNull);
      // The recipient reads whose side it is.
      s = challengeSides(_en, fakeChallenge().asRecipient() as PredictionCardData);
      expect(s.mine.tag, "Friend's side");
      s = challengeSides(_de, fakeChallenge());
      expect((s.mine.name, s.theirs.name, s.mine.chance),
          ('Ja', 'Nein', shareCardChance(_de.localeName, 62)));
    });

    testWidgets('the share text dares; an investment and a plain send do not',
        (tester) async {
      late BuildContext ctx;
      await pumpShareWidget(tester, env, Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      }));
      const url = 'https://web.test/c/lnk_1?challenge=1';
      String msg({String? name = 'Ana', String? venue = 'polymarket',
              bool challenge = true}) =>
          shareLinkMessage(ctx,
              name: name,
              amount: r'$10.00',
              url: url,
              outcome: 'Yes',
              title: 'Will it rain?',
              venue: venue,
              challenge: challenge);
      expect(
          msg(),
          'Ana, my pick: Yes on Will it rain?. Take the other side or join '
          'me. \$10.00 on me: $url');
      expect(
          msg(name: null),
          'My pick: Yes on Will it rain?. Take the other side or join me. '
          '\$10.00 on me: $url');
      expect(msg(venue: 'hyperliquid'),
          startsWith('Ana, I sent you an investment on Kute'));
      expect(msg(challenge: false),
          startsWith('Ana, I sent you a prediction on Kute'));
    });

    test('kind and pose: a dare is its own card, Sal side-eyes', () {
      expect(fakeChallenge().kind, 'send_challenge');
      expect(fakeBinaryPick().kind, 'send_prediction');
      expect(shareCardPose(fakeChallenge()), ShareCardPose.flat);
      expect(shareCardPose(fakeBinaryPick()), ShareCardPose.predict);
      expect(shareCardPalette(fakeChallenge()), ShareCardPalette.prediction);
      // Only a pick dares.
      expect(
          const PredictionCardData(question: 'Q', outcome: 'Yes', challenge: true)
              .kind,
          'prediction_market');
    });

    test('the other side among a market\'s outcomes', () {
      expect(challengeOtherSideIndex(_btc.outcomes, 0), 1);
      expect(challengeOtherSideIndex(_btc.outcomes, 1), 0);
      expect(challengeOtherSideIndex(_election.outcomes, 0), isNull);
      expect(challengeOtherSideIndex(_btc.outcomes, 2), isNull);
      expect(challengeOtherSideIndex(const [], 0), isNull);
      expect(shareChallengeOffered(hasPick: true, venue: 'polymarket'), isTrue);
      expect(
          shareChallengeOffered(hasPick: true, venue: 'hyperliquid'), isFalse);
      expect(shareChallengeOffered(hasPick: false, venue: 'polymarket'),
          isFalse);
    });
  });

  group('the card', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    testWidgets(
        'both sides, the sender\'s marked, the stake, the dare; no '
        'speedometer', (tester) async {
      await tester.runAsync(loadShareCardFonts);
      await pumpShareWidget(tester, env,
          Align(alignment: Alignment.topLeft, child: ShareCard(data: fakeChallenge())));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('share-card-send_challenge')),
          findsOneWidget);
      expect(find.text('ANA, I DARE YOU'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-versus')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-speedometer')), findsNothing);
      String text(String k) =>
          tester.widget<Text>(find.byKey(ValueKey(k))).data!;
      expect(text('share-card-versus-mine-tag'), 'MY SIDE');
      expect(text('share-card-versus-mine-name'), 'Yes');
      expect(text('share-card-versus-mine-chance'), '62%');
      expect(text('share-card-versus-theirs-tag'), 'YOUR SIDE?');
      expect(text('share-card-versus-theirs-name'), 'No');
      expect(text('share-card-versus-theirs-chance'), '38%');
      expect(text('share-card-plain'), r'$10 to play, on me');
      expect(text('share-card-edge'),
          "I'm on Yes. Think I'm wrong? Take the other side.");
      // Marked: the sender's side filled in the ink, its words in the
      // card's colour; the other side open.
      final p = ShareCardPalette.prediction;
      BoxDecoration box(String k) => tester
          .widget<Container>(find.descendant(
              of: find.byKey(ValueKey(k)), matching: find.byType(Container))
              .first)
          .decoration! as BoxDecoration;
      expect(box('share-card-versus-mine').color, p.ink);
      expect(box('share-card-versus-theirs').color, isNull);
      expect(box('share-card-versus-theirs').border, isNotNull);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('share-card-versus-mine-name')))
              .style!
              .color,
          p.background);
      // The sides sit under Sal, never behind him.
      final sal = tester.getRect(find.byKey(const ValueKey('share-card-sal')));
      final versus =
          tester.getRect(find.byKey(const ValueKey('share-card-versus')));
      expect(versus.top, greaterThanOrEqualTo(sal.bottom - 24));
    });

    // Every line whole in every language (founder: titles never cut; the
    // dares and the won card's lines are new copy in 23 languages).
    testWidgets('every dare and every won line fits, in all 23 languages',
        (tester) async {
      await tester.runAsync(loadShareCardFonts);
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cut = <String>[];
      Future<void> check(Locale locale, Widget card, String label,
          List<String> keys) async {
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            locale: locale,
            theme: ThemeData(
                fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Align(alignment: Alignment.topLeft, child: card),
          ),
        ));
        await tester.pump();
        if (tester.takeException() != null) cut.add('$locale $label overflow');
        for (final k in keys) {
          final f = find.byKey(ValueKey(k));
          if (f.evaluate().isEmpty) continue;
          for (final e in f.evaluate()) {
            final r = e.renderObject;
            if (r is RenderParagraph && r.didExceedMaxLines) {
              cut.add('$locale $label $k: ${r.text.toPlainText()}');
            }
          }
        }
      }

      const cardKeys = [
        'share-card-caps',
        'share-card-edge',
        'share-card-plain',
        'share-card-versus-mine-tag',
        'share-card-versus-theirs-tag',
        'share-card-versus-mine-name',
        'share-card-versus-theirs-name',
      ];
      const bragKeys = [
        'brag-card-caps',
        'brag-card-edge',
        'brag-card-plain',
        'brag-card-fact',
        'brag-card-meta',
      ];
      for (final locale in AppLocalizations.supportedLocales) {
        for (var seed = 0; seed < 4; seed++) {
          await check(
              locale,
              ShareCard(data: fakeChallengeNamed(name: 'Daniel'), lineSeed: seed),
              'dare $seed',
              cardKeys);
          await check(
              locale,
              ShareCard(
                  data: fakeChallenge(name: 'Daniel').asRecipient(),
                  lineSeed: seed),
              'dare hero $seed',
              cardKeys);
          await check(locale, BragCard(data: fakeBragWin(), lineSeed: seed),
              'won $seed', bragKeys);
        }
      }
      expect(cut, isEmpty, reason: cut.join('\n'));
    });
  });

  group('the link carries the flag', () {
    test('the URL: ?challenge=1 added, the id still read by old parsing', () {
      const url = 'https://kute.test/c/lnk_1';
      final dared = shareChallengeUrl(url);
      expect(dared, 'https://kute.test/c/lnk_1?challenge=1');
      expect(shareChallengeUrl('https://kute.test/c/lnk_1?ref=JOAO42'),
          'https://kute.test/c/lnk_1?ref=JOAO42&challenge=1');
      expect(shareChallengeUrl(''), '');
      final uri = Uri.parse(dared);
      expect(ShareLinkClaims.claimIdFromLink(uri), 'lnk_1');
      expect(ShareLinkClaims.challengeFromLink(uri), isTrue);
      expect(ShareLinkClaims.challengeFromLink(Uri.parse(url)), isFalse);
      // The OneLink form (the claim page's Get Kute, once the backend
      // passes it on).
      final onelink = Uri.parse('https://kute.onelink.me/x?deep_link_value='
          'claim&deep_link_sub1=lnk_1&deep_link_sub2=challenge');
      expect(ShareLinkClaims.claimIdFromLink(onelink), 'lnk_1');
      expect(ShareLinkClaims.challengeFromLink(onelink), isTrue);
    });

    test('the router: the route carries it, a locked session parks it', () {
      ShareLinksStore.debugMemory = <String, String>{};
      addTearDown(() => ShareLinksStore.debugMemory = null);
      final uri = Uri.parse('https://kute.test/c/lnk_1?challenge=1');
      final route = AppRouter.claimLinkRedirect(uri, locked: false);
      expect(route, '/claim/lnk_1?challenge=1');
      expect(ShareLinkClaims.challengeFromLink(Uri.parse(route!)), isTrue);
      expect(
          AppRouter.claimLinkRedirect(
              Uri.parse('https://kute.test/c/lnk_1'),
              locked: false),
          '/claim/lnk_1');
      // Locked: parked with its flag, cleared together.
      expect(AppRouter.claimLinkRedirect(uri, locked: true), isNull);
      expect(ShareLinksStore.parkedClaimId, 'lnk_1');
      expect(ShareLinksStore.parkedClaimChallenge, isTrue);
      expect(ShareLinksStore.all(), isEmpty, reason: 'not a pending row');
      expect(ShareLinksStore.takeParkedClaim(), 'lnk_1');
      expect(ShareLinksStore.parkedClaimId, isNull);
      expect(ShareLinksStore.parkedClaimChallenge, isFalse);
      // A plain link parked after a challenge drops the flag.
      ShareLinksStore.parkClaim('lnk_2', challenge: true);
      ShareLinksStore.parkClaim('lnk_3');
      expect(ShareLinksStore.parkedClaimChallenge, isFalse);
    });

    test('the backend: read optional, the pending row round-trips', () {
      Map<String, Object?> json({Object? challenge}) => {
            'id': 'lnk_1',
            'kind': 'dollars',
            'amountMinor': 1000,
            'status': 'open',
            if (challenge != null) 'challenge': challenge,
          };
      expect(ShareLink.fromJson(json(challenge: true))!.challenge, isTrue);
      expect(ShareLink.fromJson(json())!.challenge, isFalse,
          reason: 'a backend that does not store it');
      expect(ShareLink.fromJson(json(challenge: 'yes'))!.challenge, isFalse);
      final row = PendingShareLink(
        id: 'lnk_1',
        kind: ShareLinkKind.dollars,
        amountMinor: 1000,
        url: 'https://kute.test/c/lnk_1?challenge=1',
        createdAt: DateTime(2026, 11, 4),
        status: ShareLinkStatus.open,
        challenge: true,
      );
      final back = PendingShareLink.fromJson(jsonDecode(jsonEncode(row.toJson())))!;
      expect(back.challenge, isTrue);
      expect(back.url, row.url);
      expect(back.withStatus(ShareLinkStatus.claimed).challenge, isTrue);
      final plain = PendingShareLink.fromJson(jsonDecode(jsonEncode(
          PendingShareLink(
            id: 'lnk_2',
            kind: ShareLinkKind.dollars,
            amountMinor: 1000,
            url: 'u',
            createdAt: DateTime(2026, 11, 4),
            status: ShareLinkStatus.open,
          ).toJson())))!;
      expect(plain.challenge, isFalse);
      expect(plain.toJson().containsKey('challenge'), isFalse);
    });

    test('create sends challenge: true only on a dare', () async {
      final bodies = <Object?>[];
      final api = BackendShareLinksApi(
        baseUrl: 'https://backend.test',
        sessionSender: (route, send) => send(const {}),
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body));
          return http.Response(
              jsonEncode({'id': 'lnk_1', 'url': 'https://web.test/c/lnk_1'}),
              201);
        }),
      );
      await api.create(
          kind: ShareLinkKind.dollars,
          amountMinor: 1000,
          marketSlug: 'btc-150k',
          venue: 'polymarket',
          outcome: 'Yes',
          outcomeIndex: 0,
          side: 'buy',
          challenge: true);
      await api.create(kind: ShareLinkKind.dollars, amountMinor: 1000);
      expect((bodies.first! as Map)['challenge'], true);
      expect((bodies.last! as Map).containsKey('challenge'), isFalse);
    });
  });

  group('the sender', () {
    late List<String> shared;
    setUp(() {
      shared = [];
      ShareCardShare.debugSharer = (XFile image, String text) async {
        shared.add(text);
        return 'success';
      };
    });

    Future<void> toName(WidgetTester tester, SendToAnyoneSheet sheet) async {
      await pumpShareWidget(tester, env, sheet);
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('0'));
      await settle(tester);
      await tester.tap(kuteBarPrimaryWithText('Continue'));
      await settle(tester);
    }

    testWidgets(
        'a prediction: the switch, off by default; on, the live card dares '
        'and the link goes as a challenge', (tester) async {
      await toName(
          tester,
          const SendToAnyoneSheet(
            kind: ShareLinkKind.dollars,
            marketSlug: 'will-it-rain',
            marketTitle: 'Will it rain?',
            venue: 'polymarket',
            outcome: 'Yes',
            outcomeIndex: 0,
            side: 'buy',
          ));
      expect(find.text('Challenge them'), findsOneWidget);
      expect(find.text('Dare them to take the other side'), findsOneWidget);
      expect(
          tester
              .widget<Switch>(
                  find.byKey(const ValueKey('share-challenge-switch')))
              .value,
          isFalse);
      expect(find.byKey(const ValueKey('share-card-send_prediction')),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('share-name-field')), 'Ana');
      await tester.tap(find.byKey(const ValueKey('share-challenge-toggle')));
      await settle(tester);
      expect(find.byKey(const ValueKey('share-card-send_challenge')),
          findsOneWidget);
      expect(find.text('ANA, I DARE YOU'), findsOneWidget);
      await tester.tap(kuteBarPrimaryWithText('Create link'));
      await settle(tester);
      await shareCardAndWait(tester, shared);

      expect(env.fake.calls.single.$2['challenge'], true);
      final row = ShareLinksStore.byId('lnk_1')!;
      expect(row.challenge, isTrue);
      expect(row.url, 'https://web.test/c/lnk_1?challenge=1');
      expect(
          shared.single,
          'Ana, my pick: Yes on Will it rain?. Take the other side or join '
          'me. \$10.00 on me: https://web.test/c/lnk_1?challenge=1');
      expect(env.paramsOf('share_link_created').single, {
        'kind': 'dollars',
        'asset': 'USDB',
        'amount': 10.0,
        'market': 'will-it-rain',
        'outcome': 'Yes',
        'challenge': true,
      });
    });

    testWidgets('left off: a plain pick, no flag anywhere', (tester) async {
      await toName(
          tester,
          const SendToAnyoneSheet(
            kind: ShareLinkKind.dollars,
            marketSlug: 'will-it-rain',
            marketTitle: 'Will it rain?',
            venue: 'polymarket',
            outcome: 'Yes',
            outcomeIndex: 0,
            side: 'buy',
          ));
      await tester.tap(kuteBarPrimaryWithText('Create link'));
      await settle(tester);
      expect(env.fake.calls.single.$2.containsKey('challenge'), isFalse);
      expect(ShareLinksStore.byId('lnk_1')!.url, 'https://web.test/c/lnk_1');
      expect(ShareLinksStore.byId('lnk_1')!.challenge, isFalse);
    });

    testWidgets('an investment has no switch',
        (tester) async {
      await toName(
          tester,
          const SendToAnyoneSheet(
            kind: ShareLinkKind.dollars,
            marketSlug: 'BTC',
            marketTitle: 'BTC',
            venue: 'hyperliquid',
            outcome: 'Long',
            side: 'long',
          ));
      expect(find.byKey(const ValueKey('share-name-field')), findsOneWidget);
      expect(find.text('Challenge them'), findsNothing);
    });

    testWidgets('a plain send has no switch', (tester) async {
      await toName(
          tester, const SendToAnyoneSheet(kind: ShareLinkKind.dollars));
      expect(find.byKey(const ValueKey('share-name-field')), findsOneWidget);
      expect(find.text('Challenge them'), findsNothing);
    });
  });

  group('the recipient', () {
    late List<ClaimPickOpening> opened;

    setUp(() {
      opened = [];
      ClaimScreen.debugDestination = (_) async => 'spark1recipient';
      ClaimScreen.debugOpenPick = opened.add;
    });

    Future<void> pump(WidgetTester tester, {bool routeFlag = false}) =>
        pumpShareWidget(
            tester, env, ClaimScreen(id: 'lnk_1', challenge: routeFlag),
            cardVenues: false,
            overrides: [
              usdBalanceProvider.overrideWithValue(0),
              polymarketEventDetailsProvider.overrideWith((ref, slug) async =>
                  slug == _btc.slug
                      ? _btc
                      : slug == _election.slug
                          ? _election
                          : null),
              polymarketMarketHistoryProvider
                  .overrideWith((ref, key) async => const []),
              hyperliquidPerpMarketsProvider
                  .overrideWith((ref) async => const <HlMarket>[]),
              hyperliquidSpotMarketsProvider
                  .overrideWith((ref) async => const <HlMarket>[]),
            ]);

    /// Claims, then the sender's app pays: the money is in.
    Future<void> claimAndArrive(WidgetTester tester, ShareLink paid) async {
      await tester.tap(kuteBarPrimaryWithText('Claim'));
      await settle(tester);
      env.fake.seed(paid);
      await tester.pump(ClaimScreen.paidPollInterval);
      await settle(tester);
    }

    testWidgets(
        'the dare as the hero; once the money is in, two choices and '
        'nothing preselected; Take the other side opens No',
        (tester) async {
      env.fake.seed(_link());
      await pump(tester);
      expect(find.byKey(const ValueKey('share-card-send_challenge')),
          findsOneWidget);
      expect(find.text('ANA, A FRIEND DARES YOU'), findsOneWidget);
      expect(find.text("FRIEND'S SIDE"), findsOneWidget);
      expect(find.text('YOUR SIDE?'), findsOneWidget);

      await tester.tap(kuteBarPrimaryWithText('Claim'));
      await settle(tester);
      // Waiting for the money: no choice yet.
      expect(find.text('Your friend is on Yes · \$12.50'), findsOneWidget);
      expect(find.byKey(const ValueKey('claim-same-side')), findsNothing);
      expect(kuteBarPrimaryWithText('Take the other side'), findsNothing);

      env.fake.seed(_link(status: ShareLinkStatus.paid));
      await tester.pump(ClaimScreen.paidPollInterval);
      await settle(tester);
      expect(kuteBarPrimaryWithText('Take the other side'), findsOneWidget);
      expect(find.text('Same side as your friend'), findsOneWidget);
      expect(find.text('Place the prediction'), findsNothing);
      // Nothing opened, nothing chosen, before a tap.
      expect(opened, isEmpty);
      expect(env.paramsOf('share_challenge_answered'), isEmpty);

      await tester.tap(kuteBarPrimaryWithText('Take the other side'));
      await settle(tester);
      expect(opened.single, (outcomeIndex: 1, market: false));
      expect(env.paramsOf('share_challenge_answered').single, {
        'kind': 'dollars',
        'asset': 'USDB',
        'amount': 12.5,
        'choice': 'other_side',
        'market': 'btc-150k',
      });

      await tester.tap(find.byKey(const ValueKey('claim-same-side')));
      await settle(tester);
      expect(opened.last, (outcomeIndex: 0, market: false));
      expect(env.paramsOf('share_challenge_answered').last!['choice'],
          'same_side');
    });

    testWidgets('a No pick: the other side is Yes', (tester) async {
      env.fake.seed(_link(outcome: 'No', outcomeIndex: 1));
      await pump(tester);
      await claimAndArrive(
          tester,
          _link(outcome: 'No', outcomeIndex: 1, status: ShareLinkStatus.paid));
      await tester.tap(kuteBarPrimaryWithText('Take the other side'));
      await settle(tester);
      expect(opened.single, (outcomeIndex: 0, market: false));
    });

    testWidgets('the URL\'s flag alone makes it a challenge', (tester) async {
      env.fake.seed(_link(challenge: false));
      await pump(tester, routeFlag: true);
      expect(find.text('ANA, A FRIEND DARES YOU'), findsOneWidget);
      await claimAndArrive(
          tester, _link(challenge: false, status: ShareLinkStatus.paid));
      expect(kuteBarPrimaryWithText('Take the other side'), findsOneWidget);
    });

    testWidgets(
        'no single other side (three candidates): the market, nothing '
        'preselected', (tester) async {
      env.fake.seed(_link(market: 'brazil-2026', outcome: 'Lula'));
      await pump(tester);
      await claimAndArrive(tester,
          _link(market: 'brazil-2026', outcome: 'Lula', status: ShareLinkStatus.paid));
      await tester.tap(kuteBarPrimaryWithText('Take the other side'));
      await settle(tester);
      expect(opened.single, (outcomeIndex: null, market: true));
      // Same side still opens the friend's pick.
      await tester.tap(find.byKey(const ValueKey('claim-same-side')));
      await settle(tester);
      expect(opened.last, (outcomeIndex: 0, market: false));
    });

    testWidgets('a plain pick keeps Place the prediction, no choices',
        (tester) async {
      env.fake.seed(_link(challenge: false));
      await pump(tester);
      expect(find.text('ANA, A FRIEND SENT YOU A PICK'), findsOneWidget);
      await claimAndArrive(
          tester, _link(challenge: false, status: ShareLinkStatus.paid));
      expect(kuteBarPrimaryWithText('Place the prediction'), findsOneWidget);
      expect(find.byKey(const ValueKey('claim-same-side')), findsNothing);
      await tester.tap(kuteBarPrimaryWithText('Place the prediction'));
      await settle(tester);
      expect(opened.single, (outcomeIndex: 0, market: false));
      expect(env.paramsOf('share_challenge_answered'), isEmpty);
    });
  });
}
