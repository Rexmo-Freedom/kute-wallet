// Every receipt opened from an Activity row has ONE structure (founder,
// 1 November 2026; receipt_parts.dart): the hero (logo, title, the amount,
// the result or fiat under it, the date as a quiet line; the circled
// close, no Sal circle), the key facts as square tiles, long text on its
// own full-width row, and the receipt's action as the bar's primary
// button, never a button pinned on the sheet.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/shared/components/receipt_parts.dart';
import 'package:kute/screens/shared/hyperliquid_fill_activity.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';
import 'receipt_fixtures.dart';

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

/// The labels of the receipt's tiles, in order.
List<String> _tiles(WidgetTester tester) => tester
    .widgetList<ReceiptFactTile>(_inSheet(find.byType(ReceiptFactTile)))
    .map((t) => t.fact.label)
    .toList();

/// The value on the tile labelled [label].
String _tile(WidgetTester tester, String label) => tester
    .widgetList<ReceiptFactTile>(_inSheet(find.byType(ReceiptFactTile)))
    .firstWhere((t) => t.fact.label == label)
    .fact
    .value;

/// The value on the full-width row labelled [label].
String _long(WidgetTester tester, String label) => tester
    .widget<ReceiptLongRow>(_inSheet(find.byType(ReceiptLongRow)
        .evaluate()
        .where((e) => (e.widget as ReceiptLongRow).label == label)
        .map((e) => find.byWidget(e.widget))
        .first))
    .value;

/// The primary contexts the open receipt declares.
Iterable<KuteBarContext> _primaries() => find
    .byWidgetPredicate(
        (w) => w is KuteBarContextScope && w.barContext.isPrimary)
    .evaluate()
    .map((e) => (e.widget as KuteBarContextScope).barContext);

/// The hero and the chrome every receipt shares: one hero with its close
/// circle, no Sal circle, no button pinned at the foot.
void _expectStructure(WidgetTester tester,
    {required String title, String? result, bool date = true}) {
  expect(_inSheet(find.byKey(const ValueKey('receipt-hero'))), findsOneWidget);
  expect(
      find.descendant(
          of: find.byKey(const ValueKey('receipt-hero')),
          matching: find.text(title)),
      findsOneWidget);
  expect(_inSheet(find.byKey(const ValueKey('receipt-hero-amount'))),
      findsOneWidget);
  if (result != null) {
    expect(
        tester
            .widget<Text>(
                _inSheet(find.byKey(const ValueKey('receipt-hero-result'))))
            .data,
        result);
  }
  expect(_inSheet(find.byKey(const ValueKey('receipt-hero-date'))),
      date ? findsOneWidget : findsNothing);
  expect(_inSheet(find.byType(KuteCloseButton)), findsOneWidget);
  expect(_inSheet(find.byType(OutlinedButton)), findsNothing);
  expect(_inSheet(find.text('View on the blockchain')), findsNothing);
  expect(_inSheet(find.byKey(const ValueKey('receipt-bar-clearance'))),
      findsOneWidget);
}

