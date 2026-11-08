// EVERY RECEIPT SHARES (founder, 5 November 2026: "All these
// transactions, next to View on the blockchain, should have the share and
// a special share card"). Each transaction receipt's bar carries the round
// Sal button beside its primary (View on the blockchain, View market,
// Track this exchange; Done where it has none), and a tap opens the
// preview with that receipt's own card: SENT / RECEIVED / ON ITS WAY for
// bitcoin and dollars, MOVED, BOUGHT, I'M ON YES, CASHED OUT, NOT THIS
// TIME, the won brag card, an Investing trade. A failed transaction shares
// nothing. The card never carries a transaction id or an address. A won
// receipt has no "Brag about it" row (founder, 8 November 2026: a
// duplicate of the share): the round button is its way to the brag card.

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/prediction_results.dart' show PredictionResult;
import 'package:kute/models/outlogic_model.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usdb_provider.dart' show usdbTokenIdentifier;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_cards.dart' show ShareCard;
import 'package:kute/screens/share/receipt_share.dart';
import 'package:kute/screens/shared/hyperliquid_fill_activity.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart'
    show ShareCardShare;
import 'package:kute/services/mempool_address_service.dart'
    show MempoolTransaction;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/kute_bar_test_support.dart';
import 'receipt_fixtures.dart';

/// A dollar payment out of the spending account, failed.
UsdbTokenTransaction _failedDollarsSend() {
  final payment = breez.Payment(
    id: 'usd-send-failed',
    paymentType: breez.PaymentType.send,
    status: breez.PaymentStatus.failed,
    amount: BigInt.from(12000000),
    fees: BigInt.zero,
    timestamp: BigInt.from(receiptAt.millisecondsSinceEpoch ~/ 1000),
    method: breez.PaymentMethod.token,
    details: breez.PaymentDetails.token(
      metadata: breez.TokenMetadata(
        identifier: usdbTokenIdentifier,
        issuerPublicKey: 'issuer',
        name: 'USDB',
        ticker: 'USDB',
        decimals: 6,
        maxSupply: BigInt.zero,
        isFreezable: false,
      ),
      txHash: 'tx-usd-failed',
      txType: breez.TokenTransactionType.transfer,
    ),
  );
  return UsdbTokenTransaction(
      id: payment.id,
      timestamp: receiptAt,
      details: payment,
      isConfirmed: false);
}

/// $20 of dollars converted into ₿30,000 in the spending account, done;
/// [lightning]: paid to a Lightning invoice instead (a send from dollars).
SwapOrderTransaction _conversion(
    {String status = 'success', bool lightning = false}) {
  final row = SwapOrder(
    id: 'ord_conversion-1',
    coinFrom: 'USDB',
    networkFrom: 'SPARK',
    coinTo: 'BTC',
    networkTo: lightning ? 'LIGHTNING' : 'SPARK',
    depositAddress: 'spark-deposit-1',
    depositAmount: '20.00',
    withdrawalAmount: '0.00030000',
    status: status,
    timestamp: receiptAt.millisecondsSinceEpoch,
    withdrawalAddress: lightning ? 'lnbc1someone' : 'sp1self',
    depositMin: '0',
    depositMax: '0',
    rate: '0',
    refundAddress: '',
    provider: 'Orchestra',
    walletId: 'spending',
  );
  return SwapOrderTransaction(
      id: row.id, timestamp: receiptAt, isConfirmed: true, details: row);
}

/// A bank purchase of ₿60,000 for €50.00, [status] as Outlogic sent it.
OutlogicTransaction _bankBuy(String status) => OutlogicTransaction(
      id: 'outlogic-1',
      timestamp: receiptAt,
      isConfirmed: status == 'COMPLETED',
      details: OutlogicOrder(
        id: 'outlogic-1',
        status: status,
        email: 'me@example.com',
        depositCryptoAddress: '',
        fromAmount: 50,
        fromAsset: 'EUR',
        toAsset: 'BTC',
        destinationType: 'crypto',
        destinationCryptoAddress: 'bc1qmine',
        createdAt: '',
        depositSepaAddress: 'DE00 1234 5678',
        trade: OutlogicTrade(
          fromAmount: 50,
          fromAsset: 'EUR',
          toAmount: 0.0006,
          toAsset: 'BTC',
          feeAmount: 0.5,
          price: 82000,
          timestamp: '',
        ),
      ),
    );

