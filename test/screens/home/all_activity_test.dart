// The Bitcoin home's Activity shows everything the spending account did
// (founder, 1 November 2026): bitcoin sends and receives, the Dollars
// ledger and the Investments activity the Portfolio's Activity used to
// list (Investing fills, Predictions bets, venue moves), merged by time,
// the newest eight on the home; "See all" lists them all on one screen.

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:hive_ce/hive.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/activity/activity_history_screen.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/shared/all_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show ActivityDaySection, assembleActivityRows;
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../../helpers/portfolio_overrides.dart';

final _t0 = DateTime.utc(2026, 10, 5, 12);
const _self = 'sp1self';

SwapOrderTransaction _swap(String id,
        {required String coinFrom,
        required String networkFrom,
        required String coinTo,
        required String networkTo,
        required DateTime at,
        String depositAmount = '10',
        String withdrawalAmount = '10'}) =>
    SwapOrderTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: SwapOrder(
        id: id,
        coinFrom: coinFrom,
        networkFrom: networkFrom,
        coinTo: coinTo,
        networkTo: networkTo,
        depositAddress: 'deposit-$id',
        depositAmount: depositAmount,
        withdrawalAmount: withdrawalAmount,
        status: 'success',
        timestamp: at.millisecondsSinceEpoch,
        withdrawalAddress: networkTo == 'SPARK' ? _self : '0xvenue',
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: 'spending',
      ),
    );

UsdbTokenTransaction _dollars(String id,
        {required double usd,
        required breez.PaymentType type,
        required DateTime at}) =>
    UsdbTokenTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: breez.Payment(
        id: id,
        paymentType: type,
        status: breez.PaymentStatus.completed,
        amount: BigInt.from((usd * 1e6).round()),
        fees: BigInt.zero,
        timestamp: BigInt.from(at.millisecondsSinceEpoch ~/ 1000),
        method: breez.PaymentMethod.token,
        details: breez.PaymentDetails.token(
          metadata: breez.TokenMetadata(
            identifier: 'btkn1usdb',
            issuerPublicKey: 'issuer',
            name: 'USDB',
            ticker: 'USDB',
            decimals: 6,
            maxSupply: BigInt.zero,
            isFreezable: false,
          ),
          txHash: 'tx-$id',
          txType: breez.TokenTransactionType.transfer,
        ),
      ),
    );

SparkTransaction _spark(String id, int sats, DateTime at,
        {TransactionType direction = TransactionType.received}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at,
      isConfirmed: true,
      amountSats: sats,
      sparkType: SparkTransactionType.spark,
      direction: direction,
      pending: false,
    );

PolymarketTransaction _bet(String id, DateTime at) => PolymarketTransaction(
      id: id,
      timestamp: at,
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: at.millisecondsSinceEpoch ~/ 1000,
        conditionId: '0xrain',
        type: 'TRADE',
        size: 10,
        usdcSize: 5,
        transactionHash: '0x$id',
        side: 'BUY',
        asset: 'yes',
        outcomeIndex: 0,
        title: 'Will it rain tomorrow?',
        outcome: 'Yes',
        eventSlug: '',
      ),
    );

HlFill _fill(DateTime at, {int oid = 1}) => HlFill(
      coin: 'BTC',
      px: 60000,
      sz: 0.01,
      side: 'B',
      time: at.millisecondsSinceEpoch,
      closedPnl: 0,
      fee: 0.1,
      feeToken: 'USDC',
      oid: oid,
      hash: '0xfill$oid',
      dir: 'Open Long',
      cloid: null,
    );

const _kinds = {
  'to_hl': SwapActivityKind.investingDeposit,
  'buy': SwapActivityKind.dollarWithdrawal,
};

List<String?> _ids(List<AllActivityEntry> e) =>
    [for (final x in e) x.tx?.id ?? 'fill:${x.fill!.oid}'];

