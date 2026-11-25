// The Predictions sell sheet carries the buy slips' one small Max beside
// the figure: it fills the whole position (every share), and restores that
// after the figure is edited. A position with nothing to sell has none.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:money2/money2.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/euro_settings.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/shell_bar_harness.dart';

class _FakeTrading extends PolymarketTradingNotifier {
  @override
  Future<void> refresh() async {}

  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => null;
}

PolymarketPosition _position({double size = 18.6}) => PolymarketPosition(
      marketId: 'condition',
      marketQuestion: 'Will the U.S. invade Iran before 2027?',
      outcome: 'Yes',
      size: size,
      avgPrice: 0.15,
      currentPrice: 0.15,
      pnl: 0,
      pnlPercent: 0,
      isResolved: false,
      tokenId: 'yes',
    );

Future<void> _pump(WidgetTester tester, PolymarketPosition position,
    {String? currency}) async {
  tester.view.physicalSize = const Size(430, 932) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // The bar over the sheet is the sheet's button (shell_bar_harness.dart).
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      polymarketTradingProvider.overrideWith(_FakeTrading.new),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      currencyProvider.overrideWith((_) => _Currency()),
      if (currency != null) ...[
        euroRateOverride(),
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: currency,
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true))),
      ],
    ],
    child: shellBarApp(
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
        extensions: [AppColorsExtension.light()],
      ),
      home: Scaffold(body: SellSheet(position: position)),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _close(WidgetTester tester) async {
  // Unmount so the sheet's book refresh timer stops.
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

String _typed(WidgetTester tester) =>
    tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay)).amountText;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('one small Max beside the figure sells the whole position',
      (tester) async {
    await _pump(tester, _position());
    final hero = find.byType(BigAmountDisplay);
    final max = find.descendant(of: hero, matching: find.byType(AmountMaxChip));
    expect(max, findsOneWidget);
    expect(_typed(tester), isEmpty);

    await tester.tap(find.bySemanticsLabel('Use maximum'));
    await tester.pump();
    // 18.6 shares at 15c.
    expect(_typed(tester), '2.79');
    expect(find.textContaining('18.60 shares'), findsWidgets);
    // The bar is the sheet's one button: it reads the sale (a frame after
    // the sheet declares it).
    await pumpBar(tester);
    expect(barPrimaryLabel(tester), 'Sell · \$2.79');
    expect(barPrimaryText('Sell · \$2.79'), findsOneWidget);
    expect(barPrimaryEnabled(tester), isTrue);

    // Edited down, Max brings the whole position back.
    final pad = find.byType(AmountKeypad);
    await tester.tap(find.descendant(
        of: pad, matching: find.byIcon(Icons.backspace_rounded)));
    await tester.pump();
    expect(_typed(tester), '2.7');
    await tester.tap(max);
    await tester.pump();
    expect(_typed(tester), '2.79');
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets(
      'euros in Settings: Max and a typed amount are dollars, the shares '
      'offered are the dollars over the price, no rate', (tester) async {
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
    expect(await policy.refresh(), isTrue);
    await _pump(tester, _position(), currency: 'EUR');
    final hero = find.byType(BigAmountDisplay);
    expect(tester.widget<BigAmountDisplay>(hero).prefix, r'$');
    await tester.tap(find.bySemanticsLabel('Use maximum'));
    await tester.pump();
    // 18.6 shares at 15c, as with dollars in Settings.
    expect(_typed(tester), '2.79');
    await pumpBar(tester);
    expect(barPrimaryLabel(tester), 'Sell · \$2.79');

    final pad = find.byType(AmountKeypad);
    final backspace = find.descendant(
        of: pad, matching: find.byIcon(Icons.backspace_rounded));
    for (var i = 0; i < 4; i++) {
      await tester.tap(backspace);
      await tester.pump();
    }
    await tester.tap(find.descendant(of: pad, matching: find.text('2')));
    await tester.pump();
    expect(_typed(tester), '2');
    await pumpBar(tester);
    expect(barPrimaryLabel(tester), 'Sell · \$2.00');
    expect(find.textContaining('€'), findsNothing);
    // The order's size, on Advanced: $2 at 15c is 13.33 shares (2 / 0.92
    // would be 14.49).
    await tester.tap(find.byKey(const ValueKey('slip-advanced-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('13.33 shares'), findsOneWidget);
    expect(find.textContaining('€'), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
    policy.dispose();
  });

  testWidgets(
      'a position in a crypto round IN PLAY past its cutoff still sells: '
      'buys there are closed (founder, 12 November 2026), exits always open',
      (tester) async {
    final now = DateTime.now();
    // Four minutes into a five-minute round: past its two-minute cutoff.
    final start = now.millisecondsSinceEpoch ~/ 1000 - 240;
    final slug = polyCryptoRoundSlug('btc', 5, start);
    expect(polyRoundBuyClosed(slug, now: now), isTrue,
        reason: 'the round is past its cutoff: no buy');
    await _pump(
        tester,
        PolymarketPosition(
          marketId: 'cur-cond',
          marketQuestion: 'Bitcoin Up or Down - November 12, 7:00AM-7:05AM ET',
          outcome: 'Up',
          size: 18.6,
          avgPrice: 0.15,
          currentPrice: 0.15,
          pnl: 0,
          pnlPercent: 0,
          isResolved: false,
          tokenId: 'cur-up',
          eventSlug: slug,
        ));
    await tester.tap(find.bySemanticsLabel('Use maximum'));
    await tester.pump();
    expect(_typed(tester), '2.79');
    await pumpBar(tester);
    expect(barPrimaryLabel(tester), 'Sell · \$2.79');
    expect(barPrimaryEnabled(tester), isTrue);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets('nothing to sell, no Max', (tester) async {
    await _pump(tester, _position(size: 0));
    expect(find.byType(AmountMaxChip), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });
}
