// The locked bet slip after Confirm, while the money moves (founder, 12
// November 2026, on a green "AI bubble burst in 2026?" slip: "this moving
// and small letters does not seem good"; "moving $1 from Bitcoin, make it
// look better"). The journey under the order's figure is clear and
// confident:
//
//   * the status is the thing people read: the stage in the slip's body
//     size, semibold, in the full on-colour ("Getting your prediction
//     ready", "Placing $1.00 on Yes"), a small live dot before it, the
//     step at work as a quieter second line under it ("Moving $1.00 from
//     Bitcoin"), each line its own words;
//   * nothing tiny: no amounts under the stations (they repeat the stake)
//     and no step dots under the destination (they repeat the status), no
//     text in the journey under 13 sp;
//   * the order's line under the figure ("Yes · pays $7.47 if you win") is
//     the size of the slip's other secondary words, not a caption;
//   * nothing cut at 320 pt, text x1.5, light and dark, on a white-ink
//     Yes slip and a dark-ink Draw slip; Reduce Motion holds still.
//
// The PNGs (a green Yes slip mid-journey and a Draw slip) are written only
// when asked:
//
//   BET_SLIP_ON_COLOUR_RENDER=<dir> flutter test \
//     test/screens/polymarket/slip_journey_status_test.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
import 'package:kute/screens/shared/side_tint_palette.dart' show SheetTint;
import 'package:kute/screens/shared/slip_stat_tiles.dart' show SlipJourney;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show fundedOrderGraph;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/ink_contrast.dart';
import '../../helpers/render_png.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/shell_bar_harness.dart';

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
      const PolymarketTradingState(usdcBalance: 0);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

class _Funded extends FundedOrdersNotifier {
  _Funded(this.records);
  final List<FundedOrderRecord> records;
  @override
  List<FundedOrderRecord> build() => records;
}

const _yesNo = [
  PolymarketOutcome(name: 'Yes', price: 0.134, tokenId: 'yes'),
  PolymarketOutcome(name: 'No', price: 0.866, tokenId: 'no'),
];

const _match = [
  PolymarketOutcome(name: 'Benfica', price: 0.62, tokenId: 'home'),
  PolymarketOutcome(name: 'Draw', price: 0.22, tokenId: 'draw'),
  PolymarketOutcome(name: 'Austria Wien', price: 0.16, tokenId: 'away'),
];

/// A bet of [usd] on [token], all of it from Bitcoin, straight into
/// Predictions: the Bitcoin leg running ([at] `leg`), or landed with the
/// venue confirming the balance ([at] `confirm`).
FundedOrderRecord _fromBitcoin(String token, String side, double usd,
    {String at = 'leg'}) {
  var g = fundedOrderGraph(
    venue: OneBalanceVenue.predictions,
    orderUsd: usd,
    legs: [
      MoneyStep(
          id: 'leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: usd),
    ],
  );
  g = MoneyStepGraph([
    for (final s in g.steps)
      s.copyWith(
          status: switch ((s.id, at)) {
        ('leg:bitcoin', 'leg') => MoneyStepStatus.running,
        ('leg:bitcoin', _) => MoneyStepStatus.done,
        ('ready:convert' || 'ready:approve', 'confirm') =>
          MoneyStepStatus.skipped,
        ('ready:confirm', 'confirm') => MoneyStepStatus.running,
        _ => s.status,
      }),
  ]);
  return FundedOrderRecord(
    id: 'fo_$token',
    label: FundedOrderLabel(
      venue: OneBalanceVenue.predictions,
      orderUsd: usd,
      side: side,
      market: 'q',
      marketKey: token,
    ),
    stage: at == 'leg' ? FundedOrderStage.adding : FundedOrderStage.preparing,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    addUsd: usd,
    btcRowIds: const {'q_btc'},
    steps: g,
  );
}

RuntimeCapabilitiesService? _policy;

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, BetSlipSheet slip,
    {required List<FundedOrderRecord> funded,
    bool dark = false,
    double width = 390,
    double textScale = 1,
    bool reduceMotion = false}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  installShellBar();
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
      fundedOrdersProvider.overrideWith(() => _Funded(funded)),
    ],
    child: shellBarApp(
      dark: dark,
      wrap: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion),
        child: child!,
      ),
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
  await tester.tap(find.byKey(const ValueKey('open-slip')));
  await _frames(tester, 16);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  _policy?.dispose();
  _policy = null;
  await tester.pump(const Duration(seconds: 30));
}