void main() {
  // The rows' fiat lookup reads the cached rates box.
  late Directory hiveDir;
  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('all_activity_test');
    Hive.init(hiveDir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OwnSparkArrivals.reset();
  });

  group('the merged list', () {
    test('every account\'s rows, the bets and the fills, newest first', () {
      final rx = _spark('rx', 5000, _t0);
      final dep = _dollars('dep',
          usd: 20,
          type: breez.PaymentType.receive,
          at: _t0.add(const Duration(minutes: 10)));
      final bet = _bet('bet', _t0.add(const Duration(minutes: 20)));
      final fill = _fill(_t0.add(const Duration(minutes: 30)));
      final entries = mergeAllActivity(
          walletRows: [dep, rx], bets: [bet, bet], fills: [fill]);
      expect(_ids(entries), ['fill:1', 'bet', 'dep', 'rx']);
    });

    test('a deposit waiting on the person leads, whenever it arrived', () {
      final waiting = SparkUnclaimedDeposit.fromCache(
        id: 'dep_wait',
        timestamp: _t0,
        txid: 'tx_wait',
        vout: 0,
        amountSats: 30000,
        isMature: true,
        hasClaimError: true,
      );
      expect(waiting.needsAction, isTrue);
      final rx = _spark('rx', 5000, _t0.add(const Duration(hours: 1)));
      final entries = mergeAllActivity(walletRows: [rx, waiting]);
      expect(_ids(entries), ['dep_wait', 'rx']);
    });

    test('every account at once: one row per action, legs folded in', () {
      // A bitcoin receive from a friend, a dollar deposit, dollars into
      // Investing (its token transfer is its leg) and a purchase of
      // bitcoin from Dollars (its token send and its Spark receive are
      // legs).
      final friend = _spark('rx_friend', 50000, _t0);
      final dep = _dollars('usd_dep',
          usd: 40,
          type: breez.PaymentType.receive,
          at: _t0.add(const Duration(minutes: 5)));
      final toHl = _swap('to_hl',
          coinFrom: kOrchestraUsdAssetCode,
          networkFrom: 'SPARK',
          coinTo: 'USDC',
          networkTo: 'HYPERCORE',
          depositAmount: '10.00',
          at: _t0.add(const Duration(minutes: 10)));
      final toHlLeg = _dollars('usd_to_hl',
          usd: 10,
          type: breez.PaymentType.send,
          at: _t0.add(const Duration(minutes: 10, seconds: 5)));
      final buy = _swap('buy',
          coinFrom: kOrchestraUsdAssetCode,
          networkFrom: 'SPARK',
          coinTo: 'BTC',
          networkTo: 'SPARK',
          depositAmount: '9.71',
          withdrawalAmount: '0.00012212',
          at: _t0.add(const Duration(minutes: 20)));
      final buyLeg = _dollars('usd_buy',
          usd: 9.71,
          type: breez.PaymentType.send,
          at: _t0.add(const Duration(minutes: 20, seconds: 3)));
      final buyRx = _spark('rx_buy', 12212, _t0.add(const Duration(minutes: 22)));
      final sorted = <BaseTransaction>[
        friend,
        dep,
        toHl,
        toHlLeg,
        buy,
        buyLeg,
        buyRx,
      ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final rows = assembleActivityRows(
        sorted,
        ownAddresses: const {_self},
        isHardwareOrWatchOnly: false,
        onlyUsdb: false,
        allAccounts: true,
        classify: (o) => _kinds[o.id] ?? classifySwapActivity(o),
        walletId: 'spending',
        deliveryLinks: const {},
      );
      expect([for (final r in rows) r.id],
          ['buy', 'to_hl', 'usd_dep', 'rx_friend']);
    });
  });

  group('on screen', () {
    Future<void> pump(WidgetTester tester, Widget home,
        {Transaction? history,
        List<HlFill> fills = const [],
        Size size = const Size(400, 3000)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            ...portfolioOverrides(history: history),
            ...offlineVenueOverrides,
            hyperliquidActivityFillsProvider.overrideWith((_) => fills),
            settingsProvider.overrideWith((_) => SettingsModel(Settings(
                currency: 'USD',
                language: 'en',
                btcFormat: 'sats',
                backup: false,
                biometricsEnabled: false,
                bitcoinElectrumNode: '',
                nodeType: '',
                reviewDone: true,
                activeWalletId: 'spending',
                wallets: [WalletConfig(id: 'spending', name: 'Spending')]))),
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
              home: home,
            ),
          )));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // A bitcoin receive, a dollar deposit and `bets` predictions, one a
    // minute, the predictions the newest.
    Transaction history(int bets) => Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: [_spark('rx', 5000, _t0)],
          sparkUnclaimedDeposits: const [],
          usdbTokenTransactions: [
            _dollars('dep',
                usd: 20,
                type: breez.PaymentType.receive,
                at: _t0.add(const Duration(minutes: 1))),
          ],
          swapOrderTransactions: const [],
          polymarketTransactions: [
            for (var i = 0; i < bets; i++)
              _bet('bet$i', _t0.add(Duration(minutes: 2 + i))),
          ],
        );

    testWidgets('the home shows the newest eight of every account',
        (tester) async {
      await pump(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: AllActivityPreview())),
          history: history(3),
          fills: [
            for (var i = 0; i < 6; i++)
              _fill(_t0.add(Duration(minutes: 10 + i)), oid: i),
          ]);
      // 6 fills + 3 bets + 1 dollar deposit + 1 bitcoin receive = 11; the
      // newest eight: every fill and the first two bets.
      expect(find.text('Prediction · Yes', skipOffstage: false),
          findsNWidgets(2));
      expect(find.byType(ActivityDaySection), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short history: every row, bitcoin and Dollars included',
        (tester) async {
      await pump(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: AllActivityPreview())),
          history: history(2));
      expect(find.text('Prediction · Yes', skipOffstage: false),
          findsNWidgets(2));
      // The bitcoin receive and the dollar deposit are rows too.
      expect(find.text('Received', skipOffstage: false), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing yet: the empty state the home passes',
        (tester) async {
      await pump(
          tester,
          const Scaffold(
              body: SingleChildScrollView(
                  child: AllActivityPreview(emptyState: Text('empty')))));
      expect(find.text('empty'), findsOneWidget);
    });

    testWidgets('See all lists every row, links card on top, no tabs',
        (tester) async {
      await pump(tester, const ActivityHistoryScreen(), history: history(12));
      // Empty here (nothing sent), so it draws nothing, but it is there.
      expect(find.byType(PendingShareLinksCard, skipOffstage: false),
          findsOneWidget);
      expect(find.byType(AllActivitySliver), findsOneWidget);
      expect(find.text('Prediction · Yes', skipOffstage: false),
          findsNWidgets(12));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long history is built a page at a time as it scrolls',
        (tester) async {
      final long = Transaction(
        bitcoinTransactions: const [],
        sparkTransactions: const [],
        sparkUnclaimedDeposits: const [],
        usdbTokenTransactions: const [],
        swapOrderTransactions: const [],
        polymarketTransactions: [
          for (var i = 0; i < 150; i++)
            _bet('bet$i', _t0.subtract(Duration(hours: i))),
        ],
      );
      await pump(tester, const ActivityHistoryScreen(),
          history: long, size: const Size(400, 900));
      final sliver = find.byType(AllActivitySliver);
      expect(sliver, findsOneWidget);
      final oldest = _t0.subtract(const Duration(hours: 149)).toLocal();
      final oldestDay = DateFormat.MMMMd('en').format(oldest);
      // The first page stops well short of the oldest day.
      expect(find.text(oldestDay, skipOffstage: false), findsNothing);
      // Scroll to the end: every page loads, the oldest bet last.
      for (var i = 0; i < 60; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(oldestDay), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
