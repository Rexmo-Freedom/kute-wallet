// The Bitcoin home's Activity shows everything the spending account did
// (founder, 1 November 2026): bitcoin sends and receives, the Dollars
// ledger and the Investments activity the Portfolio's Activity used to
// list (Investing fills, Predictions bets, venue moves), merged by time,
// the newest five actions on the home under a "Today" card; "See all"
// lists them all on one screen, each funding chain folded into the action
// it paid for (activity_curation.dart, founder 1 November 2026).

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
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/providers/portfolio_performance_provider.dart'
    show portfolioPerformanceDisplayProvider;
import 'package:kute/screens/shared/activity_curation.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/activity/activity_history_screen.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/shared/all_activity.dart';
import 'package:kute/screens/shared/hyperliquid_fill_activity.dart'
    show HyperliquidFillActivityRow;
import 'package:kute/screens/shared/transactions_builder.dart'
    show ActivityDaySection, ActivityRowNote, assembleActivityRows;
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

PolymarketTransaction _bet(String id, DateTime at,
        {String type = 'TRADE', String side = 'BUY', double usd = 5}) =>
    PolymarketTransaction(
      id: id,
      timestamp: at,
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: at.millisecondsSinceEpoch ~/ 1000,
        conditionId: '0xrain',
        type: type,
        size: 10,
        usdcSize: usd,
        transactionHash: '0x$id',
        side: side,
        asset: 'yes',
        outcomeIndex: 0,
        title: 'Will it rain tomorrow?',
        outcome: 'Yes',
        eventSlug: '',
      ),
    );

HlFill _fill(DateTime at, {int oid = 1, String dir = 'Open Long'}) => HlFill(
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
      dir: dir,
      cloid: null,
    );

const _kinds = {
  'to_hl': SwapActivityKind.investingDeposit,
  'buy': SwapActivityKind.dollarWithdrawal,
  'btc_to_usd': SwapActivityKind.dollarDeposit,
  'usd_to_pm': SwapActivityKind.predictionsDeposit,
  'btc_to_pm': SwapActivityKind.predictionsDeposit,
  'btc_to_hl': SwapActivityKind.investingDeposit,
  'manual_usd': SwapActivityKind.dollarDeposit,
  'pm_home': SwapActivityKind.predictionsWithdrawal,
};

SwapActivityKind _classify(SwapOrder o) =>
    _kinds[o.id] ?? classifySwapActivity(o);

AllActivityEntry _e(BaseTransaction tx) =>
    (time: tx.timestamp, tx: tx, fill: null);