BetSlipSheet _yesSlip() => const BetSlipSheet(
      marketQuestion: 'AI bubble burst in 2026?',
      outcomes: _yesNo,
      initialOutcomeIndex: 0,
      initialAmountUsd: 1,
    );

BetSlipSheet _drawSlip() => BetSlipSheet(
      marketQuestion: 'Benfica vs Austria Wien',
      outcomes: _match,
      outcomeLabels: const ['Benfica', 'Draw', 'Austria Wien'],
      outcomeColors: [
        kGameSideColors[0],
        kGameSideColors[2],
        kGameSideColors[1]
      ],
      initialOutcomeIndex: 1,
      initialAmountUsd: 10,
    );

Color _page(bool dark) =>
    (dark ? AppColorsExtension.dark() : AppColorsExtension.light()).background;

final _title = find.byKey(const ValueKey('money-steps-title'));
final _detail = find.byKey(const ValueKey('money-steps-detail'));

/// Every paragraph in [root] a person can see (not faded out to nothing),
/// with its own size.
List<(String, double)> _visibleSizes(WidgetTester tester, Finder root) {
  final out = <(String, double)>[];
  for (final e in find
      .descendant(of: root, matching: find.byType(RichText))
      .evaluate()) {
    var seen = 1.0;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Opacity) seen *= w.opacity;
      return true;
    });
    if (seen < 0.05) continue;
    final p = e.renderObject! as RenderParagraph;
    if (!p.attached || !p.hasSize || p.size.isEmpty) continue;
    void visit(InlineSpan span, double? inherited) {
      if (span is! TextSpan) return;
      final size = span.style?.fontSize ?? inherited;
      final text = span.text;
      if (text != null && text.trim().isNotEmpty && size != null) {
        out.add((text, size));
      }
      for (final c in span.children ?? const <InlineSpan>[]) {
        visit(c, size);
      }
    }

    visit(p.text, null);
  }
  return out;
}

/// No text on screen is cut: no paragraph past its lines, none past the
/// view's edges.
void _expectNothingCut(WidgetTester tester, double width, String reason) {
  for (final e in find
      .descendant(
          of: find.byType(BetSlipSheet), matching: find.byType(RichText))
      .evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    if (!p.attached || !p.hasSize || p.size.isEmpty) continue;
    final text = p.text.toPlainText();
    expect(p.didExceedMaxLines, isFalse, reason: '$reason: "$text" cut');
    final r =
        MatrixUtils.transformRect(p.getTransformTo(null), Offset.zero & p.size);
    expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$reason: "$text"');
    expect(r.right, lessThanOrEqualTo(width + 0.5), reason: '$reason: "$text"');
  }
}

/// The contrast a journey's words must reach on the slip: 4.5:1, or on a
/// white-ink slip's green and red (white there as ever, founder rule) all
/// the full white gives: the slip's own on-colour at full strength.
double _fullContrast(WidgetTester tester) {
  final tint = tester.widget<SheetTint>(find
      .descendant(
          of: find.byType(BetSlipSheet), matching: find.byType(SheetTint))
      .first);
  return math.min(4.5, contrastRatio(tint.on, tint.side) - 0.01);
}