/// A Predictions record that is not a trade: a deposit, a payout.
PolymarketTransaction _venueRecord(String type, double usdc) =>
    PolymarketTransaction(
      id: 'pm-$type',
      timestamp: receiptAt,
      activity: Activity(
        proxyWallet: '0xme',
        timestamp: receiptAt.millisecondsSinceEpoch ~/ 1000,
        conditionId: '0xpaid',
        type: type,
        size: usdc,
        usdcSize: usdc,
        price: null,
        transactionHash: receiptPolygonHash,
        side: null,
        asset: 'tok',
        outcomeIndex: 0,
        title: type == 'REDEEM' ? receiptMarket : null,
        outcome: type == 'REDEEM' ? 'Yes' : null,
        eventSlug: '',
      ),
    );

Activity _result(String outcome, {required bool won}) => Activity(
      proxyWallet: '0xme',
      timestamp: receiptAt.millisecondsSinceEpoch ~/ 1000,
      conditionId: '0xresult',
      type: 'REDEEM',
      size: 20,
      usdcSize: won ? 20 : 0,
      price: null,
      transactionHash: '',
      side: null,
      asset: 'tok',
      outcomeIndex: 0,
      title: receiptMarket,
      outcome: outcome,
      eventSlug: '',
    );

void main() {
  late Directory hive;
  setUpAll(() async => hive = await openReceiptHive());
  tearDownAll(() => closeReceiptHive(hive));

  final events = <(String, Map<String, Object>?)>[];
  setUp(() {
    events.clear();
    TrackingService.setDisabled(true);
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  late BuildContext opener;
  late WidgetRef openerRef;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester,
      {Widget? home, bool bar = false}) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    if (bar) {
      kuteShellMounted.value = true;
      addTearDown(() => kuteShellMounted.value = false);
    }
    // A fresh app: a receipt opened before is gone with its sheets.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(receiptApp(
      home ??
          Consumer(builder: (context, ref, _) {
            opener = context;
            openerRef = ref;
            return const SizedBox.expand();
          }),
      theme: buildLightTheme(),
      builder: bar ? withKuteShellBar : null,
      overrides: [
        swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
        sparkSelfAddressProvider.overrideWith((_) async => 'sp1self'),
      ],
    ));
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, BaseTransaction tx,
      {bool bar = false}) async {
    await pump(tester, bar: bar);
    await openTransactionDetails(opener, openerRef, tx);
    await settle(tester);
  }

  /// The row a won receipt wore under its tiles until 8 November 2026.
  void expectNoBragRow() {
    expect(find.text('Brag about it'), findsNothing);
    expect(find.text('A card with your result'), findsNothing);
  }

  /// The receipt's primary and its round share button.
  KuteBarShare shareOf(WidgetTester tester, {String? primary}) {
    final ctx = kuteBarPrimaryContext(tester);
    if (primary != null) expect(ctx.label, primary);
    final share = ctx.share;
    expect(share, isNotNull, reason: 'the round Sal button beside the bar');
    expect(share!.open, isNotNull);
    return share;
  }

  /// Taps the round button (through the context it declares) and returns
  /// the card the preview shows.
  Future<ReceiptCardData> tapShare(WidgetTester tester,
      {String? primary}) async {
    shareOf(tester, primary: primary).open!();
    await settle(tester);
    expect(find.byKey(const ValueKey('share-card-preview')), findsOneWidget);
    final card = tester.widget<ShareCard>(find.byType(ShareCard));
    expect(
        find.byKey(ValueKey('share-card-${card.data.kind}')), findsOneWidget);
    return card.data as ReceiptCardData;
  }

  testWidgets(
      'Lightning send: View on the blockchain, the round button, '
      'SENT in bitcoin', (tester) async {
    await open(tester, receiptLightningSend());
    final card = await tapShare(tester, primary: 'View on the blockchain');
    expect(card.type, ReceiptCardKind.sent);
    expect(card.asset, ReceiptCardAsset.bitcoin);
    expect(card.bitcoin, '₿2,100');
    expect(find.text('SENT'), findsOneWidget);
    // Never an id: no hash, invoice or payment id on the card.
    final texts = tester
        .widgetList<Text>(find.descendant(
            of: find.byType(ShareCard), matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .join(' ');
    expect(texts, isNot(contains(receiptLightningId)));
    expect(texts, isNot(contains('lnbc')));
  });

  testWidgets('on-chain receive: RECEIVED; unconfirmed, ON ITS WAY',
      (tester) async {
    await open(tester, receiptOnChainReceive());
    var card = await tapShare(tester, primary: 'View on the blockchain');
    expect(card.type, ReceiptCardKind.received);
    expect(card.bitcoin, '₿150,000');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));

    await open(tester, receiptOnChainReceive(confirmed: false));
    card = await tapShare(tester);
    expect(card.type, ReceiptCardKind.incoming);
    expect(find.text('ON ITS WAY'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets(
      'Dollars deposit: RECEIVED in dollars; a failed payment shares '
      'nothing', (tester) async {
    await open(tester, receiptDollarsDeposit());
    final card = await tapShare(tester, primary: 'View on the blockchain');
    expect(card.type, ReceiptCardKind.received);
    expect(card.asset, ReceiptCardAsset.dollars);
    expect(card.amount, r'$25.00');

    await open(tester, _failedDollarsSend());
    expect(kuteBarPrimaryContext(tester).label, 'View on the blockchain');
    expect(kuteBarPrimaryContext(tester).share, isNull);
  });

  testWidgets("prediction placed: I'M ON NO at the price paid, the stake",
      (tester) async {
    await open(tester, receiptPredictionBuy());
    // The buy has no chain hash in the fixture: Done is its primary.
    final card = await tapShare(tester, primary: 'Done');
    expect(card.type, ReceiptCardKind.predicted);
    expect(card.side, 'No');
    expect(card.chance, 0.357);
    expect(card.amount, r'$4.46');
    expect(card.title, receiptMarket);
    expect(find.text("I'M ON NO"), findsOneWidget);
    expect(find.byKey(const ValueKey('share-card-odds')), findsOneWidget);
  });

  testWidgets('prediction sold: CASHED OUT with the Result tile\'s figure',
      (tester) async {
    await open(tester, receiptPredictionSell());
    final card = await tapShare(tester, primary: 'View on the blockchain');
    expect(card.type, ReceiptCardKind.cashedOut);
    expect(card.amount, r'$4.37');
    expect(card.result, r'−$0.09');
    expect(card.pnl, closeTo(-0.09, 0.001));
    expect(find.text('CASHED OUT'), findsOneWidget);
  });

  testWidgets(
      'a lost prediction: NOT THIS TIME, the stake; a won one: the '
      'won brag card', (tester) async {
    await pump(tester);
    showPredictionResultDetails(
        opener,
        PredictionResult(
            activity: _result('Yes', won: false),
            won: false,
            stakeUsd: 8,
            payoutUsd: 0));
    await settle(tester);
    final lost = await tapShare(tester, primary: 'Done');
    expect(lost.type, ReceiptCardKind.lost);
    expect(lost.result, r'−$8.00');
    expect(find.text('NOT THIS TIME'), findsOneWidget);

    await pump(tester);
    showPredictionResultDetails(
        opener,
        PredictionResult(
            activity: _result('Yes', won: true),
            won: true,
            stakeUsd: 8,
            payoutUsd: 20));
    await settle(tester);
    expectNoBragRow();
    shareOf(tester, primary: 'Done').open!();
    await settle(tester);
    expect(find.byKey(const ValueKey('brag-preview-card')), findsOneWidget);
    expect(find.text('CALLED IT'), findsOneWidget);
  });

  testWidgets(
      'a won payout has no Brag about it row: the round button on the bar '
      'opens the won brag card', (tester) async {
    await open(tester, receiptPredictionWon(), bar: true);
    expectNoBragRow();
    expect(find.text('Won · Down'), findsOneWidget);
    final pill = find.byKey(const ValueKey('kute-bar-primary'));
    expect(
        find.descendant(
            of: pill, matching: find.text('View on the blockchain')),
        findsOneWidget);
    await tester.tap(find.descendant(
        of: pill, matching: find.byKey(const ValueKey('kute-bar-share'))));
    await settle(tester);
    expect(find.byKey(const ValueKey('brag-preview-card')), findsOneWidget);
    expect(find.text('Show off this win'), findsOneWidget);
    expect(find.text('CALLED IT'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-card-preview')), findsNothing);
  });

  testWidgets(
      'a win on a record with no market name still opens the won brag card, '
      'from both receipts', (tester) async {
    await open(tester, receiptPredictionWon(title: null));
    expectNoBragRow();
    shareOf(tester, primary: 'View on the blockchain').open!();
    await settle(tester);
    expect(find.byKey(const ValueKey('brag-preview-card')), findsOneWidget);

    await pump(tester);
    showPredictionResultDetails(
        opener,
        PredictionResult(
            activity: receiptPredictionWon(title: null).activity,
            won: true,
            stakeUsd: 3.88,
            payoutUsd: 5));
    await settle(tester);
    expectNoBragRow();
    shareOf(tester).open!();
    await settle(tester);
    expect(find.byKey(const ValueKey('brag-preview-card')), findsOneWidget);
  });

  testWidgets('Investing fill: Done on a Ledger account\'s, the trade card',
      (tester) async {
    await pump(tester,
        home: const HyperliquidFillActivityRow(fill: receiptInvestingReduce));
    await tester.tap(find.text('Reduced OAI'));
    await settle(tester);
    final card = await tapShare(tester, primary: 'Done');
    expect(card.type, ReceiptCardKind.closed);
    expect(card.side, 'long');
    expect(card.ticker, 'OAI');
    expect(card.size, '0.5 OAI');
    expect(card.price, r'$142.18');
    expect(card.result, r'−$0.03');
    expect(find.text('CLOSED POSITION · LONG'), findsOneWidget);
  });

  testWidgets(
      'a conversion into bitcoin, the person\'s own money: Track this '
      'exchange, MOVED, never BOUGHT; an expired one shares nothing',
      (tester) async {
    await open(tester, _conversion());
    final card = await tapShare(tester, primary: 'Track this exchange');
    expect(card.type, ReceiptCardKind.moved);
    expect(card.to, 'Bitcoin');
    expect(card.amount, r'$20.00');
    expect(card.bitcoin, '₿30,000');

    // Dollars paid to someone's Lightning invoice: SENT, in dollars.
    await open(tester, _conversion(lightning: true));
    final send = await tapShare(tester, primary: 'Track this exchange');
    expect(send.type, ReceiptCardKind.sent);
    expect(send.asset, ReceiptCardAsset.dollars);
    expect(send.amount, r'$20.00');

    await open(tester, _conversion(status: 'expired'));
    final primaries = find
        .byWidgetPredicate(
            (w) => w is KuteBarContextScope && w.barContext.isPrimary)
        .evaluate()
        .map((e) => (e.widget as KuteBarContextScope).barContext);
    expect(primaries.every((c) => c.share == null), isTrue);
  });

  testWidgets('USDC received into Predictions: RECEIVED in dollars',
      (tester) async {
    await open(
        tester,
        PolymarketUsdcReceive(
          id: '0xabc:1',
          timestamp: receiptAt,
          isConfirmed: true,
          fromAddress: '0xsender',
          tokenAddress: '0x3c499c542cef5e3811e1192ce70d8cc03d5c3359',
          rawAmount: BigInt.from(15000000),
          blockNumber: 1,
        ));
    final card = await tapShare(tester, primary: 'View on the blockchain');
    expect(card.type, ReceiptCardKind.received);
    expect(card.asset, ReceiptCardAsset.dollars);
    expect(card.amount, r'$15.00');
  });

  testWidgets(
      'a bank purchase done: Done and BOUGHT · BITCOIN in its own '
      'currency; still waiting for the transfer: no share', (tester) async {
    await open(tester, _bankBuy('COMPLETED'));
    final card = await tapShare(tester, primary: 'Done');
    expect(card.type, ReceiptCardKind.bought);
    expect(card.amount, '€50.00');
    expect(card.bitcoin, '₿60,000');
    expect(find.text('BOUGHT · BITCOIN'), findsOneWidget);
    // The order's IBAN never reaches the card.
    expect(
        find.descendant(
            of: find.byType(ShareCard), matching: find.textContaining('DE00')),
        findsNothing);

    await open(tester, _bankBuy('WAITING_FOR_DEPOSIT'));
    expect(
        find.byWidgetPredicate(
            (w) => w is KuteBarContextScope && w.barContext.isPrimary),
        findsNothing);
  });

  testWidgets(
      'Predictions deposit: MOVED, your wallet → Predictions; a '
      'payout with no cost known: PAID OUT', (tester) async {
    await open(tester, _venueRecord('DEPOSIT', 20));
    var card = await tapShare(tester, primary: 'View on the blockchain');
    expect(card.type, ReceiptCardKind.moved);
    expect(card.from, 'Your wallet');
    expect(card.to, 'Predictions');

    await open(tester, _venueRecord('REDEEM', 30));
    card = await tapShare(tester, primary: 'View on the blockchain');
    expect(card.type, ReceiptCardKind.paidOut);
    expect(card.result, r'+$30.00');
  });

  testWidgets('a deposit on its way in: ON ITS WAY in bitcoin', (tester) async {
    await open(
        tester,
        SparkPendingDeposit(
          id: 'spark_pending_abc',
          timestamp: receiptAt,
          confirmations: 3,
          claimInProgress: true,
          mempoolTx: MempoolTransaction(
              txid: receiptOnChainTxid,
              confirmed: true,
              fee: 0,
              balanceChange: 50000),
        ));
    final card = await tapShare(tester, primary: 'View on the blockchain');
    expect(card.type, ReceiptCardKind.incoming);
    expect(card.bitcoin, '₿50,000');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a dollar transfer on Polygon: SENT in dollars', (tester) async {
    final row = SwapOrder(
      id: 'native-1',
      coinFrom: 'USDC',
      networkFrom: 'POLYGON',
      coinTo: 'USDC',
      networkTo: 'POLYGON',
      depositAddress: '0xfrom',
      depositAmount: '12.50',
      withdrawalAmount: '12.50',
      status: 'success',
      timestamp: receiptAt.millisecondsSinceEpoch,
      withdrawalAddress: '0xfriend',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Native',
      walletId: 'spending',
    );
    final tx = SwapOrderTransaction(
        id: row.id, timestamp: receiptAt, isConfirmed: true, details: row);
    // Its row opens the transfer's own receipt (Polygonscan).
    await pump(tester,
        home: Consumer(
            builder: (context, ref, _) =>
                buildUnifiedTransactionItem(tx, context, ref)));
    await tester.tap(find.text('Sent'));
    await settle(tester);
    var card = await tapShare(tester, primary: 'View on the blockchain');
    expect(card.type, ReceiptCardKind.sent);
    expect(card.amount, r'$12.50');
    // Opened as a swap order's receipt, the same card.
    await open(tester, tx);
    card = await tapShare(tester, primary: 'Done');
    expect(card.type, ReceiptCardKind.sent);
  });

  testWidgets(
      'the round Sal button floats beside the primary pill; a tap opens the '
      'preview, Share reports receipt_card_shared', (tester) async {
    await open(tester, receiptLightningSend(), bar: true);
    final pill = find.byKey(const ValueKey('kute-bar-primary'));
    expect(pill, findsOneWidget);
    final button = find.descendant(
        of: pill, matching: find.byKey(const ValueKey('kute-bar-share')));
    expect(button, findsOneWidget);
    expect(
        find.descendant(
            of: pill, matching: find.text('View on the blockchain')),
        findsOneWidget);
    // At the pill's right.
    expect(tester.getCenter(button).dx,
        greaterThan(tester.getCenter(find.text('View on the blockchain')).dx));
    await tester.tap(button);
    await settle(tester);
    expect(
        find.byKey(const ValueKey('share-card-receipt_sent')), findsOneWidget);
    // The preview's own bar: Share, handing the OS the PNG.
    final sent = <String>[];
    ShareCardShare.debugSharer = (image, text) async {
      sent.add(image.name);
      return 'success';
    };
    addTearDown(() => ShareCardShare.debugSharer = null);
    final share = kuteBarPrimaryContext(tester);
    expect(share.label, 'Share');
    share.onPrimary!();
    for (var i = 0; i < 50 && sent.isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(sent, hasLength(1));
    expect(
        events.where((e) => e.$1 == 'receipt_card_shared').map((e) => e.$2), [
      {'card': 'receipt_sent', 'result': 'success'}
    ]);
  });

  test('the share message: a market\'s link with the code, else the invite',
      () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
        receiptShareText(
            l10n,
            const ReceiptCardData(
                type: ReceiptCardKind.predicted,
                asset: ReceiptCardAsset.predictions,
                title: 'Will it rain?',
                link: 'https://backend.kutewallet.com/m/predictions/rain',
                referralCode: 'JOAO42')),
        'Will it rain? on Kute '
        'https://backend.kutewallet.com/m/predictions/rain?ref=JOAO42');
    expect(
        receiptShareText(
            l10n,
            const ReceiptCardData(
                type: ReceiptCardKind.sent,
                asset: ReceiptCardAsset.bitcoin,
                referralCode: 'JOAO42')),
        contains('JOAO42'));
    expect(
        receiptShareText(
            l10n,
            const ReceiptCardData(
                type: ReceiptCardKind.sent, asset: ReceiptCardAsset.bitcoin)),
        '');
  });
}
