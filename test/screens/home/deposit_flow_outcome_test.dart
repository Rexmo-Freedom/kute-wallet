// Every Move route ends in one outcome for one real action: move_submitted
// when the user commits, then move_completed or move_failed, and a single
// move_sheet_abandoned on close only when nothing completed (with
// handed_off_to_<flow> when the action continued in the Ledger device flow
// or in Cash App). The sheet wiring is checked against the source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/home/components/deposit/deposit_flow_outcome.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/source_scan.dart';

const _inputs = <String, Object>{
  'from_asset': 'btc',
  'to_asset': 'usdc',
  'wallet_kind': 'ledger',
  'amount_sats': 150000,
  'amount_usd': 97.5,
};

void main() {
  late List<(String, Map<String, Object>?)> seen;
  late MoveFlowOutcome move;

  setUp(() {
    TrackingService.setDisabled(true);
    TrackingService.debugResetMoneyFlows();
    seen = [];
    TrackingService.debugTrackObserver = (e, p) => seen.add((e, p));
    TrackingService.moneyFlowStarted('move',
        event: 'move_sheet_opened',
        abandonEvent: 'move_sheet_abandoned',
        entrySource: 'home');
    move = MoveFlowOutcome();
  });
  tearDown(() {
    TrackingService.debugTrackObserver = null;
    TrackingService.debugResetMoneyFlows();
  });

  List<String> names() => [for (final e in seen.skip(1)) e.$1];
  Map<String, Object>? paramsOf(String event) =>
      seen.lastWhere((e) => e.$1 == event).$2;

  group('Ledger device flow', () {
    test('a submitted device flow completes the move, no abandon after', () {
      move.handedOff('ledger');
      // The device sheet's onSubmitted: submit then complete.
      move.submitted(_inputs);
      move.completed();
      move.closed();
      expect(names(), ['move_submitted', 'move_completed']);
      expect(paramsOf('move_completed'), {..._inputs, 'outcome': 'submitted'});
    });

    test('left without submitting: one abandon, handed off to the Ledger', () {
      move.handedOff('ledger');
      move.closed();
      move.closed();
      expect(names(), ['move_sheet_abandoned']);
      expect(
          paramsOf('move_sheet_abandoned')!['reason'], 'handed_off_to_ledger');
    });

    test('back on the sheet with another source clears the hand-off', () {
      move.handedOff('ledger');
      move.clearHandoff();
      move.closed();
      expect(paramsOf('move_sheet_abandoned')!['reason'], 'user_closed');
    });
  });

  group('Cash App purchase started from Move', () {
    test('paid in Cash App: completed once, no abandon after', () {
      move.submitted(_inputs);
      move.handedOff('cashapp');
      move.completed(outcome: 'paid');
      move.completed(outcome: 'paid');
      move.closed();
      expect(names(), ['move_submitted', 'move_completed']);
      expect(paramsOf('move_completed')!['outcome'], 'paid');
    });

    test('closed while the order waits in Cash App: handed off', () {
      move.submitted(_inputs);
      move.handedOff('cashapp');
      move.closed();
      expect(names(), ['move_submitted', 'move_sheet_abandoned']);
      final abandon = paramsOf('move_sheet_abandoned')!;
      expect(abandon['reason'], 'handed_off_to_cashapp');
      expect(abandon['step'], 'submitted');
      expect(abandon['amount_usd'], 97.5);
    });

    test('order failed: one move_failed with a category, never raw text', () {
      move.submitted(_inputs);
      move.failed(
          TrackingService.errorCategory('Connection refused by host 10.0.0.1'),
          stage: 'dispatch');
      move.failed('settlement', stage: 'settlement'); // same submit: dropped
      move.closed();
      expect(
          names(), ['move_submitted', 'move_failed', 'move_sheet_abandoned']);
      expect(paramsOf('move_failed'), {
        ..._inputs,
        'error_category': 'network',
        'stage': 'dispatch',
      });
      final abandon = paramsOf('move_sheet_abandoned')!;
      expect(abandon['reason'], 'backend_unreachable');
      expect(abandon['last_error_category'], 'network');
    });

    test('settlement failure after the hand-off drops the hand-off', () {
      move.submitted(_inputs);
      move.handedOff('cashapp');
      move.failed('settlement', stage: 'settlement');
      move.closed();
      expect(paramsOf('move_failed')!['error_category'], 'settlement');
      expect(paramsOf('move_sheet_abandoned')!['reason'], 'error_shown');
    });
  });

  group('Savings-wallet PSBT routes', () {
    test('broadcast completes the move, no abandon after', () {
      move.submitted(_inputs);
      move.completed(); // onBroadcastResult(null, 'broadcast')
      move.closed();
      move.failed('network', stage: 'broadcast'); // after close: nothing
      expect(names(), ['move_submitted', 'move_completed']);
    });

    test('a declined approval fails once and the retry completes', () {
      move.submitted(_inputs);
      move.failed('user_cancelled', stage: 'approval');
      move.submitted(_inputs);
      move.completed();
      move.closed();
      expect(names(), [
        'move_submitted',
        'move_failed',
        'move_submitted',
        'move_completed',
      ]);
    });

    test('nothing is reported after the sheet closed', () {
      move.submitted(_inputs);
      move.closed();
      move.completed();
      move.submitted(_inputs);
      expect(names(), ['move_submitted', 'move_sheet_abandoned']);
    });
  });

  group('the Move sheet wires each route', () {
    final sheet = stripComments(
        File('lib/screens/home/components/deposit_sheet.dart')
            .readAsStringSync());

    String body(String signature) {
      final start = sheet.indexOf(signature);
      expect(start, greaterThan(0), reason: signature);
      var depth = 0;
      // The body opens after the parameter list (which may hold `{`).
      final open =
          RegExp(r'\)\s*(async\s*)?\{').firstMatch(sheet.substring(start))!;
      for (var i = start + open.end - 1; i < sheet.length; i++) {
        if (sheet[i] == '{') depth++;
        if (sheet[i] == '}' && --depth == 0) {
          return sheet.substring(start, i + 1);
        }
      }
      fail('unterminated $signature');
    }

    test('dispose closes the move flow through the outcome', () {
      final dispose = body('void dispose() {');
      expect(dispose, contains('_moveOutcome.closed();'));
      expect(dispose, isNot(contains("moneyFlowAbandoned('move'")));
    });

    test('no spending <-> savings move survives', () {
      // Every door is locked to a venue or a rail; the sheet never moves
      // bitcoin between the spending account and a savings wallet.
      for (final gone in [
        '_moveSpendingBtcToSavingsBtc',
        '_dispatchSavingsBtcToSpendingBtc',
        'WatchOnlySigningScreen(',
        'MoveLockedSide.none',
        'onPickDestSavingsWallet',
        'onPickSourceSavingsWallet',
      ]) {
        expect(sheet.contains(gone), isFalse, reason: gone);
      }
    });

    test('every Ledger device sheet is a hand-off that reports submission', () {
      final route = body('Future<void> _convertLedger() async {');
      for (final sheetCall in [
        'showLedgerFundInvestingSheet(',
        'showLedgerFundPredictionsSheet(',
        'showLedgerWithdrawInvestingSheet(',
        'showLedgerWithdrawPredictionsSheet(',
      ]) {
        final at = route.indexOf(sheetCall);
        expect(at, greaterThan(0), reason: sheetCall);
        final handoff =
            route.lastIndexOf("_moveOutcome.handedOff('ledger')", at);
        expect(handoff, greaterThan(0), reason: sheetCall);
        final call = route.substring(at, route.indexOf(');', at));
        expect(call, contains('onSubmitted: _trackLedgerMoveSubmitted'),
            reason: sheetCall);
      }
      for (final file in [
        'ledger_fund_investing_sheet.dart',
        'ledger_fund_predictions_sheet.dart',
        'ledger_withdraw_investing_sheet.dart',
        'ledger_withdraw_predictions_sheet.dart',
      ]) {
        final src = stripComments(
            File('lib/screens/ledger/funding/$file').readAsStringSync());
        expect(src, contains('widget.onSubmitted?.call();'), reason: file);
      }
    });

    test('the Cash App onramp submits, hands off, then completes or fails', () {
      final create = body('Future<void> _createCashAppOnramp() async {');
      final submitted = create.indexOf('_trackMoveSubmitted();');
      final created = create.indexOf('orderCreated = true;');
      final handoff = create.indexOf("_moveOutcome.handedOff('cashapp');");
      expect(submitted, greaterThan(0));
      expect(submitted, lessThan(created));
      expect(handoff, greaterThan(created));
      expect(create, contains('_trackMoveFailed(e);'));
      final poll = body('Future<void> _pollCashAppStatus(');
      expect(poll, contains("_trackMoveCompleted(outcome: 'paid');"));
      expect(poll,
          contains("_trackMoveFailed('settlement', stage: 'settlement');"));
    });
  });
}
