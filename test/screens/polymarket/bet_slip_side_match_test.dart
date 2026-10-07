// The Predictions slip's selected side: the card highlighted, the slip's
// colour, the button's label, the disc glyph and the token the order buys
// all name the same outcome, for any outcome names. The owner's slip on a
// "Bitcoin Up or Down" market had DOWN selected (red) and read "Place
// $2.48 on UP": the label asked "is the outcome called No", so every
// non-Yes/No second side read as the first.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/formatters/polymarket_side_labels.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/selected_outcome_guard.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 100);
}

/// Records the intent the slip hands to placement (the token it would
/// sign), then stops before anything is signed.
/// Prepares against a book that holds $4 under the cap: the stake of $10
/// cannot fill.
class _ThinBookController extends PolymarketBetController {
  _ThinBookController(super.ref);
  @override
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent) async {
    final book = parsePolymarketOrderBook({
      'market': 'm',
      'asset_id': intent.tokenId,
      'tick_size': '0.01',
      'neg_risk': false,
      'min_order_size': '1',
      'asks': [
        {'price': '0.40', 'size': '10'}
      ],
      'bids': const [],
    });
    return intent.copyWith(
        marketQuote: PolymarketMarketBuyQuote.fromBook(book,
            tokenId: intent.tokenId,
            amount: intent.amount,
            slippagePct: intent.slippagePct));
  }

  @override
  Future<AuthGrantException?> place(String mode,
      {required AuthGrant grant,
      bool successHaptic = true,
      String? entrySource}) {
    throw StateError('a stake the book cannot fill must not be placed');
  }
}

class _CaptureController extends PolymarketBetController {
  _CaptureController(super.ref);
  final tokens = <String>[];
  @override
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent) async {
    tokens.add(intent.tokenId);
    throw StateError('captured');
  }
}

/// The controller the slip read, created when placement first asks.
_CaptureController? _controller;

Future<void> _pumpSlip(
  WidgetTester tester, {
  required String question,
  required List<PolymarketOutcome> outcomes,
  required int initialIndex,
  String? sideLabelPos,
  String? sideLabelNeg,
  PolymarketBetController Function(Ref ref)? controller,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _controller = null;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
      polymarketTradingProvider.overrideWith(_Trading.new),
      swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
      livePriceProvider.overrideWith(_Prices.new),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const <Order>[])),
      aiEnabledProvider.overrideWith((ref) async => false),
      polymarketBetControllerProvider.overrideWith((ref) =>
          controller?.call(ref) ?? (_controller = _CaptureController(ref))),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BetSlipSheet(
              marketQuestion: question,
              outcomes: outcomes,
              initialOutcomeIndex: initialIndex,
              sideLabelPos: sideLabelPos,
              sideLabelNeg: sideLabelNeg,
              initialAmountUsd: 10,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

PolySlipCta _cta(WidgetTester tester) =>
    tester.widget<PolySlipCta>(find.byType(PolySlipCta).first);

/// One market and, per outcome index, what its side must read as.
class _Case {
  const _Case(this.name, this.question, this.outcomes, this.labels, this.icons,
      this.colors,
      {this.sideLabelPos, this.sideLabelNeg, this.ctaLabels});
  final String name;
  final String question;
  final List<PolymarketOutcome> outcomes;
  final List<String> labels;
  final List<IconData> icons;
  final List<Color> colors;
  final String? sideLabelPos;
  final String? sideLabelNeg;

  /// What the button names, when it differs from the card's casing.
  final List<String>? ctaLabels;
}

const _green = AppColors.marketUp;
const _red = AppColors.marketDown;

final _cases = [
  const _Case(
    'Yes/No',
    'Will it rain?',
    [
      PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'tok-yes'),
      PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'tok-no'),
    ],
    ['YES', 'NO'],
    [Icons.check_rounded, Icons.close_rounded],
    [_green, _red],
    ctaLabels: ['Yes', 'No'],
  ),
  const _Case(
    'Up/Down (the owner\'s market)',
    'Bitcoin Up or Down - October 7, 8:45AM-8:50AM ET',
    [
      PolymarketOutcome(name: 'Up', price: 0.5, tokenId: 'tok-up'),
      PolymarketOutcome(name: 'Down', price: 0.5, tokenId: 'tok-down'),
    ],
    ['UP', 'DOWN'],
    [Icons.arrow_upward_rounded, Icons.arrow_downward_rounded],
    [_green, _red],
  ),
  const _Case(
    'Down listed first',
    'Bitcoin Up or Down - October 7, 9:00AM-9:05AM ET',
    [
      PolymarketOutcome(name: 'Down', price: 0.5, tokenId: 'tok-down'),
      PolymarketOutcome(name: 'Up', price: 0.5, tokenId: 'tok-up'),
    ],
    ['DOWN', 'UP'],
    [Icons.arrow_downward_rounded, Icons.arrow_upward_rounded],
    [_red, _green],
  ),
  const _Case(
    'two teams, title in the outcomes\' order',
    'Lakers vs. Celtics',
    [
      PolymarketOutcome(name: 'Lakers', price: 0.5, tokenId: 'tok-lal'),
      PolymarketOutcome(name: 'Celtics', price: 0.5, tokenId: 'tok-bos'),
    ],
    ['Lakers', 'Celtics'],
    [Icons.bolt_rounded, Icons.bolt_rounded],
    [_green, _red],
  ),
  const _Case(
    'two teams, the caller\'s labels in the other order',
    'Lakers vs. Celtics',
    [
      PolymarketOutcome(name: 'Lakers', price: 0.5, tokenId: 'tok-lal'),
      PolymarketOutcome(name: 'Celtics', price: 0.5, tokenId: 'tok-bos'),
    ],
    ['Lakers', 'Celtics'],
    [Icons.bolt_rounded, Icons.bolt_rounded],
    [_green, _red],
    sideLabelPos: 'Celtics',
    sideLabelNeg: 'Lakers',
  ),
  const _Case(
    'Over/Under',
    'Total goals O/U 2.5',
    [
      PolymarketOutcome(name: 'Over', price: 0.5, tokenId: 'tok-over'),
      PolymarketOutcome(name: 'Under', price: 0.5, tokenId: 'tok-under'),
    ],
    ['OVER', 'UNDER'],
    [Icons.arrow_upward_rounded, Icons.arrow_downward_rounded],
    [_green, _red],
  ),
];

