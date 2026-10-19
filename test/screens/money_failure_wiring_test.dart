// Where the money-failure soft tap is wired (founder decision, 15 October
// 2026): a failed Bitcoin send, Dollars send, Move or receive request plays
// it once; a declined approval, a cancel or a stop for re-review never
// does; and a send's rubber band never adds its own on top. The behaviour
// of the tap itself (once per failure, after the band let go) is in
// test/services/money_failure_feedback_test.dart and
// test/screens/pay/send_rubber_band_test.dart; this checks the screens
// call it where they should, against the source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

String _source(String path) => stripComments(File(path).readAsStringSync());

/// The body of the member that starts at [signature] in [src].
String _body(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: signature);
  final open =
      RegExp(r'(\)|=>)\s*(async\s*)?\{').firstMatch(src.substring(start));
  expect(open, isNotNull, reason: signature);
  var depth = 0;
  for (var i = start + open!.end - 1; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}' && --depth == 0) return src.substring(start, i + 1);
  }
  fail('unterminated $signature');
}

int _count(String haystack, String needle) =>
    needle.allMatches(haystack).length;

void main() {
  group('Bitcoin send (confirm_send.dart)', () {
    final src = _source('lib/screens/pay/components/confirm_send.dart');

    test('waits for the Send block\'s band, as busy as the band is', () {
      final helper = src.substring(src.indexOf('void _sendFailedFeedback()'),
          src.indexOf(';', src.indexOf('void _sendFailedFeedback()')) + 1);
      expect(helper, contains('moneyFailureFeedbackAfterBand('));
      expect(helper, contains('isProcessing || _sendAwaitingReady'));
    });

    test('every failure screen taps (Lightning, Spark, on-chain, Orchestra)',
        () {
      expect(_body(src, 'void _showSendFailed('),
          contains('_sendFailedFeedback();'));
      // Its callers: the Spark/Lightning send, the bitcoin software wallet
      // and the Orchestra send.
      expect(_count(src, '_showSendFailed('), greaterThanOrEqualTo(4));
    });

    test('a declined scan, a review-again stop or a C8 never taps', () {
      expect(_body(src, 'Future<bool> _approveSend('),
          isNot(contains('_sendFailedFeedback')));
      expect(_body(src, 'Future<bool> _consumeSend('),
          isNot(contains('_sendFailedFeedback')));
      final orchestra = _body(src, 'Future<void> _handleOrchestraFromBtc(');
      // The quote-stage refusal skips a declined prompt.
      expect(
          orchestra,
          contains(
              "if (quoteError != 'settlement_declined') _sendFailedFeedback();"));
      // A declined step-up after the quote returns before the failure
      // screen.
      final declined = orchestra.indexOf('SettlementStopReason.declined) {');
      expect(declined, greaterThan(0));
      final declinedReturn = orchestra.indexOf('return;', declined);
      expect(declinedReturn, lessThan(orchestra.indexOf('_showSendFailed(e,')));
      // The software wallet's stop for re-review shows C8, not a failure.
      final software = _body(src, 'Future<void> _handleBitcoinSoftwareSend(');
      final review = software.indexOf('if (stoppedForReview) {');
      expect(review, greaterThan(0));
      expect(software.substring(review, software.indexOf('} else {', review)),
          isNot(contains('_sendFailed')));
      // A declined hardware approval resets quietly.
      final hardware = _body(src, 'Future<void> _handleHardwareSigning(');
      final notApproved = hardware.indexOf('if (!approved) {');
      expect(
          hardware.substring(
              notApproved, hardware.indexOf('return;', notApproved)),
          isNot(contains('_sendFailedFeedback')));
    });

    test('a send that stopped with an error said taps', () {
      expect(_body(src, 'Future<void> _sendPressed('),
          contains('_sendFailedFeedback();'));
      expect(
          _count(_body(src, 'Future<void> _handleSwapSend('),
              '_sendFailedFeedback();'),
          2);
      expect(
          _count(_body(src, 'Future<void> _dispatchSend('),
              '_sendFailedFeedback();'),
          3);
      expect(
          _count(_body(src, 'Future<void> _handleBitcoinSoftwareSend('),
              '_sendFailedFeedback();'),
          2);
      // The hardware PSBT build failing (the Sign step's error card).
      expect(_body(src, 'Future<void> _handleHardwareSigning('),
          contains('_sendFailedFeedback();'));
    });

    test('the hardware broadcast taps when it fails', () {
      final watch =
          _source('lib/screens/pay/components/watch_only_screen.dart');
      expect(
          _count(_body(watch, 'Future<void> _onBroadcastImpl()'),
              'unawaited(moneyFailureFeedback());'),
          2);
    });

    test('the send\'s rubber band never taps on its own', () {
      final band = _source('lib/screens/shared/send/send_flow_widgets.dart');
      final build = band.substring(band.indexOf(
          'Widget build(BuildContext context) => RubberBandProgress('));
      expect(build.substring(0, build.indexOf(');')),
          contains('failureTap: false'));
    });
  });

  group('Dollars send (usd_send_screen.dart)', () {
    final src = _source('lib/screens/usd/usd_send_screen.dart');

    test('waits for the band and taps on every shown failure', () {
      expect(
          src,
          contains(
              'moneyFailureFeedbackAfterBand(() => mounted && _processing)'));
      final send = _body(src, 'Future<void> _send()');
      expect(_count(send, '_sendFailedFeedback();'), 2);
      expect(_body(src, 'Future<bool> _pullVenueCash('),
          contains('_sendFailedFeedback();'));
    });

    test('a declined step-up returns before the tap', () {
      final send = _body(src, 'Future<void> _send()');
      final declined = send.indexOf(
          'if (e is SettlementStopped && e.reason == SettlementStopReason.declined) {');
      expect(declined, greaterThan(0));
      final ret = send.indexOf('return;', declined);
      expect(ret, lessThan(send.lastIndexOf('_sendFailedFeedback();')));
      expect(send.substring(declined, ret), isNot(contains('_sendFailed')));
    });
  });

  group('Move sheet (deposit_sheet.dart)', () {
    final src = _source('lib/screens/home/components/deposit_sheet.dart');

    test('move_failed taps, except for a declined approval or a cancel', () {
      final track = _body(src, 'void _trackMoveFailed(');
      expect(track, contains('_moveFailedFeedback();'));
      expect(track, contains('!_isApprovalStop(e)'));
      expect(track, contains("category != 'user_cancelled'"));
      expect(track, contains("resolvedStage != 'approval'"));
      expect(_body(src, 'bool _stoppedByApproval('),
          isNot(contains('_moveFailedFeedback')));
    });

    test('the failures shown without move_failed tap too', () {
      // A purchase from Dollars whose venue cash stopped.
      final failedDirect = src.indexOf("covered ? 'venue_cash_pending'");
      expect(src.indexOf('_moveFailedFeedback();', failedDirect),
          lessThan(src.indexOf('return null;', failedDirect)));
      expect(_body(src, 'Future<void> _convertUsdToBtc()'),
          contains('_moveFailedFeedback();'));
      expect(_body(src, 'Future<void> _dispatchBtcToPredictions('),
          contains('_moveFailedFeedback();'));
      expect(_body(src, 'Future<void> _dispatchUsdToPredictions('),
          contains('_moveFailedFeedback();'));
      expect(_body(src, 'Future<void> _convert()'),
          contains('_moveFailedFeedback();'));
      // Every dispatch catch that shows an error reports move_failed.
      expect(_count(src, '_trackMoveFailed(e'), greaterThanOrEqualTo(12));
    });

    test(
        'the confirm\'s band lets go quietly; the one soft tap plays after '
        'it, as busy as the band is', () {
      final feedback = _body(src, 'void _moveFailedFeedback(');
      expect(feedback,
          contains('moneyFailureFeedbackAfterBand(() => mounted && _processing)'));
      final band = src.substring(src.indexOf('RubberBandBusy('),
          src.indexOf('child: _ConvertButton(', src.indexOf('RubberBandBusy(')));
      expect(band, contains('busy: _processing && _bandOn'));
      expect(band, contains('failureTap: false'));
    });

    test('every hot move snaps the band before the sheet closes', () {
      for (final dispatcher in [
        'Future<void> _convertUsdToBtc()',
        'Future<void> _dispatchBtcToPredictions(',
        'Future<void> _dispatchBtcToUsd(',
        'Future<void> _dispatchUsdToBtc(',
        'Future<void> _dispatchUsdToPredictions(',
        'Future<void> _dispatchUsdToHyperliquid(',
        'Future<void> _dispatchBtcToHyperliquid(',
        'Future<void> _dispatchHyperliquidToBtc(',
        'Future<void> _finishVenuePurchase(',
      ]) {
        final body = _body(src, dispatcher);
        final pop = body.contains('navigator.pop()')
            ? body.indexOf('navigator.pop()')
            : body.indexOf('.pop()');
        expect(pop, greaterThan(0), reason: dispatcher);
        expect(body.indexOf('await _snapBeforeLeaving();'),
            allOf(greaterThan(0), lessThan(pop)),
            reason: dispatcher);
      }
    });
  });

  group('receive requests', () {
    test('Bitcoin receive: an invoice that could not be made', () {
      final src =
          _source('lib/screens/receive/components/confirm_receive.dart');
      expect(_body(src, 'Future<void> _createLightningInvoice('),
          contains('unawaited(moneyFailureFeedback());'));
      // Other coins open the Dollars sheet, whose address failure taps
      // there (below); background polling never taps.
      expect(_count(src, 'moneyFailureFeedback()'), 1);
    });

    test('one-time receive: the address the person asked an amount for', () {
      final src = _source('lib/screens/receive/quoted_receive_screen.dart');
      expect(_body(src, 'Future<void> _createQuote('),
          contains('unawaited(moneyFailureFeedback());'));
      expect(_count(src, 'moneyFailureFeedback()'), 1);
    });
  });
}
