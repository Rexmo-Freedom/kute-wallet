// A Ledger venue move whose funding source is switched to Cash App must
// reach the Cash App onramp (delivering to the Ledger's verified venue
// account) instead of dead-ending, while every BTC-source Ledger check
// stays exactly as strict as before.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';

import '../../helpers/source_scan.dart';

const _ledger = 'ledger-1';

LedgerMoveRoute _route({
  bool featureEnabled = true,
  bool hasVenueWallet = false,
  bool identityOk = true,
  required MoveLockedSide lockedSide,
  bool fromBtc = false,
  bool fromHyperliquid = false,
  bool sourceCashApp = false,
  bool sourceFiat = false,
  String? sourceWalletId,
  String? destWalletId,
  bool destPredictions = false,
  bool destHyperliquid = false,
  bool destFiat = false,
}) =>
    ledgerMoveRoute(
      featureEnabled: featureEnabled,
      hasVenueWallet: hasVenueWallet,
      identityVerifiedAndUnchanged: identityOk,
      ledgerWalletId: _ledger,
      lockedSide: lockedSide,
      fromBtc: fromBtc,
      fromHyperliquid: fromHyperliquid,
      sourceCashApp: sourceCashApp,
      sourceFiat: sourceFiat,
      sourceWalletId: sourceWalletId,
      destWalletId: destWalletId,
      destPredictions: destPredictions,
      destHyperliquid: destHyperliquid,
      destFiat: destFiat,
    );

/// The state `_switchToFiatVenueSource(cashApp)` leaves the sheet in.
LedgerMoveRoute _cashAppSwitched({
  required bool predictions,
  bool identityOk = true,
  bool hasVenueWallet = false,
  bool sourceFiat = false,
  bool sourceCashApp = true,
}) =>
    _route(
      lockedSide: predictions
          ? MoveLockedSide.buyToPredictions
          : MoveLockedSide.buyToHyperliquid,
      identityOk: identityOk,
      hasVenueWallet: hasVenueWallet,
      sourceCashApp: sourceCashApp,
      sourceFiat: sourceFiat,
      destPredictions: predictions,
      destHyperliquid: !predictions,
    );

