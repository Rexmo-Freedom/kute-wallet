// The bet slip opened on a charted game outcome wears EXACTLY that
// outcome's line colour, the colour of its button on the market page
// (founder, 12 November 2026, a Benfica vs Austria Wien slip on Draw still
// a deep amber under white text: "the sheet still has the old colors"),
// and everything lettered on it is the ink that reads on that colour: one
// on-colour ([contrastingOnColor] of the sheet), dark on the palette's
// soft tones, white on a dark fill. Every Text and Icon on the slip is
// walked and read against the fill under it (helpers/ink_contrast.dart).
//
// Yes / No and Up / Down slips are as they were: white on the same green
// and red.
//
// A light sheet's panes and outlines are as quiet as a green one's (founder,
// 12 November 2026, on the Draw slip: "they look like they have bigger
// borders?"): the Draw and Yes slips are laid out at 393 pt with the same
// boxes, corners and outline widths, and each pane and outline stands off
// its sheet as far on Draw as on Yes.
//
// The PNGs (the Draw slip and a Yes slip, light and dark, and both at 393
// pt) are written only when asked:
//
//   BET_SLIP_ON_COLOUR_RENDER=<dir> flutter test \
//     test/screens/polymarket/bet_slip_on_colour_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart'
    show kGameSideColors;
import 'package:kute/screens/polymarket/components/outcome_leading.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, AmountMaxChip, BigAmountDisplay;
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/standing_orders/standing_order_store.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_bar_surface.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/ink_contrast.dart';
import '../../helpers/render_png.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/shell_bar_harness.dart';
import '../../services/standing_orders/fake_secret_store.dart';

final _dir = Platform.environment['BET_SLIP_ON_COLOUR_RENDER'];

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
  Future<void> refresh() async {}
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 100);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

class _MemoryStandingStore extends StandingOrderStore {
  _MemoryStandingStore() : super(secrets: FakeSecretStore());
  final Map<String, StandingOrder> rows = {};
  @override
  Future<List<StandingOrder>> load(String walletId) async =>
      [for (final o in rows.values) if (o.walletId == walletId) o];
  @override
  Future<void> save(StandingOrder order) async => rows[order.id] = order;
  @override
  Future<void> remove(StandingOrder order) async => rows.remove(order.id);
}

// The founder's game: home, draw, away, in the market page's own colours
// (the chart's lines: sky blue, orange for the draw, lavender).
const _match = [
  PolymarketOutcome(name: 'Benfica', price: 0.62, tokenId: 'home'),
  PolymarketOutcome(name: 'Draw', price: 0.22, tokenId: 'draw'),
  PolymarketOutcome(name: 'Austria Wien', price: 0.16, tokenId: 'away'),
];
const _matchLabels = ['Benfica', 'Draw', 'Austria Wien'];
final _matchColors = <Color?>[
  kGameSideColors[0],
  kGameSideColors[2],
  kGameSideColors[1],
];

const _overUnder = [
  PolymarketOutcome(name: 'Over', price: 0.48, tokenId: 'over'),
  PolymarketOutcome(name: 'Under', price: 0.52, tokenId: 'under'),
];
const _yesNo = [
  PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'yes'),
  PolymarketOutcome(name: 'No', price: 0.38, tokenId: 'no'),
];
const _upDown = [
  PolymarketOutcome(name: 'Up', price: 0.55, tokenId: 'up'),
  PolymarketOutcome(name: 'Down', price: 0.45, tokenId: 'down'),
];

/// The fill a white-lettered line had before this change, worked out here
/// on its own: the line's hue, darkened until white reads at 4.5:1.
Color _whiteLetteredFill(Color line) {
  double white(Color c) => 1.05 / (c.computeLuminance() + 0.05);
  if (white(line) >= 4.5) return line;
  final hsl = HSLColor.fromColor(line);
  var l = hsl.lightness;
  var fill = line;
  while (l > 0 && white(fill) < 4.5) {
    l = (l - 0.005).clamp(0.0, 1.0);
    fill = hsl.withLightness(l).toColor();
  }
  return fill;
}

