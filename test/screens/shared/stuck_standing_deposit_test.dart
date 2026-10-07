import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/orchestra_swap_refund_action.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/theme/app_theme.dart';

const _spark = 'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _base = '0x1111111111111111111111111111111111111111';

const _record = StandingDepositRecord(
  walletId: 'spending',
  label: 'sref',
  recipient: _spark,
  asset: 'USDB',
  revision: 4,
  response: {
    'standingAddressId': 'sda_1',
    'enabled': true,
    'addresses': {'base': _base},
  },
);

Map<String, dynamic> _deposit(
        {String status = 'held', Object? orderId, Object? refundTxId}) =>
    {
      'id': 'dep_1',
      'chain': 'base',
      'asset': 'USDC',
      'amount': '2500000',
      'status': status,
      'sourceTxId': '0xsource',
      'createdAt': '2026-09-30T10:00:00Z',
      if (orderId != null) 'orderId': orderId,
      if (refundTxId != null) 'refundTxId': refundTxId,
    };

SwapOrder? _row(Map<String, dynamic> deposit,
        {StandingDepositRecord record = _record}) =>
    stuckStandingDepositRow(
        deposit: deposit,
        record: record,
        walletId: 'spending',
        recipient: _spark);

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: false,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

void main() {
  group('stuck deposit row', () {
    test('a held deposit with no order becomes a receive row', () {
      final row = _row(_deposit())!;
      expect(row.id, 'sdep_dep_1');
      expect(row.isStuckStandingDeposit, isTrue);
      expect(row.stuckStandingDepositId, 'dep_1');
      expect(row.status, 'held');
      expect(row.coinFrom, 'USDC');
      expect(row.networkFrom, 'base');
      expect(row.coinTo, 'USDB');
      expect(row.networkTo, 'SPARK');
      expect(row.depositAddress, _base);
      expect(double.parse(row.depositAmount), 2.5);
      expect(row.withdrawalAmount, '0');
      expect(row.walletId, 'spending');
      expect(row.timestamp,
          DateTime.parse('2026-09-30T10:00:00Z').millisecondsSinceEpoch);
      expect(classifySwapActivity(row), SwapActivityKind.receive);
      // Nothing to poll: it has no order id.
      expect(row.isOrchestra, isTrue);
      expect(row.shouldPollOrchestra, isFalse);
      expect(row.isPending, isFalse);
    });

    test('only a deposit that did not work gets a row', () {
      // Still on its way, or converted: no stuck row.
      for (final status in ['pending', 'detected', 'completed', 'delivered']) {
        expect(_row(_deposit(status: status)), isNull, reason: status);
      }
      // It became an order: that order's row represents it.
      expect(_row(_deposit(orderId: 'ord_1')), isNull);
      expect(_row(_deposit(status: 'failed'))!.status, 'failed');
      expect(_row(_deposit(status: 'refund_requested'))!.status,
          'refund_requested');
      expect(_row(_deposit(refundTxId: '0xback'))!.status, 'refunded');
    });

    test('a refund this wallet asked for reads as requested', () {
      final asked = _record.copy(refunds: {
        'dep_1': {'state': 'requested', 'key': 'k', 'address': _base}
      });
      expect(_row(_deposit(), record: asked)!.status, 'refund_requested');
      final refused = _record.copy(refunds: {
        'dep_1': {'state': 'refused', 'key': 'k', 'address': _base}
      });
      expect(_row(_deposit(), record: refused)!.status, 'held');
    });
  });

  group('refund button in the row details', () {
    late Directory directory;
    late Future<Map<String, dynamic>> Function(
        {required String operation,
        String? label,
        required bool Function() current,
        Map<String, dynamic>? body,
        String? idempotencyKey,
        int offset}) original;
    late List<Map<String, dynamic>> listed;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('stuck-deposit-');
      Hive.init(directory.path);
      listed = [_deposit()];
      original = StandingDepositStore.standingRequest;
      StandingDepositStore.standingRequest = (
          {required operation,
          label,
          required current,
          body,
          idempotencyKey,
          offset = 0}) async {
        expect(operation, 'deposits');
        expect(label, _record.label);
        return {'deposits': listed, 'nextOffset': null};
      };
    });
    tearDown(() async {
      StandingDepositStore.standingRequest = original;
      await Hive.close();
      await directory.delete(recursive: true);
    });

    Future<void> pump(WidgetTester tester, SwapOrder row) async {
      await tester.runAsync(() => StandingDepositStore.save(
          _record, StandingDepositStore.capture('spending')));
      await tester.pumpWidget(ProviderScope(
        overrides: [settingsProvider.overrideWith((_) => _Settings())],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: OrchestraSwapRefundAction(order: row)),
          ),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }

    testWidgets('a held deposit offers the refund', (tester) async {
      await pump(tester, _row(_deposit())!);
      expect(find.text(l10nForLanguage('en').requestRefund), findsOneWidget);
    });

    testWidgets('no refund is offered for a deposit the listing lacks',
        (tester) async {
      listed = [
        {..._deposit(), 'id': 'dep_other'}
      ];
      await pump(tester, _row(_deposit())!);
      expect(find.text(l10nForLanguage('en').requestRefund), findsNothing);
    });

    testWidgets('a refunded deposit offers nothing more', (tester) async {
      listed = [_deposit(refundTxId: '0xback')];
      await pump(tester, _row(_deposit(refundTxId: '0xback'))!);
      expect(find.text(l10nForLanguage('en').requestRefund), findsNothing);
    });
  });
}
