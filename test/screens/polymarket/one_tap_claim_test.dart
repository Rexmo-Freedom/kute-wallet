// Claiming a resolved prediction is one tap: the Claim button where the win
// is shown runs the redeem and ends on the claim confirmation, with no
// review page ("You won ... Claim $4.53") in between. A second tap while
// the first claim is in flight sends nothing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/claim_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/position_claim.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/theme/app_theme.dart';

class _FakeTrading extends PolymarketTradingNotifier {
  final redeemed = <String>[];
  Completer<double?>? hold;
  Object? failWith;
  int refreshes = 0;

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();

  @override
  Future<double?> redeemPosition({
    required String conditionId,
    List<int> indexSets = const [1, 2],
    String? trigger,
    String? surface,
    bool reportFailure = true,
  }) async {
    redeemed.add(conditionId);
    final failure = failWith;
    if (failure != null) throw failure;
    final pending = hold;
    if (pending != null) return pending.future;
    return 4.53;
  }
}

PolymarketPosition _resolved({bool won = true}) => PolymarketPosition(
      marketId: 'condition',
      marketQuestion: 'Bitcoin Up or Down - October 5, 5:50AM-5:55AM ET',
      outcome: 'Up',
      size: 4.53,
      avgPrice: 0.66,
      currentPrice: won ? 1 : 0,
      pnl: 1.54,
      pnlPercent: 51.4,
      isResolved: true,
      won: won,
      tokenId: 'up',
    );

Future<_FakeTrading> _pump(WidgetTester tester, Widget button) async {
  final trading = _FakeTrading();
  await tester.pumpWidget(ProviderScope(
    overrides: [polymarketTradingProvider.overrideWith(() => trading)],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: button)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return trading;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteConfirmation.debugFeedbackOverride = () async {};
  });
  tearDown(() => KuteConfirmation.debugFeedbackOverride = null);

  testWidgets('the card\'s Claim runs the claim and lands on the confirmation',
      (tester) async {
    final trading = await _pump(
        tester,
        PolyClaimButton(
            position: _resolved(), surface: 'portfolio_card', compact: true));
    expect(find.text(r'Claim $4.53'), findsOneWidget);

    await tester.tap(find.text(r'Claim $4.53'));
    await tester.pumpAndSettle();

    expect(trading.redeemed, ['condition']);
    // Straight to the confirmation: no review page, no sell sheet.
    expect(find.byType(ClaimPlacedOverlay), findsOneWidget);
    expect(find.byType(SellSheet), findsNothing);
    expect(find.text('You won'), findsNothing);
    // The one line the review page added is on the receipt.
    expect(find.text('Network fee'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second tap while the claim is in flight sends nothing',
      (tester) async {
    final trading = await _pump(
        tester,
        PolyClaimButton(
            position: _resolved(), surface: 'portfolio_card', compact: true));
    trading.hold = Completer<double?>();

    await tester.tap(find.text(r'Claim $4.53'));
    await tester.pump();
    // The button is loading (disabled); tapping where it is does nothing.
    await tester.tap(find.byType(PolyClaimButton), warnIfMissed: false);
    await tester.pump();
    expect(trading.redeemed, ['condition']);

    trading.hold!.complete(4.53);
    await tester.pumpAndSettle();
    expect(trading.redeemed, ['condition']);
    expect(find.byType(ClaimPlacedOverlay), findsOneWidget);
  });

  testWidgets(
      'a claim before the result is on chain says so, not "not completed"',
      (tester) async {
    final trading = await _pump(
        tester,
        PolyClaimButton(
            position: _resolved(), surface: 'portfolio_card', compact: true));
    trading.failWith = const PolymarketResultNotOnChainException();

    await tester.tap(find.text(r'Claim $4.53'));
    await tester.pump();

    expect(
        find.text('Polymarket is still recording this result. Your \$4.53 '
            'will be ready to claim in a few minutes.'),
        findsOneWidget);
    expect(find.textContaining('did not complete'), findsNothing);
    expect(find.byType(ClaimPlacedOverlay), findsNothing);
    // The card is read again, so it goes back to waiting for the result.
    expect(trading.refreshes, 1);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('a claim of shares already sold says so, and sends nothing more',
      (tester) async {
    final trading = await _pump(
        tester,
        PolyClaimButton(
            position: _resolved(), surface: 'portfolio_card', compact: true));
    trading.failWith = const PolymarketNothingToClaimException();

    await tester.tap(find.text(r'Claim $4.53'));
    await tester.pump();

    expect(
        find.text('Already sold or claimed. Nothing is left to claim on '
            'this prediction.'),
        findsOneWidget);
    expect(find.textContaining('did not complete'), findsNothing);
    expect(find.byType(ClaimPlacedOverlay), findsNothing);
    expect(trading.refreshes, 1);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('a lost side clears in one tap', (tester) async {
    final trading = await _pump(
        tester,
        PolyClaimButton(
            position: _resolved(won: false), surface: 'position_detail'));
    expect(find.text('Clear position'), findsOneWidget);

    await tester.tap(find.text('Clear position'));
    await tester.pumpAndSettle();

    expect(trading.redeemed, ['condition']);
    expect(find.byType(KuteConfirmation), findsOneWidget);
    expect(find.byType(ClaimPlacedOverlay), findsNothing);
  });

  testWidgets('a resolved position never opens the sell sheet', (tester) async {
    await _pump(
        tester,
        Builder(
            builder: (context) => TextButton(
                onPressed: () => SellSheet.show(context, position: _resolved()),
                child: const Text('sell'))));
    await tester.tap(find.text('sell'));
    await tester.pumpAndSettle();
    expect(find.byType(SellSheet), findsNothing);
  });
}