Future<RuntimeCapabilitiesService> _allowEverything() async {
  AffiliateService.debugSessionToken = 'test-session';
  final policy = runtimePolicyFixture();
  RuntimeCapabilitiesService.debugInstance = policy;
  expect(await policy.refresh(), isTrue);
  return policy;
}

Future<void> _release(
    WidgetTester tester, RuntimeCapabilitiesService policy) async {
  await tester.pumpWidget(const SizedBox.shrink());
  policy.dispose();
  RuntimeCapabilitiesService.debugInstance = null;
  AffiliateService.debugSessionToken = null;
}

void main() {
  group('each side of the slip names one outcome', () {
    for (final c in _cases) {
      for (final pick in [0, 1]) {
        testWidgets('${c.name}: picking ${c.outcomes[pick].name}',
            (tester) async {
          final policy = await _allowEverything();
          // Open on the other side, then pick this one on the slip, the
          // way the owner did.
          await _pumpSlip(tester,
              question: c.question,
              outcomes: c.outcomes,
              initialIndex: 1 - pick,
              sideLabelPos: c.sideLabelPos,
              sideLabelNeg: c.sideLabelNeg);
          // Both sides show their own label and glyph; no check or cross
          // on a market that is not Yes/No.
          final sides = find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_BinaryToggleButton');
          expect(sides, findsNWidgets(2));
          // The card that shows outcome [i]'s label (the positive side is
          // drawn first, wherever it sits in the outcome list).
          Finder sideOf(int i) =>
              find.ancestor(of: find.text(c.labels[i]), matching: sides);
          for (final i in [0, 1]) {
            expect(sideOf(i), findsOneWidget, reason: 'side $i label');
            expect(
                find.descendant(
                    of: sideOf(i), matching: find.byIcon(c.icons[i])),
                findsOneWidget,
                reason: 'side $i glyph');
          }
          if (!c.icons.contains(Icons.check_rounded)) {
            for (final glyph in [Icons.check_rounded, Icons.close_rounded]) {
              expect(find.descendant(of: sides, matching: find.byIcon(glyph)),
                  findsNothing);
            }
          }

          await tester.tap(sideOf(pick));
          await tester.pumpAndSettle();

          final cta = _cta(tester);
          expect(
              cta.label, 'Place \$10.00 on ${(c.ctaLabels ?? c.labels)[pick]}');
          expect(cta.color, c.colors[pick]);

          await tester.tap(find.byType(PolySlipCta).first);
          await tester.pumpAndSettle();
          expect(_controller?.tokens, [c.outcomes[pick].tokenId]);
          expect(tester.takeException(), isNull);
          await _release(tester, policy);
        });
      }
    }
  });

  group('side labels by outcome', () {
    test('a semantic pair is matched to the outcome it names', () {
      expect(
          polymarketBinarySideLabels(['Up', 'Down'], (pos: 'UP', neg: 'DOWN')),
          ['UP', 'DOWN']);
      expect(
          polymarketBinarySideLabels(['Down', 'Up'], (pos: 'UP', neg: 'DOWN')),
          ['DOWN', 'UP']);
      expect(
          polymarketBinarySideLabels(['Los Angeles Lakers', 'Boston Celtics'],
              (pos: 'Celtics', neg: 'Lakers')),
          ['Lakers', 'Celtics']);
      expect(
          polymarketBinarySideLabels(
              ['LGC', 'Team Falcons'], (pos: 'LGC -1.5', neg: 'Falcons +1.5')),
          ['LGC -1.5', 'Falcons +1.5']);
    });

    test('Yes/No takes the pair by meaning, wherever Yes sits', () {
      expect(
          polymarketBinarySideLabels(
              ['Yes', 'No'], (pos: 'OVER', neg: 'UNDER')),
          ['OVER', 'UNDER']);
      expect(
          polymarketBinarySideLabels(
              ['No', 'Yes'], (pos: 'OVER', neg: 'UNDER')),
          ['UNDER', 'OVER']);
    });

    test('an unmatched or ambiguous pair falls back to the outcome names', () {
      expect(
          polymarketBinarySideLabels(
              ['Heat', 'Knicks'], (pos: 'UP', neg: 'DOWN')),
          isNull);
      expect(polymarketBinarySideLabels(['Yes', 'No'], (pos: 'YES', neg: 'NO')),
          isNull);
      expect(
          polymarketBinarySideLabels(
              ['Real Madrid', 'Real Betis'], (pos: 'Real', neg: 'Real')),
          isNull);
    });

    test('positive side and glyphs', () {
      expect(polymarketPositiveIndex(['Up', 'Down']), 0);
      expect(polymarketPositiveIndex(['Down', 'Up']), 1);
      expect(polymarketPositiveIndex(['No', 'Yes']), 1);
      expect(polymarketPositiveIndex(['Lakers', 'Celtics']), 0);
      expect(polymarketSideGlyph('YES'), PolymarketSideGlyph.yes);
      expect(polymarketSideGlyph('No'), PolymarketSideGlyph.no);
      expect(polymarketSideGlyph('DOWN'), PolymarketSideGlyph.down);
      expect(polymarketSideGlyph('Over'), PolymarketSideGlyph.up);
      expect(polymarketSideGlyph('Lakers'), PolymarketSideGlyph.neutral);
    });
  });

  group('the guard before signing', () {
    const outcomes = [
      PolymarketOutcome(name: 'Up', price: 0.5, tokenId: 'tok-up'),
      PolymarketOutcome(
          name: 'Down', price: 0.5, tokenId: 'tok-down', noTokenId: 'tok-x'),
    ];

    test('passes when the order buys the selected outcome', () {
      ensureOrderBuysSelectedOutcome(
          orderedTokenId: 'tok-down',
          outcomes: outcomes,
          selectedIndex: 1,
          buyNo: false);
      ensureOrderBuysSelectedOutcome(
          orderedTokenId: 'tok-x',
          outcomes: outcomes,
          selectedIndex: 1,
          buyNo: true);
    });

    test('trips when it would buy the other side, or nothing is selected', () {
      for (final (token, index, buyNo) in [
        ('tok-up', 1, false),
        ('tok-down', 0, false),
        ('tok-down', 1, true),
        ('', 1, false),
        ('tok-up', 2, false),
        ('tok-up', -1, false),
      ]) {
        expect(
            () => ensureOrderBuysSelectedOutcome(
                orderedTokenId: token,
                outcomes: outcomes,
                selectedIndex: index,
                buyNo: buyNo),
            throwsA(isA<PolymarketSideMismatch>()),
            reason: '$token @ $index buyNo=$buyNo');
      }
    });
  });

  testWidgets(
      'a stake the book cannot fill says what fills now, before any approval',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester,
        question: 'Bitcoin Up or Down - October 7, 8:45AM-8:50AM ET',
        outcomes: const [
          PolymarketOutcome(name: 'Up', price: 0.5, tokenId: 'tok-up'),
          PolymarketOutcome(name: 'Down', price: 0.5, tokenId: 'tok-down'),
        ],
        initialIndex: 1,
        controller: _ThinBookController.new);
    await tester.tap(find.byType(PolySlipCta).first);
    await tester.pumpAndSettle();
    expect(
        find.text('Up to \$4.00 fills now at this price. Nothing was bought. '
            'Try that amount or less.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('bet-slip-retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _release(tester, policy);
  });
}