/// The journey's status and words, as the founder asked for them.
void _expectClearJourney(WidgetTester tester,
    {required bool dark, required String reason}) {
  final full = _fullContrast(tester);
  final journey = find.byType(SlipJourney);
  expect(journey, findsOneWidget, reason: reason);
  // The status: one title, in the slip's body size, semibold, full ink.
  expect(_title, findsOneWidget, reason: '$reason: the status title');
  final titleText = tester.widget<RichText>(
      find.descendant(of: _title, matching: find.byType(RichText)).first);
  final style = titleText.text.style!;
  expect(style.fontSize, greaterThanOrEqualTo(16.sp - 0.01),
      reason: '$reason: the status in the body size');
  expect(style.fontWeight!.value, greaterThanOrEqualTo(600),
      reason: '$reason: the status semibold');
  final inks = readInks(tester, _title, page: _page(dark));
  expect(inks, isNotEmpty, reason: reason);
  for (final i in inks) {
    expect(i.ratio, greaterThanOrEqualTo(full), reason: '$reason: $i');
  }
  // Nothing in the journey under 13 sp, and everything there reads.
  for (final (text, size) in _visibleSizes(tester, journey)) {
    expect(size, greaterThanOrEqualTo(13.sp - 0.01),
        reason: '$reason: "$text" at $size');
  }
  expectInksRead(tester, journey,
      page: _page(dark), text: full, reason: reason);
  // No amounts under the stations: they repeated the stake.
  expect(
      find.descendant(
          of: journey,
          matching: find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>)
                  .value
                  .startsWith('money-steps-station-amount-'))),
      findsNothing,
      reason: '$reason: no amounts under the stations');
  // The order's line under the figure: the slip's secondary size.
  final line =
      tester.widget<Text>(find.byKey(const ValueKey('slip-order-figure-line')));
  expect(line.style!.fontSize, greaterThanOrEqualTo(16.sp - 0.01),
      reason: '$reason: the order\'s line readable');
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

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets(
        'a green Yes slip mid-journey: the stage, then the step at '
        'work, nothing tiny ($theme)', (tester) async {
      await _pump(tester, _yesSlip(),
          dark: dark, funded: [_fromBitcoin('yes', 'Yes', 1)]);
      if (_dir case final dir?) {
        await writeViewPng(tester, '$dir/yes_journey_$theme.png');
      }
      expect(tester.widget<Text>(_titleText()).data,
          'Getting your prediction ready');
      expect(tester.widget<Text>(_detailText()).data,
          r'Moving $1.00 from Bitcoin');
      _expectClearJourney(tester, dark: dark, reason: 'Yes ($theme)');
      await _close(tester);
    });

    testWidgets(
        'the money there, the venue confirming: the stage, then '
        'the venue\'s own step ($theme)', (tester) async {
      await _pump(tester, _yesSlip(),
          dark: dark, funded: [_fromBitcoin('yes', 'Yes', 1, at: 'confirm')]);
      expect(tester.widget<Text>(_titleText()).data,
          'Getting your prediction ready');
      expect(tester.widget<Text>(_detailText()).data, 'Confirming balance');
      _expectClearJourney(tester, dark: dark, reason: 'confirm ($theme)');
      await _close(tester);
    });

    testWidgets(
        'a Draw slip mid-journey: dark ink on the light game colour '
        '($theme)', (tester) async {
      await _pump(tester, _drawSlip(),
          dark: dark, funded: [_fromBitcoin('draw', 'Draw', 10)]);
      if (_dir case final dir?) {
        await writeViewPng(tester, '$dir/draw_journey_$theme.png');
      }
      _expectClearJourney(tester, dark: dark, reason: 'Draw ($theme)');
      await _close(tester);
    });

    for (final (name, slip, token, side, usd) in [
      ('Yes', _yesSlip, 'yes', 'Yes', 1.0),
      ('Draw', _drawSlip, 'draw', 'Draw', 10.0),
    ]) {
      testWidgets('$name at 320 pt, text x1.5: nothing cut ($theme)',
          (tester) async {
        await _pump(tester, slip(),
            dark: dark,
            width: 320,
            textScale: 1.5,
            funded: [_fromBitcoin(token, side, usd)]);
        if (_dir case final dir?) {
          await writeViewPng(
              tester, '$dir/${token}_journey_320_x1.5_$theme.png');
        }
        _expectNothingCut(tester, 320, '$name 320 x1.5 ($theme)');
        _expectClearJourney(tester,
            dark: dark, reason: '$name 320 x1.5 ($theme)');
        await _close(tester);
      });
    }
  }

  testWidgets('Reduce Motion: the journey holds still, the live dot steady',
      (tester) async {
    await _pump(tester, _yesSlip(),
        reduceMotion: true, funded: [_fromBitcoin('yes', 'Yes', 1)]);
    expect(_title, findsOneWidget);
    // Nothing on the slip asks for another frame.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await _close(tester);
  });
}

Finder _titleText() =>
    find.descendant(of: _title, matching: find.byType(Text)).last;
Finder _detailText() =>
    find.descendant(of: _detail, matching: find.byType(Text)).last;
