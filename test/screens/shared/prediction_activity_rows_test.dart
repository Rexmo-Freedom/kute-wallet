// What a Predictions activity row shows: a placed prediction carries no
// sign (the stake moved into the position); only a settled result does,
// coloured: won green, lost red. Drawn through the Ledger account's list,
// which shares the row copy, figures and widget with the spending
// account's Predictions activity.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart' show Activity, Position;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/ledger/ledger_polymarket_tab.dart'
    show LedgerPmActivityList;
import 'package:kute/screens/shared/transactions_builder.dart'
    show predictionResultTransactions;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';

const _btc = 'Bitcoin Up or Down - October 5, 7:00AM-7:05AM ET';
const _newsom = 'Will Gavin Newsom win the 2028 Democratic nomination?';

Activity _row(String type,
        {String? side,
        required double usdc,
        double size = 1,
        required int at,
        String cid = '0xc',
        String? title,
        String? outcome,
        String? token}) =>
    Activity(
      proxyWallet: '0xledger',
      timestamp: at,
      conditionId: cid,
      type: type,
      size: size,
      usdcSize: usdc,
      transactionHash: '0x$type$at',
      side: side,
      asset: token,
      outcomeIndex: 0,
      title: title,
      outcome: outcome,
      eventSlug: '',
    );

Position _resolved(
        {required String cid,
        required String token,
        required double curPrice,
        required double size,
        required double cost}) =>
    Position(
      proxyWallet: '0xledger',
      asset: token,
      conditionId: cid,
      size: size,
      avgPrice: cost / size,
      initialValue: cost,
      currentValue: size * curPrice,
      cashPnl: size * curPrice - cost,
      percentPnl: 0,
      totalBought: size,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: curPrice,
      redeemable: true,
      title: _btc,
      slug: 'btc',
      eventSlug: '',
      outcome: 'Up',
      outcomeIndex: 0,
      oppositeOutcome: 'Down',
      oppositeAsset: 'down',
    );