RuntimeCapabilitiesService? _policy;

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, BetSlipSheet slip,
    {bool dark = false,
    List<StandingOrder> standing = const [],
    Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  installShellBar();
  // Everything allowed: the slip's own action, Advanced.
  final policy = _policy = runtimePolicyFixture();
  RuntimeCapabilitiesService.debugInstance = policy;
  expect(await policy.refresh(), isTrue);
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
            wallets: [WalletConfig(id: 'w', name: 'Spending')],
            activeWalletId: 'w',
          ))),
      polymarketTradingProvider.overrideWith(_Trading.new),
      livePriceProvider.overrideWith(_Prices.new),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const <Order>[])),
      polymarketFeeTermsProvider
          .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
      swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
      aiEnabledProvider.overrideWith((ref) async => false),
      currencyProvider.overrideWith((ref) => _Currency()),
      usdBalanceProvider.overrideWithValue(0),
      standingOrderStoreProvider.overrideWithValue(_MemoryStandingStore()),
    ],
    child: shellBarApp(
      dark: dark,
      home: Builder(
        builder: (context) => Scaffold(
          resizeToAvoidBottomInset: false,
          body: Center(
            child: TextButton(
              key: const ValueKey('open-slip'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                enableDrag: false,
                backgroundColor: Colors.transparent,
                builder: (_) => slip,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await _frames(tester, 2);
  if (standing.isNotEmpty) {
    ProviderScope.containerOf(
            tester.element(find.byKey(const ValueKey('open-slip'))))
        .read(standingOrdersProvider.notifier)
        .debugReplace(standing);
    await _frames(tester, 2);
  }
  await tester.tap(find.byKey(const ValueKey('open-slip')));
  await _frames(tester);
}

/// Leaves the slip and lets its timers run out.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  _policy?.dispose();
  _policy = null;
  await tester.pump(const Duration(seconds: 30));
}

BetSlipSheet _matchSlip(int index,
        {Set<String>? standingEndedBefore, double? amount = 10}) =>
    BetSlipSheet(
      marketQuestion: 'Benfica vs Austria Wien',
      outcomes: _match,
      outcomeLabels: _matchLabels,
      outcomeColors: _matchColors,
      initialOutcomeIndex: index,
      initialAmountUsd: amount,
      standingEndedBefore: standingEndedBefore,
    );

StandingOrder _standing(String token, String side) {
  final at = DateTime.now();
  return StandingOrder(
    id: 'so_test',
    walletId: 'w',
    venue: StandingOrderVenue.predictions,
    marketKey: token,
    marketTitle: 'Benfica vs Austria Wien',
    sideLabel: side,
    isBuy: true,
    size: 45.45,
    approvedPrice: 0.22,
    amountUsd: 10,
    orderKind: 'market',
    state: StandingOrderState.posting,
    createdAt: at,
    updatedAt: at,
  );
}

SheetTint _tint(WidgetTester tester) => tester.widget<SheetTint>(
    find.descendant(
        of: find.byType(BetSlipSheet), matching: find.byType(SheetTint)).first);

/// The sheet's own painted colour (the rounded container the slip is).
Color? _sheetFill(WidgetTester tester) {
  final box = find
      .descendant(
          of: find.byType(BetSlipSheet),
          matching: find.byType(AnimatedContainer))
      .first;
  return (tester.widget<AnimatedContainer>(box).decoration as BoxDecoration)
      .color;
}

Color _page(bool dark) =>
    (dark ? AppColorsExtension.dark() : AppColorsExtension.light()).background;

/// Everything lettered on the slip reads on what is under it, and the
/// bar's button (the slip's one action) reads on its own fill and stands
/// off the sheet.
void _expectSlipReads(WidgetTester tester,
    {required bool dark, required String reason, bool live = true}) {
  final sheet = _sheetFill(tester)!;
  final inks = expectInksRead(tester, find.byType(BetSlipSheet),
      page: _page(dark), reason: reason);
  expect(inks.length, greaterThan(4), reason: '$reason: the slip is lettered');
  // A white button would not stand off a light sheet: the app's own
  // near-black button, white words.
  final button = barPrimaryContext(tester).style!;
  if (_tint(tester).on == Colors.black) {
    expect(button.fill, KuteBarSurface.inkOnWhite, reason: reason);
    expect(button.foreground, Colors.white, reason: reason);
  }
  expect(contrastRatio(button.foreground, button.fill),
      greaterThanOrEqualTo(4.5),
      reason: '$reason: the button\'s label on its fill');
  expect(contrastRatio(button.fill, sheet), greaterThanOrEqualTo(3),
      reason: '$reason: the button against the sheet');
  // The words as the bar draws them (a step still to take, "Enter an
  // amount", is the bar's own off look, not the slip's).
  if (live && barPrimaryContext(tester).actionable) {
    expectInksRead(tester, findBarPrimary(),
        page: sheet, reason: '$reason: the bar\'s button');
  }
}

void main() {
  setUpAll(loadRenderFonts);
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AffiliateService.debugSessionToken = 'test-session';
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  group('polyOutcomeFill', () {
    test('a line dark ink reads on is its own fill: button, line and slip '
        'are one colour', () {
      for (final line in {...kPolyOutcomeColors, ...kGameSideColors}) {
        if (contrastingOnColor(line) == Colors.white) continue;
        expect(polyOutcomeFill(line), line);
        expect(contrastRatio(Colors.black, line), greaterThanOrEqualTo(7.0));
      }
      // The three a game draws.
      expect(polyOutcomeFill(const Color(0xFF4FC3F7)), const Color(0xFF4FC3F7));
      expect(polyOutcomeFill(const Color(0xFFCE93D8)), const Color(0xFFCE93D8));
      expect(polyOutcomeFill(const Color(0xFFFFB74D)), const Color(0xFFFFB74D));
    });

    test('a white-lettered line is darkened as before, and only as far as '
        'white needs', () {
      for (final line in [
        AppColors.marketUp,
        AppColors.marketDown,
        AppColors.info,
        const Color(0xFF1E3A8A),
      ]) {
        expect(contrastingOnColor(line), Colors.white);
        expect(polyOutcomeFill(line), _whiteLetteredFill(line));
        expect(polyWhiteContrast(polyOutcomeFill(line)),
            greaterThanOrEqualTo(4.5));
      }
      expect(polyOutcomeFill(const Color(0xFF1E3A8A)), const Color(0xFF1E3A8A));
    });
  });

  group('the tint\'s palette', () {
    final light = AppColorsExtension.light();

    test('white ink: every step as it always was (the green and red '
        'sheets, the Investing ticket)', () {
      for (final side in [AppColors.marketUp, AppColors.marketDown]) {
        final c = sideTintPalette(light, side);
        const on = Colors.white;
        expect(c.background, side);
        expect(c.textPrimary, on);
        expect(c.surface, on.withValues(alpha: 0.16));
        expect(c.surfaceLight, on.withValues(alpha: 0.24));
        expect(c.surfaceElevated, on.withValues(alpha: 0.32));
        expect(c.textSecondary, on.withValues(alpha: 0.78));
        expect(c.textTertiary, on.withValues(alpha: 0.64));
        expect(c.textDisabled, on.withValues(alpha: 0.38));
        expect(c.border, on.withValues(alpha: 0.34));
        expect(c.borderSubtle, on.withValues(alpha: 0.22));
        expect(c.dragHandle, on.withValues(alpha: 0.45));
        expect(isSideTinted(c), isTrue);
      }
      expect(tintPane(Colors.white, AppColors.marketUp, 0.32),
          Colors.white.withValues(alpha: 0.32));
      expect(tintEdge(Colors.white, AppColors.marketDown, 0.62, over: 0.32),
          Colors.white.withValues(alpha: 0.62));
      expect(slipCtaFill(Colors.white), Colors.white);
      expect(
          slipCtaLabelColor(
              fill: Colors.white, side: AppColors.marketUp, neutral: true),
          Colors.black);
    });

    test('dark ink on any fill it is picked for: the words read at 4.5:1 '
        'on the sheet and on its panes', () {
      Color over(Color top, Color under) => Color.alphaBlend(top, under);
      // The darkest fill dark ink is picked for, and the palette's.
      final fills = [
        for (final line in {...kPolyOutcomeColors, ...kGameSideColors})
          if (contrastingOnColor(line) == Colors.black) line,
        const Color(0xFFE57373),
      ];
      for (final side in fills) {
        final c = sideTintPalette(light, side);
        expect(c.textPrimary, Colors.black);
        expect(isSideTinted(c), isTrue);
        for (final ink in [c.textPrimary, c.textSecondary, c.textTertiary]) {
          expect(contrastRatio(over(ink, side), side),
              greaterThanOrEqualTo(4.5),
              reason: '$ink on $side');
        }
        // On a pane: the full ink on the strongest, the second on the
        // tappable one.
        final picked = over(tintPane(Colors.black, side, 0.32), side);
        expect(contrastRatio(Colors.black, picked), greaterThanOrEqualTo(4.5),
            reason: 'ink on the picked pane of $side');
        final tappable = over(c.surfaceLight, side);
        expect(contrastRatio(over(c.textSecondary, tappable), tappable),
            greaterThanOrEqualTo(4.5),
            reason: 'second ink on the tappable pane of $side');
      }
      // The button: the app's own near-black one, white words.
      expect(slipCtaFill(Colors.black), KuteBarSurface.inkOnWhite);
      expect(
          slipCtaLabelColor(
              fill: slipCtaFill(Colors.black),
              side: kGameSideColors[0],
              neutral: true),
          Colors.white);
    });
  });

  group(
      'dark ink\'s panes and borders stand off the sheet as white\'s do '
      'on the Yes slip\'s green', () {
    final light = AppColorsExtension.light();
    final fills = [
      for (final line in {...kPolyOutcomeColors, ...kGameSideColors})
        if (contrastingOnColor(line) == Colors.black) line,
    ];
    double white(double alpha) => tintStepContrast(
        Colors.white.withValues(alpha: alpha), AppColors.marketUp);

    test(
        'every step of the palette, every pane and outline of the side '
        'buttons, the close circle', () {
      expect(fills, isNotEmpty);
      for (final side in fills) {
        final c = sideTintPalette(light, side);
        for (final (name, step, alpha) in [
          ('surface', c.surface, 0.16),
          ('surfaceLight', c.surfaceLight, 0.24),
          ('surfaceElevated', c.surfaceElevated, 0.32),
          ('border', c.border, 0.34),
          ('borderSubtle', c.borderSubtle, 0.22),
          ('dragHandle', c.dragHandle, 0.45),
          for (final a in [0.10, 0.18, 0.32, 0.40, 0.62])
            ('pane $a', tintPane(Colors.black, side, a), a),
        ]) {
          expect(tintStepContrast(step, side), closeTo(white(alpha), 0.002),
              reason: '$name on $side');
        }
        // An outline over its own pane: the two together, as the eye
        // meets the rim.
        for (final (border, pane) in [(0.62, 0.32), (0.24, 0.10)]) {
          final rim = Color.alphaBlend(
              tintEdge(Colors.black, side, border, over: pane),
              Color.alphaBlend(tintPane(Colors.black, side, pane), side));
          final whiteRim = Color.alphaBlend(
              Colors.white.withValues(alpha: border),
              Color.alphaBlend(
                  Colors.white.withValues(alpha: pane), AppColors.marketUp));
          expect(contrastRatio(rim, side),
              closeTo(contrastRatio(whiteRim, AppColors.marketUp), 0.002),
              reason: 'outline $border over pane $pane on $side');
        }
      }
    });

    test(
        'the same alpha in black was far heavier: the borders the founder '
        'saw', () {
      const draw = Color(0xFFFFB74D);
      // Before: black at white's 0.62 and 0.34 on the Draw slip.
      expect(tintStepContrast(Colors.black.withValues(alpha: 0.62), draw),
          greaterThan(2 * white(0.62)));
      expect(tintStepContrast(Colors.black.withValues(alpha: 0.34), draw),
          greaterThan(1.4 * white(0.34)));
      // Now: the same.
      expect(tintStepContrast(sideTintPalette(light, draw).border, draw),
          closeTo(white(0.34), 0.002));
    });
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    group('a game\'s slip wears its line\'s colour ($theme)', () {
      for (final (index, name) in _matchLabels.indexed) {
        testWidgets('$name: the sheet is the line\'s colour, lettered in the '
            'ink that reads on it', (tester) async {
          final line = _matchColors[index]!;
          await _pump(tester, _matchSlip(index), dark: dark);
          expect(_sheetFill(tester), line);
          expect(_tint(tester).side, line);
          expect(_tint(tester).on, contrastingOnColor(line));
          expect(_tint(tester).on, Colors.black);
          // The subtree's theme says which way its ink goes (the status
          // bar's and the platform controls' brightness).
          expect(
              Theme.of(tester.element(find.byType(AmountKeypad))).brightness,
              Brightness.light);
          expect(find.byType(AmountKeypad), findsOneWidget);
          _expectSlipReads(tester, dark: dark, reason: '$name ($theme)');
          await _close(tester);
        });
      }

      testWidgets('switching side on the slip switches the sheet to that '
          'line\'s colour, still read', (tester) async {
        await _pump(tester, _matchSlip(1), dark: dark);
        for (final (index, name) in _matchLabels.indexed) {
          await tester.tap(find
              .descendant(
                  of: find.byType(BetSlipSheet), matching: find.text(name))
              .first);
          await _frames(tester, 6);
          expect(_sheetFill(tester), _matchColors[index]);
          _expectSlipReads(tester, dark: dark, reason: 'to $name ($theme)');
        }
        await _close(tester);
      });

      testWidgets('nothing typed, a stake under the minimum, one past the '
          'balance: each state\'s words read', (tester) async {
        for (final amount in <double?>[null, 0.5, 500]) {
          for (final index in [0, 1, 2]) {
            await _pump(tester, _matchSlip(index, amount: amount), dark: dark);
            expect(_sheetFill(tester), _matchColors[index]);
            _expectSlipReads(tester,
                dark: dark,
                live: false,
                reason: '${_matchLabels[index]} at $amount ($theme)');
            await _close(tester);
          }
        }
      });

      testWidgets('one of many outcomes, picked on its Yes: its line\'s '
          'colour; its No stays red, white', (tester) async {
        const many = [
          PolymarketOutcome(
              name: 'Benfica', price: 0.4, tokenId: 'a', noTokenId: 'an'),
          PolymarketOutcome(
              name: 'Porto', price: 0.3, tokenId: 'b', noTokenId: 'bn'),
          PolymarketOutcome(
              name: 'Sporting', price: 0.2, tokenId: 'c', noTokenId: 'cn'),
          PolymarketOutcome(
              name: 'Braga', price: 0.1, tokenId: 'd', noTokenId: 'dn'),
        ];
        for (final index in [0, 1, 2, 3]) {
          await _pump(
              tester,
              BetSlipSheet(
                marketQuestion: 'Who wins the league?',
                outcomes: many,
                outcomeColors: kPolyOutcomeColors.take(4).toList(),
                initialOutcomeIndex: index,
                initialAmountUsd: 10,
              ),
              dark: dark);
          expect(_sheetFill(tester), kPolyOutcomeColors[index]);
          expect(_tint(tester).on, Colors.black);
          _expectSlipReads(tester,
              dark: dark, reason: '${many[index].name} ($theme)');
          if (index == 0) {
            await tester.tap(find
                .descendant(
                    of: find.byType(BetSlipSheet), matching: find.text('NO'))
                .first);
            await _frames(tester, 6);
            expect(_sheetFill(tester), AppColors.marketDown);
            expect(_tint(tester).on, Colors.white);
          }
          await _close(tester);
        }
      });

      testWidgets('Over / Under of a line wear the chart\'s two colours',
          (tester) async {
        final colors = [kPolyOutcomeColors[0], kPolyOutcomeColors[1]];
        for (final index in [0, 1]) {
          await _pump(
              tester,
              BetSlipSheet(
                marketQuestion: 'Benfica vs Austria Wien: O/U 2.5',
                outcomes: _overUnder,
                outcomeColors: colors,
                initialOutcomeIndex: index,
                initialAmountUsd: 10,
              ),
              dark: dark);
          expect(_sheetFill(tester), colors[index]);
          expect(_tint(tester).on, Colors.black);
          _expectSlipReads(tester,
              dark: dark, reason: '${_overUnder[index].name} ($theme)');
          await _close(tester);
        }
      });

      testWidgets('every line colour of a many-outcome chart reads as a slip',
          (tester) async {
        for (final line in kPolyOutcomeColors) {
          await _pump(
              tester,
              BetSlipSheet(
                marketQuestion: 'Benfica vs Austria Wien: O/U 2.5',
                outcomes: _overUnder,
                outcomeColors: [line, kPolyOutcomeColors[1]],
                initialAmountUsd: 10,
              ),
              dark: dark);
          expect(_sheetFill(tester), polyOutcomeFill(line));
          if (contrastingOnColor(line) == Colors.black) {
            expect(_sheetFill(tester), line);
            _expectSlipReads(tester, dark: dark, reason: '$line ($theme)');
          }
          await _close(tester);
        }
      });

      testWidgets('locked on its order: the order\'s figure and the placing '
          'line read on the line\'s colour, OK', (tester) async {
        await _pump(tester, _matchSlip(1, standingEndedBefore: const {}),
            dark: dark, standing: [_standing('draw', 'Draw')]);
        expect(find.byType(AmountKeypad), findsNothing);
        expect(find.byKey(const ValueKey('slip-order-figure')), findsOneWidget);
        expect(find.byKey(const ValueKey('bet-slip-standing-placing')),
            findsOneWidget);
        expect(barPrimaryLabel(tester), 'OK');
        expect(_sheetFill(tester), kGameSideColors[2]);
        _expectSlipReads(tester, dark: dark, reason: 'locked Draw ($theme)');
        if (_dir case final dir?) {
          await writeViewPng(tester, '$dir/draw_locked_$theme.png');
        }
        await _close(tester);
      });

      testWidgets('Advanced keeps the app\'s palette; the picked side is its '
          'line\'s colour, lettered to read on it', (tester) async {
        await _pump(tester, _matchSlip(1), dark: dark);
        await tester.tap(find.byType(SlipAdvancedButton));
        await _frames(tester);
        final advanced = find.byType(PolySlipAdvancedScaffold);
        expect(advanced, findsOneWidget);
        // The page itself is the app's own, not a sheet of the side.
        expect(
            find.descendant(of: advanced, matching: find.byType(SheetTint)),
            findsNothing);
        // The picked side: a slab of the line's colour, dark words on it.
        final line = kGameSideColors[2];
        final onLine = [
          for (final ink in readInks(tester, advanced, page: _page(dark)))
            if (ink.fill == line) ink,
        ];
        expect(onLine.map((i) => i.what), contains('Draw'));
        for (final ink in onLine) {
          expect(ink.ink, Colors.black, reason: '$ink');
          expect(ink.ratio, greaterThanOrEqualTo(4.5), reason: '$ink');
        }
        if (_dir case final dir?) {
          await writeViewPng(tester, '$dir/draw_advanced_$theme.png');
        }
        await _close(tester);
      });
    });

    group('Yes / No and Up / Down are as they were ($theme)', () {
      testWidgets('Yes / No: white on the same green and red', (tester) async {
        for (final (index, fill) in [
          (0, AppColors.marketUp),
          (1, AppColors.marketDown),
        ]) {
          await _pump(
              tester,
              BetSlipSheet(
                marketQuestion: 'Will it rain in Lisbon tomorrow?',
                outcomes: _yesNo,
                initialOutcomeIndex: index,
                initialAmountUsd: 10,
              ),
              dark: dark);
          expect(_sheetFill(tester), fill);
          _expectWhiteSlip(tester, fill);
          if (_dir case final dir? when index == 0) {
            await writeViewPng(tester, '$dir/yes_$theme.png');
          }
          await _close(tester);
        }
      });

      testWidgets('Up / Down on their chart colours: white on the same '
          'deepened green and red', (tester) async {
        final lines = [AppColors.marketUp, AppColors.marketDown];
        for (final index in [0, 1]) {
          await _pump(
              tester,
              BetSlipSheet(
                marketQuestion: 'Bitcoin up or down today?',
                outcomes: _upDown,
                outcomeColors: lines,
                initialOutcomeIndex: index,
                initialAmountUsd: 10,
              ),
              dark: dark);
          final fill = _whiteLetteredFill(lines[index]);
          expect(_sheetFill(tester), fill);
          _expectWhiteSlip(tester, fill);
          await _close(tester);
        }
      });
    });

    testWidgets(
        'Draw and Yes at 393 pt: one geometry, the same quiet '
        'outlines ($theme)', (tester) async {
      const size = Size(393, 852);
      await _pump(tester, _matchSlip(1), dark: dark, size: size);
      final draw = _slipChrome(tester);
      if (_dir case final dir?) {
        await writeViewPng(tester, '$dir/draw_393_$theme.png');
      }
      await _close(tester);
      await _pump(
          tester,
          BetSlipSheet(
            marketQuestion: 'Will it rain in Lisbon tomorrow?',
            outcomes: _yesNo,
            initialOutcomeIndex: 0,
            initialAmountUsd: 10,
          ),
          dark: dark,
          size: size);
      final yes = _slipChrome(tester);
      if (_dir case final dir?) {
        await writeViewPng(tester, '$dir/yes_393_$theme.png');
      }
      await _close(tester);

      expect(draw.sheet.fill, kGameSideColors[2]);
      expect(yes.sheet.fill, AppColors.marketUp);
      expect(draw.toggles, hasLength(3));
      expect(yes.toggles, hasLength(2));
      // Geometry: every control the same box, corner, outline width and
      // padding. The side buttons share one row, so only their width
      // follows how many there are.
      for (final (name, a, b) in [
        ('max', draw.max, yes.max),
        ('advanced', draw.advanced, yes.advanced),
        ('key', draw.key, yes.key),
        ('close', draw.close, yes.close),
        ('amount', draw.amount, yes.amount),
        ('sheet edge', draw.sheet, yes.sheet),
      ]) {
        expect(a.shape, b.shape, reason: '$name ($theme)');
      }
      for (final t in [...draw.toggles, ...yes.toggles]) {
        expect(t.rowShape, yes.toggles.first.rowShape,
            reason: 'side button ($theme)');
      }
      for (final (i, t) in draw.toggles.indexed) {
        expect(t.size.width, closeTo(draw.toggles.first.size.width, 0.5),
            reason: 'Draw side $i width');
      }
      // Contrast: each pane and each outline stands off its sheet as far
      // on Draw as on Yes.
      final dSheet = draw.sheet.fill!, ySheet = yes.sheet.fill!;
      void same(String name, Color? d, Color? y,
          {Color? dUnder, Color? yUnder}) {
        expect(d, isNotNull, reason: name);
        expect(y, isNotNull, reason: name);
        final dc =
            contrastRatio(Color.alphaBlend(d!, dUnder ?? dSheet), dSheet);
        final yc =
            contrastRatio(Color.alphaBlend(y!, yUnder ?? ySheet), ySheet);
        expect(dc, closeTo(yc, 0.01), reason: '$name ($theme): $dc vs $yc');
      }

      final dPicked = draw.toggles.firstWhere((t) => t.picked);
      final yPicked = yes.toggles.firstWhere((t) => t.picked);
      final dOther = draw.toggles.firstWhere((t) => !t.picked);
      final yOther = yes.toggles.firstWhere((t) => !t.picked);
      same('picked side pane', dPicked.fill, yPicked.fill);
      same('other side pane', dOther.fill, yOther.fill);
      same('picked side outline', dPicked.border, yPicked.border,
          dUnder: Color.alphaBlend(dPicked.fill!, dSheet),
          yUnder: Color.alphaBlend(yPicked.fill!, ySheet));
      same('other side outline', dOther.border, yOther.border,
          dUnder: Color.alphaBlend(dOther.fill!, dSheet),
          yUnder: Color.alphaBlend(yOther.fill!, ySheet));
      same('max pane', draw.max.fill, yes.max.fill);
      same('max outline', draw.max.border, yes.max.border);
      same('advanced pane', draw.advanced.fill, yes.advanced.fill);
      same('advanced outline', draw.advanced.border, yes.advanced.border);
      same('key', draw.key.fill, yes.key.fill);
      same('close circle', draw.close.fill, yes.close.fill);
      same('sheet edge', draw.sheet.border, yes.sheet.border);
    });

    testWidgets('renders: the Draw slip ($theme)', (tester) async {
      await _pump(tester, _matchSlip(1), dark: dark);
      expect(tester.takeException(), isNull);
      if (_dir case final dir?) {
        await writeViewPng(tester, '$dir/draw_$theme.png');
      }
      await _close(tester);
    });
  }
}

/// The slip as it has always been on a dark fill: white ink, in the
/// palette's own tiers, the selected side a brighter pane of it, the
/// button white lettered in the side's colour.
void _expectWhiteSlip(WidgetTester tester, Color fill) {
  final tint = _tint(tester);
  expect(tint.side, fill);
  expect(tint.on, Colors.white);
  final c = tester.element(find.byType(AmountKeypad)).colors;
  expect(c.background, fill);
  expect(c.textPrimary, Colors.white);
  expect(c.textSecondary, Colors.white.withValues(alpha: 0.78));
  expect(c.textTertiary, Colors.white.withValues(alpha: 0.64));
  expect(c.textDisabled, Colors.white.withValues(alpha: 0.38));
  expect(c.surface, Colors.white.withValues(alpha: 0.16));
  expect(c.surfaceLight, Colors.white.withValues(alpha: 0.24));
  expect(c.surfaceElevated, Colors.white.withValues(alpha: 0.32));
  expect(c.border, Colors.white.withValues(alpha: 0.34));
  expect(c.borderSubtle, Colors.white.withValues(alpha: 0.22));
  expect(c.dragHandle, Colors.white.withValues(alpha: 0.45));
  // Every ink on the slip is white (at one of its tiers), on the fill or
  // a white pane of it.
  final inks = readInks(tester, find.byType(BetSlipSheet), page: fill);
  expect(inks, isNotEmpty);
  for (final ink in inks) {
    expect(ink.ink.computeLuminance(),
        greaterThan(ink.fill.computeLuminance()),
        reason: 'white ink: $ink');
  }
  // The picked side's pane and the other's, as before.
  final panes = [
    for (final e in find
        .descendant(
            of: find.byType(BetSlipSheet),
            matching: find.byWidgetPredicate((w) =>
                w is AnimatedContainer &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).border is Border &&
                (w.decoration as BoxDecoration).borderRadius != null &&
                w.constraints?.maxHeight != double.infinity))
        .evaluate())
      (e.widget as AnimatedContainer).decoration as BoxDecoration,
  ];
  final fills = {for (final p in panes) p.color};
  expect(fills, contains(Colors.white.withValues(alpha: 0.32)));
  expect(fills, contains(Colors.white.withValues(alpha: 0.10)));
  // The white button, its words dark (never the side's colour).
  final button = barPrimaryContext(tester).style!;
  expect(button.fill, Colors.white);
  expect(button.foreground, Colors.black);
}

/// One painted control on the slip: its box, corner, outline width and
/// padding ([shape], compared between slips), and its two colours.
class _Chrome {
  _Chrome(this.size, this.corner, this.borderWidth, this.padding, this.fill,
      this.border);

  final Size size;
  final String corner;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final Color? border;

  /// The picked side of a row: the strongest pane.
  bool picked = false;

  String get shape => '$size $corner $borderWidth $padding';

  /// A side button's shape apart from its width (the row shares it out).
  String get rowShape => '${size.height} $corner $borderWidth $padding';
}

_Chrome _chromeOf(WidgetTester tester, Finder f) {
  final w = tester.widget(f);
  final (decoration, padding) = switch (w) {
    AnimatedContainer(:final decoration, :final padding) => (
        decoration,
        padding
      ),
    Container(:final decoration, :final padding) => (decoration, padding),
    _ => throw StateError('$w'),
  };
  final size = tester.getSize(f);
  switch (decoration) {
    case BoxDecoration(:final color, :final borderRadius, :final border):
      final side = switch (border) {
        Border(:final top) => top,
        _ => BorderSide.none,
      };
      return _Chrome(size, '$borderRadius', side.width, padding, color,
          side.style == BorderStyle.none ? null : side.color);
    case ShapeDecoration(:final color, :final shape):
      final side = (shape as OutlinedBorder).side;
      return _Chrome(size, '${shape.runtimeType}', side.width, padding, color,
          side.style == BorderStyle.none ? null : side.color);
  }
  throw StateError('$decoration');
}

typedef _SlipChrome = ({
  _Chrome sheet,
  List<_Chrome> toggles,
  _Chrome max,
  _Chrome advanced,
  _Chrome key,
  _Chrome close,
  _Chrome amount,
});

bool _boxed(Widget w) =>
    (w is Container && w.decoration is BoxDecoration) ||
    (w is AnimatedContainer && w.decoration is BoxDecoration);

/// The slip's chrome as laid out: the sheet, its side buttons, the Max
/// and Advanced pills, a keypad key, the close circle and the amount.
_SlipChrome _slipChrome(WidgetTester tester) {
  final slip = find.byType(BetSlipSheet);
  final sheet = _chromeOf(
      tester,
      find
          .descendant(of: slip, matching: find.byType(AnimatedContainer))
          .first);
  final toggles = [
    for (final e in find
        .descendant(
            of: slip,
            matching: find.byWidgetPredicate((w) =>
                w is AnimatedContainer &&
                w.constraints != null &&
                w.decoration is BoxDecoration &&
                ((w.decoration as BoxDecoration).border?.isUniform ?? false)))
        .evaluate())
      _chromeOf(tester, find.byWidget(e.widget)),
  ];
  final strongest =
      toggles.map((t) => t.fill!.a).reduce((a, b) => a > b ? a : b);
  for (final t in toggles) {
    t.picked = t.fill!.a == strongest;
  }
  Finder face(Finder of) =>
      find.descendant(of: of, matching: find.byWidgetPredicate(_boxed)).first;
  final key = find
      .ancestor(
          of: find.descendant(
              of: find.byType(AmountKeypad), matching: find.text('5')),
          matching: find.byWidgetPredicate(_boxed))
      .first;
  return (
    sheet: sheet,
    toggles: toggles,
    max: _chromeOf(tester, face(find.byType(AmountMaxChip))),
    advanced: _chromeOf(tester, face(find.byType(SlipAdvancedButton))),
    key: _chromeOf(tester, key),
    close: _chromeOf(
        tester,
        find
            .descendant(
                of: find.descendant(
                    of: slip, matching: find.byType(KuteCloseButton)),
                matching: find.byType(AnimatedContainer))
            .first),
    amount: _Chrome(tester.getSize(find.byType(BigAmountDisplay)), '-', 0, null,
        null, null),
  );
}
