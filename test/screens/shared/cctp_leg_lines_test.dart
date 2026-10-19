// A CCTP move's legs under its Activity line (founder, 19 October 2026:
// the money steps show HyperCore withdrawal → Arbitrum mint → Orchestra
// order), each done on its own, from the move's settlement record.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/screens/shared/move_steps_view.dart';
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart';
import 'package:kute/theme/app_theme.dart';


import '../../helpers/fake_swap_orders.dart';
import '../../helpers/money_steps_finders.dart';

CctpLegProgress _progress({
  bool burned = false,
  bool minted = false,
  bool ordered = false,
  bool failed = false,
}) =>
    (
      burned: burned,
      minted: minted,
      ordered: ordered,
      failed: failed,
      sentUsd: 5.25,
      mintUsd: 5.05,
    );

SwapOrder _row(String id, {String? routeVersion}) => SwapOrder(
      id: id,
      coinFrom: 'USDC',
      networkFrom: 'HYPERCORE',
      coinTo: 'USDB',
      networkTo: 'SPARK',
      depositAddress: '0x17c01c4dc5fe4b698978e302b3480efc9e3a19b6',
      depositAmount: '5.25',
      withdrawalAmount: '5.05',
      status: 'exchanging',
      timestamp: 0,
      withdrawalAddress: 'spark1fixture',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '0x7578d21940ee6ac4f882b6d5173d26bce62f5136',
      provider: 'Orchestra',
      routeVersion: routeVersion,
    );

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  List<(String, MoneyStepStatus, bool)> lines(CctpLegProgress p,
          {bool done = false, bool failed = false}) =>
      [
        for (final l in cctpLegLines(en, p,
            destination: 'Dollars', rowDone: done, rowFailed: failed))
          (l.text, l.status, l.sub),
      ];

  test('three legs, each completing on its own', () {
    expect(lines(_progress()), [
      ('HyperCore → Circle · \$5.25', MoneyStepStatus.running, true),
      ('Circle → Arbitrum · \$5.05', MoneyStepStatus.waiting, true),
      ('Arbitrum → Dollars · \$5.05', MoneyStepStatus.waiting, true),
    ]);
    expect(lines(_progress(burned: true)).map((l) => l.$2), [
      MoneyStepStatus.done,
      MoneyStepStatus.running,
      MoneyStepStatus.waiting
    ]);
    expect(lines(_progress(burned: true, minted: true)).map((l) => l.$2),
        [MoneyStepStatus.done, MoneyStepStatus.done, MoneyStepStatus.running]);
    expect(
        lines(_progress(burned: true, minted: true, ordered: true), done: true)
            .map((l) => l.$2),
        [MoneyStepStatus.done, MoneyStepStatus.done, MoneyStepStatus.done]);
  });

  test('a burn proved never to have happened fails its own leg', () {
    expect(lines(_progress(failed: true)).first.$2, MoneyStepStatus.failed);
    expect(lines(_progress(burned: true, minted: true), failed: true).last.$2,
        MoneyStepStatus.failed);
  });

  test('which rows are CCTP moves', () {
    expect(isCctpMoveRow(_row('${kCctpRowPrefix}op')), isTrue);
    expect(
        isCctpMoveRow(_row('ord_1', routeVersion: kHypercoreCctpRouteVersion)),
        isTrue);
    expect(
        isCctpMoveRow(
            _row('ord_1', routeVersion: kHypercoreCctpPredictionsRouteVersion)),
        isTrue);
    expect(isCctpMoveRow(_row('ord_1', routeVersion: 'spark_to_hypercore_v1')),
        isFalse);
  });

  testWidgets('the Activity detail shows the legs under the move', (t) async {
    final row =
        _row('${kCctpRowPrefix}op-1', routeVersion: kHypercoreCctpRouteVersion)
            .copyWith(operationId: 'op-1');
    await t.pumpWidget(ProviderScope(
      overrides: [
        swapOrdersProvider.overrideWith((_) => FakeSwapOrders([row])),
        cctpLegProgressProvider('op-1')
            .overrideWith((ref) async => _progress(burned: true)),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SwapRowStepsSection(row: row)),
        ),
      ),
    ));
    await t.pump();
    expect(findMoneyStep('HyperCore → Circle · \$5.25'), findsOneWidget);
    expect(findMoneyStep('Circle → Arbitrum · \$5.05'), findsOneWidget);
    expect(findMoneyStep('Arbitrum → Dollars · \$5.05'), findsOneWidget);
  });
}