AllActivityEntry _f(HlFill f) =>
    (time: DateTime.fromMillisecondsSinceEpoch(f.time), tx: null, fill: f);

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

  group('curation', () {
    // A prediction placed at t0+20, paid Bitcoin → Dollars → Predictions.
    final btcToUsd = _swap('btc_to_usd',
        coinFrom: 'BTC',
        networkFrom: 'SPARK',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAmount: '0.0001',
        withdrawalAmount: '10.00',
        at: _t0.add(const Duration(minutes: 5)));
    final usdToPm = _swap('usd_to_pm',
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        coinTo: 'USDC.E',
        networkTo: 'POLYGON',
        depositAmount: '9.90',
        withdrawalAmount: '9.80',
        at: _t0.add(const Duration(minutes: 10)));
    final venueRecord = _bet('pm_dep', _t0.add(const Duration(minutes: 12)),
        type: 'DEPOSIT', usd: 9.8);
    final bet = _bet('bet', _t0.add(const Duration(minutes: 20)));

    test('a funding chain folds into the bet it paid for', () {
      final rx = _spark('rx', 5000, _t0.subtract(const Duration(hours: 1)));
      final entries = mergeAllActivity(
          walletRows: [usdToPm, btcToUsd, rx], bets: [bet, venueRecord]);
      final curated = curateAllActivity(entries, classify: _classify);
      expect(_ids(curated.entries), ['bet', 'rx']);
      final betEntry = curated.entries.first;
      expect(curated.paidFromOf(betEntry), [ActivityAccount.bitcoin]);
    });

    test('paid from Dollars when nothing fed Dollars', () {
      final entries =
          mergeAllActivity(walletRows: [usdToPm], bets: [bet]);
      final curated = curateAllActivity(entries, classify: _classify);
      expect(_ids(curated.entries), ['bet']);
      expect(curated.paidFromOf(curated.entries.first),
          [ActivityAccount.dollars]);
    });

    test('a Dollars hop whose figures disagree stays its own row', () {
      final bigDeposit = _swap('btc_to_usd',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: kOrchestraUsdAssetCode,
          networkTo: 'SPARK',
          withdrawalAmount: '250.00',
          at: _t0.add(const Duration(minutes: 5)));
      final entries =
          mergeAllActivity(walletRows: [usdToPm, bigDeposit], bets: [bet]);
      final curated = curateAllActivity(entries, classify: _classify);
      expect(_ids(curated.entries), ['bet', 'btc_to_usd']);
      expect(curated.paidFromOf(curated.entries.first),
          [ActivityAccount.dollars]);
    });

    test('an Investing open takes the deposit that funded it', () {
      final toHl = _swap('btc_to_hl',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: 'USDC',
          networkTo: 'HYPERCORE',
          at: _t0.add(const Duration(minutes: 3)));
      final open = _fill(_t0.add(const Duration(minutes: 8)));
      final close =
          _fill(_t0.add(const Duration(minutes: 9)), oid: 2, dir: 'Close Long');
      final entries =
          mergeAllActivity(walletRows: [toHl], fills: [open, close]);
      final curated = curateAllActivity(entries, classify: _classify);
      expect(_ids(curated.entries), ['fill:2', 'fill:1']);
      expect(curated.paidFromOf(_f(open)), [ActivityAccount.bitcoin]);
      expect(curated.paidFromOf(_f(close)), isNull);
    });

    test('a move long before the action, or after a sale, does not fold',
        () {
      final manual = _swap('manual_usd',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: kOrchestraUsdAssetCode,
          networkTo: 'SPARK',
          withdrawalAmount: '10.00',
          at: _t0.subtract(const Duration(hours: 3)));
      final sale = _bet('sale', _t0.add(const Duration(minutes: 40)),
          side: 'SELL');
      final home = _swap('pm_home',
          coinFrom: 'USDC.E',
          networkFrom: 'POLYGON',
          coinTo: 'BTC',
          networkTo: 'SPARK',
          at: _t0.add(const Duration(minutes: 45)));
      final entries = mergeAllActivity(
          walletRows: [home, manual], bets: [sale, bet]);
      final curated = curateAllActivity(entries, classify: _classify);
      expect(_ids(curated.entries), ['pm_home', 'sale', 'bet', 'manual_usd']);
      expect(curated.paidFrom, isEmpty);
    });

    test('a venue record beside its conversion is listed once', () {
      final entries = mergeAllActivity(
          walletRows: [usdToPm], bets: [venueRecord]);
      final curated = curateAllActivity(entries, classify: _classify);
      expect(_ids(curated.entries), ['usd_to_pm']);
    });

    test('the home lists actions only, five at most', () {
      final manual = _swap('manual_usd',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: kOrchestraUsdAssetCode,
          networkTo: 'SPARK',
          withdrawalAmount: '10.00',
          at: _t0.add(const Duration(hours: 2)));
      final rows = [
        for (var i = 0; i < 7; i++)
          _spark('rx$i', 1000, _t0.add(Duration(minutes: i))),
        manual,
      ];
      final entries = mergeAllActivity(walletRows: rows);
      final curated = curateAllActivity(entries, classify: _classify);
      // See all keeps the move between own accounts …
      expect(_ids(curated.entries).first, 'manual_usd');
      // … the home never lists it, and stops at five.
      final home = homeActivityEntries(curated, classify: _classify);
      expect(_ids(home), ['rx6', 'rx5', 'rx4', 'rx3', 'rx2']);
      expect(kHomeActivityRows, 5);
    });

    test('Today: in and out from today\'s actions, none without any', () {
      final now = DateTime(2026, 11, 1, 15);
      final rx = _spark('rx', 20000, now.subtract(const Duration(hours: 1)));
      final tx = _spark('tx', 5000, now.subtract(const Duration(hours: 2)),
          direction: TransactionType.sent);
      final usdIn = _dollars('usd_in',
          usd: 12.5,
          type: breez.PaymentType.receive,
          at: now.subtract(const Duration(hours: 3)));
      final old = _spark('old', 90000, now.subtract(const Duration(days: 1)));
      final manual = _swap('manual_usd',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: kOrchestraUsdAssetCode,
          networkTo: 'SPARK',
          depositAmount: '0.001',
          withdrawalAmount: '100.00',
          at: now.subtract(const Duration(minutes: 30)));
      final entries = [_e(manual), _e(rx), _e(tx), _e(usdIn), _e(old)];
      final flows = todayActivityFlows(entries,
          now: now, btcUsd: 100000, classify: _classify);
      expect(flows.any, isTrue);
      // 20,000 sats at $100k = $20 + $12.50; the move is not money in.
      expect(flows.inUsd, closeTo(32.5, 1e-9));
      expect(flows.outUsd, closeTo(5, 1e-9));
      // Only plumbing today, or nothing: no card.
      expect(
          todayActivityFlows([_e(manual), _e(old)],
                  now: now, btcUsd: 100000, classify: _classify)
              .any,
          isFalse);
      // No price: the bitcoin figure is unknown, never a wrong zero.
      expect(
          todayActivityFlows([_e(rx)],
                  now: now, btcUsd: 0, classify: _classify)
              .inUsd,
          isNull);
    });

    test('Today P&L: the venue\'s move since midnight, none without data',
        () {
      final midnight = DateTime(2026, 11, 1);
      PortfolioPerformance perf(List<PortfolioPnlPoint> points) =>
          PortfolioPerformance(
              points: points,
              sourceLabel: '',
              basisLabel: 'P&L',
              coverageLabel: '');
      expect(todayPnlOf(perf(const []), midnight), isNull);
      final p = perf([
        PortfolioPnlPoint(
            timestamp: midnight.subtract(const Duration(hours: 2)), pnlUsd: 10),
        PortfolioPnlPoint(
            timestamp: midnight.add(const Duration(hours: 9)), pnlUsd: 12.5),
      ]);
      expect(todayPnlOf(p, midnight), closeTo(2.5, 1e-9));
      // Nothing published since midnight: no figure for today.
      final stale = perf([
        PortfolioPnlPoint(
            timestamp: midnight.subtract(const Duration(hours: 2)), pnlUsd: 10),
      ]);
      expect(todayPnlOf(stale, midnight), isNull);
    });
  });

  group('on screen', () {
    Future<void> pump(WidgetTester tester, Widget home,
        {Transaction? history,
        List<HlFill> fills = const [],
        List<Override> extra = const [],
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
            currentBtcUsdProvider.overrideWithValue(100000),
            ...extra,
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

    testWidgets('the home shows the newest five of every account',
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
      // newest five: five of the fills, no bet.
      expect(find.byType(HyperliquidFillActivityRow, skipOffstage: false),
          findsNWidgets(5));
      expect(find.text('Prediction · Yes', skipOffstage: false),
          findsNothing);
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

    // Today: a bitcoin receive and a send, and a prediction paid from
    // Bitcoin through Dollars (both legs folded into it).
    Transaction todayHistory(DateTime now) => Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: [
            _spark('rx_today', 20000, now.subtract(const Duration(seconds: 50))),
            _spark('tx_today', 5000, now.subtract(const Duration(seconds: 40)),
                direction: TransactionType.sent),
          ],
          sparkUnclaimedDeposits: const [],
          swapOrderTransactions: [
            _swap('btc_to_usd',
                coinFrom: 'BTC',
                networkFrom: 'SPARK',
                coinTo: kOrchestraUsdAssetCode,
                networkTo: 'SPARK',
                depositAmount: '0.0001',
                withdrawalAmount: '10.00',
                at: now.subtract(const Duration(seconds: 30))),
            _swap('usd_to_pm',
                coinFrom: kOrchestraUsdAssetCode,
                networkFrom: 'SPARK',
                coinTo: 'USDC.E',
                networkTo: 'POLYGON',
                depositAmount: '9.90',
                withdrawalAmount: '9.80',
                at: now.subtract(const Duration(seconds: 20))),
          ],
          polymarketTransactions: [
            _bet('bet_today', now.subtract(const Duration(seconds: 10))),
          ],
        );

    testWidgets('the home: the Today card, and a bet paid from Bitcoin',
        (tester) async {
      debugAllActivityClassify = _classify;
      addTearDown(() => debugAllActivityClassify = null);
      await pump(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: AllActivityPreview())),
          history: todayHistory(DateTime.now()));
      expect(find.byType(ActivityTodayCard), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-today-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-today-out')), findsOneWidget);
      // 20,000 sats at $100k in, 5,000 out.
      Finder inTile(String key, String text) => find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.text(text));
      expect(inTile('activity-today-in', r'$20.00'), findsOneWidget);
      expect(inTile('activity-today-out', r'$5.00'), findsOneWidget);
      // No venue figure: no P&L tile.
      expect(find.byKey(const ValueKey('activity-today-pnl')), findsNothing);
      // The moves between own accounts are not rows; the bet carries them.
      expect(find.text('Prediction · Yes'), findsOneWidget);
      expect(find.textContaining('Paid from Bitcoin'), findsOneWidget);
      expect(find.byType(ActivityRowNote), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Today card shows P&L when a venue has a figure',
        (tester) async {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final perf = PortfolioPerformance(points: [
        PortfolioPnlPoint(
            timestamp: midnight.subtract(const Duration(hours: 1)),
            pnlUsd: 10),
        PortfolioPnlPoint(timestamp: now, pnlUsd: 12.5),
      ], sourceLabel: '', basisLabel: 'P&L', coverageLabel: '');
      await pump(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: AllActivityPreview())),
          history: todayHistory(now),
          extra: [
            portfolioPerformanceDisplayProvider(const PortfolioPerformanceRequest(
                    venue: PortfolioPerformanceVenue.trading))
                .overrideWithValue(AsyncData(perf)),
          ]);
      expect(find.byKey(const ValueKey('activity-today-pnl')), findsOneWidget);
      expect(find.text(r'+$2.50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no activity today: no Today card', (tester) async {
      await pump(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: AllActivityPreview())),
          history: history(2));
      expect(find.byType(ActivityTodayCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('See all keeps the moves, folded into the bet they paid',
        (tester) async {
      debugAllActivityClassify = _classify;
      addTearDown(() => debugAllActivityClassify = null);
      final now = DateTime.now();
      final h = todayHistory(now);
      final withManual = h.copyWith(swapOrderTransactions: [
        ...h.swapOrderTransactions,
        _swap('manual_usd',
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: kOrchestraUsdAssetCode,
            networkTo: 'SPARK',
            withdrawalAmount: '40.00',
            at: now.subtract(const Duration(days: 2))),
      ]);
      await pump(tester, const ActivityHistoryScreen(), history: withManual);
      expect(find.text('Prediction · Yes', skipOffstage: false),
          findsOneWidget);
      expect(find.textContaining('Paid from Bitcoin', skipOffstage: false),
          findsOneWidget);
      // The manual move is listed here (and only here), on its own day.
      expect(find.byType(ActivityDaySection, skipOffstage: false),
          findsNWidgets(2));
      expect(find.byType(ActivityTodayCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
