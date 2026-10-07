// The screen a prediction ends on when an earlier one on the account is
// still unaccounted for. It used to cut the message off after two lines
// ("...Check its status before ...") with nothing on it that checks.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/earlier_prediction_result.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/theme/app_theme.dart';

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.answers);
  final List<Object?> answers;
  var checks = 0;

  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState();

  @override
  Future<void> checkPendingOrder({String? tokenId}) async {
    final answer = answers[checks++];
    if (answer != null) throw answer;
  }
}

void main() {
  tearDown(() => KuteConfirmation.debugFeedbackOverride = null);
  final l10n = l10nForLanguage('en');

  Future<_Trading> trading(List<Object?> answers) async {
    final notifier = _Trading(answers);
    final container = ProviderContainer(
        overrides: [polymarketTradingProvider.overrideWith(() => notifier)]);
    addTearDown(container.dispose);
    await container.read(polymarketTradingProvider.future);
    return container.read(polymarketTradingProvider.notifier) as _Trading;
  }

  test('each answer of the check has its own line', () async {
    final t = await trading([
      null,
      const ResolvedPolymarketOrder(accepted: true),
      const PolymarketOrderCheckUnavailable(),
      const PolymarketOrderInProgress(),
      const PendingPolymarketOrder(),
    ]);
    Future<EarlierPredictionCheck> check() =>
        checkEarlierPrediction(t, '1', l10n);
    expect(await check(), (message: l10n.betPreviousOrderChecked, read: true));
    expect(await check(), (message: l10n.betPreviousOrderChecked, read: true));
    expect(
        await check(), (message: l10n.betConnectionUnavailable, read: false));
    expect(await check(), (message: l10n.betPreviousStillPlacing, read: false));
    expect(await check(), (message: l10n.ledgerBetPending, read: false));
  });

  testWidgets(
      'the unsettled answer wraps in full and offers the check, which '
      'shows what it found', (tester) async {
    KuteConfirmation.debugFeedbackOverride = () async {};
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var rechecks = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EarlierPredictionResult(
          message: l10n.ledgerBetPending,
          success: false,
          onDone: () {},
          recheck: () async {
            rechecks++;
            return (message: l10n.betPreviousOrderChecked, read: true);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final message = find.byKey(const ValueKey('kute-confirmation-message'));
    final text = tester.widget<Text>(message);
    expect(text.data, l10n.ledgerBetPending);
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    // Rendered whole: no line of it is cut off.
    final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: message, matching: find.byType(RichText)));
    expect(paragraph.didExceedMaxLines, isFalse);

    await tester.tap(find.text(l10n.ledgerBetCheckStatus));
    await tester.pumpAndSettle();
    expect(rechecks, 1);
    expect(find.text(l10n.betPreviousOrderChecked), findsOneWidget);
    // Settled: nothing left to check.
    expect(find.text(l10n.ledgerBetCheckStatus), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