Future<void> _pump(WidgetTester tester, List<Activity> rows,
    {List<Position> positions = const []}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        ...offlineVenueOverrides,
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true))),
      ],
      child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                theme: ThemeData(
                    fontFamily: 'Inter',
                    extensions: [AppColorsExtension.light()]),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                    body: LedgerPmActivityList(
                        rows: rows, positions: positions)),
              ))));
  await tester.pump();
}

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.state0);
  final PolymarketTradingState state0;
  @override
  Future<PolymarketTradingState> build() async => state0;
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  testWidgets('a placed prediction shows its stake unsigned, neutral',
      (tester) async {
    await _pump(tester, [
      _row('TRADE',
          side: 'BUY',
          usdc: 2.06,
          at: now - 600,
          title: _newsom,
          outcome: 'Yes'),
    ]);
    expect(find.text('Prediction · Yes'), findsOneWidget);
    expect(find.text('\$2.06'), findsOneWidget);
    expect(find.text('−\$2.06'), findsNothing);
    final context = tester.element(find.text('\$2.06'));
    expect(_colorOf(tester, '\$2.06'), context.colors.textPrimary);
  });

  testWidgets('a sale keeps +proceeds and its profit line', (tester) async {
    await _pump(tester, [
      _row('TRADE',
          side: 'BUY',
          usdc: 3.05,
          size: 5,
          at: now - 900,
          title: _newsom,
          outcome: 'Yes'),
      _row('TRADE',
          side: 'SELL',
          usdc: 3.17,
          size: 5,
          at: now - 300,
          title: _newsom,
          outcome: 'Yes'),
    ]);
    expect(find.text('Sold · Yes'), findsOneWidget);
    expect(find.text('+\$3.17'), findsOneWidget);
    expect(find.text('\$0.12 profit'), findsOneWidget);
    final context = tester.element(find.text('+\$3.17'));
    expect(_colorOf(tester, '+\$3.17'), context.colors.textPrimary);
  });

  testWidgets('a deposit keeps its unsigned amount', (tester) async {
    await _pump(tester, [_row('DEPOSIT', usdc: 40.12, at: now - 60)]);
    expect(find.text('Deposit'), findsOneWidget);
    expect(find.text('\$40.12'), findsOneWidget);
  });

  testWidgets(
      'the lost Bitcoin round, never claimed, shows Lost with −stake in red',
      (tester) async {
    await _pump(tester, [
      _row('TRADE',
          side: 'BUY',
          usdc: 3.21,
          size: 6.3,
          at: now - 3600,
          cid: '0xbtc',
          token: 'up',
          title: _btc,
          outcome: 'Up'),
    ], positions: [
      _resolved(cid: '0xbtc', token: 'up', curPrice: 0, size: 6.3, cost: 3.21),
    ]);
    expect(find.text('Prediction · Up'), findsOneWidget);
    expect(find.text('\$3.21'), findsOneWidget);
    expect(find.text('Lost · Up'), findsOneWidget);
    expect(find.text('−\$3.21'), findsOneWidget);
    expect(_colorOf(tester, '−\$3.21'), AppColors.marketDown);
  });

  testWidgets('a resolved win shows Won with +payout in green and its profit',
      (tester) async {
    await _pump(tester, [
      _row('TRADE',
          side: 'BUY',
          usdc: 3,
          size: 5,
          at: now - 3600,
          cid: '0xbtc',
          token: 'up',
          title: _btc,
          outcome: 'Up'),
    ], positions: [
      _resolved(cid: '0xbtc', token: 'up', curPrice: 1, size: 5, cost: 3),
    ]);
    expect(find.text('Won · Up'), findsOneWidget);
    expect(find.text('+\$5.00'), findsOneWidget);
    expect(_colorOf(tester, '+\$5.00'), AppColors.marketUp);
    expect(find.text('\$2.00 profit'), findsOneWidget);
    expect(find.textContaining('Claim'), findsOneWidget);
  });

  testWidgets('a claimed win from the venue is green too', (tester) async {
    await _pump(tester, [
      _row('TRADE',
          side: 'BUY',
          usdc: 3,
          size: 5,
          at: now - 3600,
          title: _btc,
          outcome: 'Up'),
      _row('REDEEM', usdc: 5, size: 5, at: now - 60, title: _btc, outcome: 'Up'),
    ]);
    expect(find.text('Won · Up'), findsOneWidget);
    expect(_colorOf(tester, '+\$5.00'), AppColors.marketUp);
    expect(find.textContaining('Claim'), findsNothing);
  });

  group('the spending account\'s Predictions activity', () {
    final buy = _row('TRADE',
        side: 'BUY',
        usdc: 3.21,
        size: 6.3,
        at: now - 3600,
        cid: '0xbtc',
        token: 'up',
        title: _btc,
        outcome: 'Up');
    final lost =
        _resolved(cid: '0xbtc', token: 'up', curPrice: 0, size: 6.3, cost: 3.21);

    Future<List<PolymarketTransaction>> resultsFor(
        WidgetTester tester, String proxy) async {
      late List<PolymarketTransaction> out;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          polymarketTradingProvider.overrideWith(() => _Trading(
              PolymarketTradingState(
                  isAuthenticated: true,
                  proxyWalletAddress: proxy,
                  openPositions: [lost]))),
        ],
        child: Consumer(builder: (context, ref, _) {
          out = predictionResultTransactions(ref, [
            PolymarketTransaction(
                id: 'buy', timestamp: buy.timestampDate, activity: buy),
          ]);
          return const SizedBox();
        }),
      ));
      await tester.pump();
      return out;
    }

    testWidgets('gets the lost Bitcoin round as a Lost row', (tester) async {
      final rows = await resultsFor(tester, '0xLEDGER');
      expect(rows, hasLength(1));
      expect(rows.single.result?.won, isFalse);
      expect(rows.single.activityType.name, 'redeem');
      expect(rows.single.timestamp.isAfter(buy.timestampDate), isTrue);
    });

    testWidgets('adds nothing to another account\'s activity', (tester) async {
      expect(await resultsFor(tester, '0xsomeoneelse'), isEmpty);
    });
  });
}
