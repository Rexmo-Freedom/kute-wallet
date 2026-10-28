import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/trade_notification_receipt.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/services/trade_notification_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

const _hash =
    '0x5301aac64f2cee18afee2da0bc9f100dced88f8996034de893db5b7439d672c3';

TradeNotification _fill({bool read = true}) => TradeNotification(
      id: 'pm-fill:0xabc:$_hash:123:0:BUY',
      account: '0xabc',
      product: 'predictions',
      title: 'Prediction bought',
      subtitle: 'Bitcoin Up or Down - October 5, 5:50AM-5:55AM ET · Up',
      time: DateTime(2026, 10, 5, 10, 52).millisecondsSinceEpoch,
      walletId: 'w1',
      walletName: 'Main Dev',
      read: read,
      rows: const {
        'Bought': r'$3.07',
        'Wallet': 'Main Dev',
        'Shares': '4.5303',
        'Average fill price': '67.70¢',
        'Status': 'Filled',
        'Transaction': _hash,
      },
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: buildLightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l10n = AppLocalizationsEn();
  // The app has these from the Material localizations by the time a
  // receipt opens; here the receipt is built before the first pump.
  setUpAll(() => initializeDateFormatting('en'));

  testWidgets(
      'a results-inbox fill reads as the result sheet: the title, the amount '
      'as the hero, the market, at most four rows and the explorer',
      (tester) async {
    final opened = <Uri>[];
    final events = <String, Map<String, Object>?>{};
    TradeReceiptTransaction.debugLaunchOverride = (uri) async {
      opened.add(uri);
    };
    TrackingService.debugTrackObserver = (e, p) => events[e] = p;
    addTearDown(() {
      TradeReceiptTransaction.debugLaunchOverride = null;
      TrackingService.debugTrackObserver = null;
    });

    var listed = 0, done = 0;
    await _pump(
        tester,
        tradeNotificationConfirmation(l10n, _fill(),
            showWallet: false, onList: () => listed++, onDone: () => done++));

    // The result is the title; a read receipt is neutral (no check).
    expect(find.text('Prediction bought'), findsOneWidget);
    expect(
        tester
            .widget<KuteStatusMark>(find.byType(KuteStatusMark))
            .tone,
        KuteConfirmationTone.neutral);

    // The amount is the hero; the outcome and market are the context.
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('kute-confirmation-amount')))
            .data,
        r'$3.07');
    expect(
        find.text('Up · Bitcoin Up or Down - October 5, 5:50AM-5:55AM ET'),
        findsOneWidget);

    // Plain rows at the Activity sheets' precision; a fill's status says
    // nothing more, and one wallet gets no wallet row.
    expect(find.text('4.53'), findsOneWidget);
    expect(find.text('67.7¢'), findsOneWidget);
    expect(find.text('Filled'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    expect(find.text('5 Oct 2026, 10:52'), findsOneWidget);
    expect(find.text('Main Dev'), findsNothing);

    // The hash is never shown; the transaction is a row action.
    expect(find.text(_hash), findsNothing);

    // The explorer: Polygonscan for a Polymarket fill; analytics carry the
    // chain, never the hash.
    await tester.tap(find.text('View on the blockchain'));
    await tester.pump();
    expect(opened, [Uri.parse('https://polygonscan.com/tx/$_hash')]);
    expect(events['block_explorer_opened'], containsPair('chain', 'polygon'));
    expect(events['block_explorer_opened'].toString(), isNot(contains(_hash)));

    // No open position: Done, and the list the receipt came from as the
    // one quiet button.
    expect(find.text('View prediction'), findsNothing);
    await tester.tap(find.text('Activity'));
    await tester.pump();
    expect(listed, 1);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(done, 1);
  });

  testWidgets(
      'an open position offers View prediction as the quiet button, and '
      'several wallets add the wallet row within four', (tester) async {
    var viewed = 0, listed = 0;
    await _pump(
        tester,
        tradeNotificationConfirmation(l10n, _fill(),
            showWallet: true,
            onList: () => listed++,
            onViewPrediction: () => viewed++));
    expect(find.text('Main Dev'), findsOneWidget);
    expect(find.text('5 Oct 2026, 10:52'), findsOneWidget);
    expect(find.text('Activity'), findsNothing);
    await tester.tap(find.text('View prediction'));
    await tester.pump();
    expect((viewed, listed), (1, 0));
  });

  testWidgets('an unread win celebrates in gold', (tester) async {
    KuteConfirmation.debugFeedbackOverride = () async {};
    addTearDown(() => KuteConfirmation.debugFeedbackOverride = null);
    final won = TradeNotification(
      id: 'pm:0xabc:123:1',
      account: '0xabc',
      product: 'predictions',
      title: 'Prediction won',
      subtitle: 'Portugal to win the final · Yes',
      time: DateTime(2026, 10, 5).millisecondsSinceEpoch,
      positive: true,
      rows: const {'Settlement payout': r'$18.00'},
    );
    await _pump(
        tester,
        tradeNotificationConfirmation(l10n, won,
            showWallet: false, onList: () {}));
    expect(
        tester
            .widget<KuteStatusMark>(find.byType(KuteStatusMark))
            .tone,
        KuteConfirmationTone.celebrate);
    expect(find.text(r'$18.00'), findsOneWidget);
    expect(find.text('Positions'), findsOneWidget);
    // No hash stored: no transaction row.
    expect(find.text('View on the blockchain'), findsNothing);
  });

  test('Hyperliquid hashes open the Hyperliquid explorer', () {
    expect(TradeReceiptTransaction.hyperliquid(_hash)!.explorerUri.toString(),
        'https://app.hyperliquid.xyz/explorer/tx/$_hash');
    expect(TradeReceiptTransaction.hyperliquid('0x${'0' * 64}'), isNull);
    expect(TradeReceiptTransaction.polygon('not a hash'), isNull);
  });
}