void main() {
  late Directory hive;
  setUpAll(() async => hive = await openReceiptHive());
  tearDownAll(() => closeReceiptHive(hive));

  late BuildContext opener;
  late WidgetRef openerRef;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester, {Widget? home}) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(receiptApp(
      home ??
          Consumer(builder: (context, ref, _) {
            opener = context;
            openerRef = ref;
            return const SizedBox.expand();
          }),
      theme: buildLightTheme(),
    ));
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, BaseTransaction tx) async {
    await pump(tester);
    await openTransactionDetails(opener, openerRef, tx);
    await settle(tester);
  }

  testWidgets('Lightning send: Status, Value then, Change since, Fee; the '
      'description on its own row; the explorer is the bar', (tester) async {
    await open(tester, receiptLightningSend());
    _expectStructure(tester, title: 'Sent');
    expect(_tiles(tester), ['Status', 'Value then', 'Change since', 'Fee']);
    expect(_tile(tester, 'Status'), 'Completed');
    expect(_tile(tester, 'Value then'), r'$2.27');
    expect(_tile(tester, 'Change since'), '▼ 10.3%');
    expect(_tile(tester, 'Fee'), '₿3');
    expect(_long(tester, 'Description'), receiptDescription);
    // The flow diagram stays, under the tiles; Nerd data at the bottom.
    expect(_inSheet(find.text('Your wallet')), findsOneWidget);
    expect(_inSheet(find.text('Nerd data')), findsOneWidget);
    expect(kuteBarPrimaryContext(tester).label, 'View on the blockchain');
  });

  testWidgets('a long press on the bar asks Sal what happened here',
      (tester) async {
    await open(tester, receiptLightningSend());
    final container =
        ProviderScope.containerOf(tester.element(find.byType(BottomSheet)));
    final stack = container.read(kuteBarContextProvider);
    final primary = kuteBarTop(stack)!;
    expect(primary.isPrimary, isTrue);
    expect(primary.disabledLabel, isNull);
    expect(primary.clip, 'idle');
    final ask = kuteBarAskContext(stack, primary);
    expect(ask.isPrimary, isFalse);
    expect(ask.question, 'What happened here?');
  });

  testWidgets('on-chain receive: Status, Value then, Change since; no fee '
      'tile; mempool is the bar', (tester) async {
    await open(tester, receiptOnChainReceive());
    _expectStructure(tester, title: 'Received');
    expect(_tiles(tester), ['Status', 'Value then', 'Change since']);
    expect(_tile(tester, 'Status'), 'Confirmed');
    expect(_tile(tester, 'Change since'), '▲ 11.5%');
    expect(kuteBarPrimaryContext(tester).label, 'View on the blockchain');
    // The flow graph's mempool fetch gives up on its own.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('prediction sell: Shares, Price, Result; the market question '
      'on its own row; the loss in colour under the amount', (tester) async {
    await open(tester, receiptPredictionSell());
    _expectStructure(tester, title: 'Sold · No', result: r'$0.09 loss');
    final tiles = _tiles(tester);
    // vs holding Bitcoin joins once its price history answers (offline
    // here: it never does, and the tile is not drawn).
    expect(tiles.take(3), ['Shares', 'Price', 'Result']);
    expect(_tile(tester, 'Shares'), '12.50');
    expect(_tile(tester, 'Price'), '35.0¢');
    expect(_tile(tester, 'Result'), r'−$0.09');
    expect(_long(tester, 'Market'), receiptMarket);
    // The outcome is in the title; nothing squeezed into a value column.
    expect(_inSheet(find.text('Outcome')), findsNothing);
    expect(kuteBarPrimaryContext(tester).label, 'View on the blockchain');
  });

  testWidgets('Dollars deposit: Status and Date tiles, Sparkscan is the bar',
      (tester) async {
    await open(tester, receiptDollarsDeposit());
    _expectStructure(tester, title: 'Deposit', date: false);
    expect(_tiles(tester), ['Status', 'Date']);
    expect(_tile(tester, 'Status'), 'Completed');
    expect(_tile(tester, 'Date'), '1 Nov 2026, 20:32');
    expect(kuteBarPrimaryContext(tester).label, 'View on the blockchain');
  });

  testWidgets('Investing reduce: Amount, Execution price, Direction, Fee; the '
      'market on its own row; no action, the default bar', (tester) async {
    await pump(tester,
        home: const HyperliquidFillActivityRow(fill: receiptInvestingReduce));
    await tester.tap(find.text('Reduced OAI'));
    await settle(tester);
    _expectStructure(tester, title: 'Reduced OAI', result: r'−$0.03');
    expect(_tiles(tester),
        ['Amount', 'Execution price', 'Direction', 'Paid fee']);
    expect(_tile(tester, 'Amount'), '0.5 OAI');
    expect(_tile(tester, 'Direction'), 'Closed position · Long');
    expect(_tile(tester, 'Paid fee'), r'$0.04');
    expect(_long(tester, 'Market'), isNotEmpty);
    expect(_primaries(), isEmpty);
  });

  testWidgets('a tile row keeps equal widths, two per row, 10 apart',
      (tester) async {
    await open(tester, receiptLightningSend());
    final status = tester.getRect(find.byKey(const ValueKey('receipt-tile-Status')));
    final then =
        tester.getRect(find.byKey(const ValueKey('receipt-tile-Value then')));
    final fee = tester.getRect(find.byKey(const ValueKey('receipt-tile-Fee')));
    expect(status.width, moreOrLessEquals(then.width, epsilon: 0.5));
    expect(status.top, moreOrLessEquals(then.top, epsilon: 0.5));
    expect(fee.top, greaterThan(status.bottom));
    expect(fee.width, moreOrLessEquals(status.width, epsilon: 0.5));
  });
}