void main() {
  group('Ledger move with a Cash App source', () {
    test('Predictions and Investing both route to the Cash App onramp', () {
      expect(
          _cashAppSwitched(predictions: true), LedgerMoveRoute.cashAppOnramp);
      expect(
          _cashAppSwitched(predictions: false), LedgerMoveRoute.cashAppOnramp);
    });

    test('a changed or unverified Ledger identity blocks it', () {
      expect(_cashAppSwitched(predictions: true, identityOk: false),
          LedgerMoveRoute.blocked);
    });

    test('a bank source or a caller venue wallet never routes', () {
      expect(
          _cashAppSwitched(
              predictions: true, sourceCashApp: false, sourceFiat: true),
          LedgerMoveRoute.blocked);
      expect(_cashAppSwitched(predictions: false, hasVenueWallet: true),
          LedgerMoveRoute.blocked);
    });

    test('a destination that disagrees with the lock is blocked', () {
      expect(
          _route(
            lockedSide: MoveLockedSide.buyToPredictions,
            sourceCashApp: true,
            destHyperliquid: true,
          ),
          LedgerMoveRoute.blocked);
      expect(
          _route(
            lockedSide: MoveLockedSide.buyToHyperliquid,
            sourceCashApp: true,
            destHyperliquid: true,
            destWalletId: 'hot-wallet',
          ),
          LedgerMoveRoute.blocked);
    });

    test('a bitcoin or wallet source under a buy lock is never Cash App', () {
      expect(
          _route(
            lockedSide: MoveLockedSide.buyToPredictions,
            sourceCashApp: true,
            fromBtc: true,
            destPredictions: true,
          ),
          LedgerMoveRoute.blocked);
      expect(
          _route(
            lockedSide: MoveLockedSide.buyToPredictions,
            sourceCashApp: true,
            sourceWalletId: _ledger,
            destPredictions: true,
          ),
          LedgerMoveRoute.blocked);
    });

    test('the feature flag off blocks it', () {
      expect(
          _route(
            featureEnabled: false,
            lockedSide: MoveLockedSide.buyToPredictions,
            sourceCashApp: true,
            destPredictions: true,
          ),
          LedgerMoveRoute.blocked);
    });
  });

  group('Ledger BTC-source checks are unchanged', () {
    test('deposit from the Ledger itself runs the device flow', () {
      for (final lock in [
        MoveLockedSide.depositToPredictions,
        MoveLockedSide.depositToHyperliquid,
      ]) {
        expect(_route(lockedSide: lock, fromBtc: true, sourceWalletId: _ledger),
            LedgerMoveRoute.deviceFlow);
        // Any other source wallet, a destination wallet, a changed
        // identity or a fiat/Cash App flag blocks it.
        expect(_route(lockedSide: lock, fromBtc: true, sourceWalletId: 'hot'),
            LedgerMoveRoute.blocked);
        expect(
            _route(
                lockedSide: lock,
                fromBtc: true,
                sourceWalletId: _ledger,
                destWalletId: 'x'),
            LedgerMoveRoute.blocked);
        expect(
            _route(
                lockedSide: lock,
                fromBtc: true,
                sourceWalletId: _ledger,
                identityOk: false),
            LedgerMoveRoute.blocked);
        expect(
            _route(
                lockedSide: lock,
                fromBtc: true,
                sourceWalletId: _ledger,
                sourceCashApp: true),
            LedgerMoveRoute.blocked);
      }
    });

    test('withdraw lands only on the Ledger', () {
      for (final lock in [
        MoveLockedSide.withdrawFromPredictions,
        MoveLockedSide.withdrawFromHyperliquid,
      ]) {
        expect(_route(lockedSide: lock, destWalletId: _ledger),
            LedgerMoveRoute.deviceFlow);
        expect(_route(lockedSide: lock, destWalletId: 'hot'),
            LedgerMoveRoute.blocked);
        expect(_route(lockedSide: lock, fromBtc: true, destWalletId: _ledger),
            LedgerMoveRoute.blocked);
      }
    });

    test('unrelated locks never run in a Ledger context', () {
      for (final lock in [
        MoveLockedSide.depositToUsd,
        MoveLockedSide.depositFromFiat,
        MoveLockedSide.withdrawToFiat,
      ]) {
        expect(
            _route(
                lockedSide: lock,
                fromBtc: true,
                sourceWalletId: _ledger,
                sourceCashApp: true),
            LedgerMoveRoute.blocked);
      }
    });
  });

  test('the sheet dispatches a Ledger Cash App source to the onramp', () {
    final source = stripComments(
        File('lib/screens/home/components/deposit_sheet.dart')
            .readAsStringSync());
    final start = source.indexOf('Future<void> _convert() async {');
    expect(start, greaterThan(0));
    final body = source.substring(
        start, source.indexOf('_typedExceedsAvailable', start));
    // Inside the Ledger branch, Cash App goes to the onramp (only when the
    // route allows it) and everything else to the device flow.
    final ledgerBranch = body.indexOf('if (_isLedgerMove) {');
    expect(ledgerBranch, greaterThanOrEqualTo(0));
    final cashApp = body.indexOf(
        'if (_ledgerCashAppSourceValid) return _createCashAppOnramp();',
        ledgerBranch);
    final device = body.indexOf('return _convertLedger();', ledgerBranch);
    expect(cashApp, greaterThan(ledgerBranch));
    expect(device, greaterThan(cashApp));
    // The onramp resolves the Ledger-verified venue recipient from the
    // Ledger pinned before any await, never from a hot wallet.
    expect(
        source.contains('await _ledgerCashAppRecipient(destination, '
            'ledgerVenueWalletId)'),
        isTrue);
  });
}
