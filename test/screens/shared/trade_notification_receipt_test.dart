import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      'a results-inbox fill reads as a receipt: heading on top, short hash, '
      'copy and explorer', (tester) async {
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
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    var listed = 0;
    await _pump(
        tester,
        tradeNotificationConfirmation(l10n, _fill(),
            showWallet: false, onList: () => listed++));

    // The result is the heading, above the card; no mascot on a receipt.
    final heading = find.text('Prediction bought');
    expect(heading, findsOneWidget);
    expect(tester.getTopLeft(heading).dy,
        lessThan(tester.getTopLeft(find.byType(TradeReceipt)).dy));
    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);

    // Title wraps on its own; the outcome is the chip.
    expect(find.text('Bitcoin Up or Down - October 5, 5:50AM-5:55AM ET'),
        findsOneWidget);
    expect(find.text('Up'), findsOneWidget);

    // Plain rows at the Activity sheets' precision.
    expect(find.text(r'$3.07'), findsOneWidget);
    expect(find.text('4.53'), findsOneWidget);
    expect(find.text('67.7¢'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Filled'), findsNothing);
    expect(find.text('5 Oct 2026, 10:52'), findsOneWidget);
    // One wallet: no wallet row.
    expect(find.text('Main Dev'), findsNothing);

    // The hash: short, one line, full value copied.
    expect(find.text(_hash), findsNothing);
    final short = find.text('0x5301aa...39d672c3');
    expect(short, findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    await tester.tap(short);
    await tester.pump();
    expect(copied, _hash);
    expect(find.text('Copied to clipboard'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // The explorer: Polygonscan for a Polymarket fill; analytics carry the
    // chain, never the hash.
    await tester.tap(find.text('View on the blockchain'));
    await tester.pump();
    expect(opened, [Uri.parse('https://polygonscan.com/tx/$_hash')]);
    expect(events['block_explorer_opened'], containsPair('chain', 'polygon'));
    expect(events['block_explorer_opened'].toString(), isNot(contains(_hash)));

    // No open position: the list the receipt came from is the only button.
    await tester.tap(find.text('Activity'));
    expect(listed, 1);
    expect(find.text('View prediction'), findsNothing);
  });

  testWidgets('an open position leads with View prediction, Activity second',
      (tester) async {
    var viewed = 0, listed = 0;
    await _pump(
        tester,
        tradeNotificationConfirmation(l10n, _fill(),
            showWallet: true,
            onList: () => listed++,
            onViewPrediction: () => viewed++));
    expect(find.text('Main Dev'), findsOneWidget);
    await tester.tap(find.text('View prediction'));
    await tester.tap(find.text('Activity'));
    expect((viewed, listed), (1, 1));
  });

  testWidgets('an unread win still celebrates above the heading',
      (tester) async {
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
    expect(find.byType(KuteCheckMark), findsOneWidget);
    expect(tester.getTopLeft(find.byType(KuteCheckMark)).dy,
        lessThan(tester.getTopLeft(find.text('Prediction won')).dy));
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
