import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/services/hardware/signing_clarity.dart';

void main() {
  test('only accepted opaque Ledger actions can be enabled by the build', () {
    expect(kLedgerInvestingEnabled, isTrue);
    // O1 and O3 were accepted and default on since ee44dc1d; the build
    // define still decides, so a build with `=false` keeps them blocked.
    expect(
        kLedgerHyperliquidOpaqueActionsEnabled,
        const bool.fromEnvironment('KUTE_LEDGER_HYPERLIQUID_OPAQUE_ACCEPTED',
            defaultValue: true));
    expect(
        kLedgerPolymarketWithdrawEnabled,
        const bool.fromEnvironment('KUTE_LEDGER_POLYMARKET_WITHDRAW_ACCEPTED',
            defaultValue: true));
    expect(kDirectHypercoreFundingEnabled, isTrue);
    expect(kLedgerUsbTransportEnabled, isTrue);
    expect(kLedgerCashAppAddressCheckEnabled, isTrue);
  });

  group('plan B4 rows', () {
    void row(LedgerActionKind kind, SigningClarity clarity,
        LedgerReleaseGate gate, bool allowedByDefault) {
      final c = classifyLedgerAction(kind);
      expect(c.clarity, clarity, reason: kind.name);
      expect(c.gate, gate, reason: kind.name);
      expect(isLedgerActionAllowed(kind), allowedByDefault, reason: kind.name);
      expect(c.needsOpaqueNote, clarity != SigningClarity.readable,
          reason: kind.name);
      if (clarity == SigningClarity.opaque &&
          kind != LedgerActionKind.pmDepositWalletBatch) {
        expect(c.deviceShows, isEmpty, reason: kind.name);
      }
    }

    test('Hyperliquid usdClassTransfer is readable and allowed', () {
      row(LedgerActionKind.hlUsdClassTransfer, SigningClarity.readable,
          LedgerReleaseGate.allowed, true);
    });

    test('native spotSend and perpetuals usdSend are readable and allowed', () {
      row(LedgerActionKind.hlSpotSend, SigningClarity.readable,
          LedgerReleaseGate.allowed, true);
      row(LedgerActionKind.hlUsdSend, SigningClarity.readable,
          LedgerReleaseGate.allowed, true);
    });

    test('Hyperliquid approveBuilderFee is an explicit readable prompt', () {
      row(LedgerActionKind.hlApproveBuilderFee, SigningClarity.readable,
          LedgerReleaseGate.explicitOneTime, true);
    });

    test('Hyperliquid withdraw3 is never exposed for Ledger', () {
      row(LedgerActionKind.hlWithdraw3, SigningClarity.readable,
          LedgerReleaseGate.notExposed, false);
    });

    test('Hyperliquid Agent actions are opaque behind O1', () {
      for (final kind in [
        LedgerActionKind.hlOrder,
        LedgerActionKind.hlCancel,
        LedgerActionKind.hlUpdateLeverage,
        LedgerActionKind.hlTwapOrder,
        LedgerActionKind.hlTwapCancel,
      ]) {
        row(kind, SigningClarity.opaque, LedgerReleaseGate.flagO1,
            kLedgerHyperliquidOpaqueActionsEnabled);
        expect(isLedgerActionAllowed(kind, opaqueHyperliquidEnabled: false),
            isFalse);
        expect(isLedgerActionAllowed(kind, opaqueHyperliquidEnabled: true),
            isTrue);
      }
    });

    test('Polymarket ClobAuth moves no value and is allowed', () {
      row(LedgerActionKind.pmClobAuth, SigningClarity.partial,
          LedgerReleaseGate.allowed, true);
    });

    test('Polymarket sigType 3 order is partial under O2', () {
      row(LedgerActionKind.pmOrder, SigningClarity.partial,
          LedgerReleaseGate.partialO2, true);
    });

    test('Polymarket batch calldata is opaque and needs the allowlist', () {
      row(LedgerActionKind.pmDepositWalletBatch, SigningClarity.opaque,
          LedgerReleaseGate.allowlistOnly, true);
    });

    test('Polymarket withdrawal is opaque behind O3', () {
      row(LedgerActionKind.pmWithdrawal, SigningClarity.opaque,
          LedgerReleaseGate.flagO3, kLedgerPolymarketWithdrawEnabled);
      expect(
          isLedgerActionAllowed(LedgerActionKind.pmWithdrawal,
              polymarketWithdrawEnabled: false),
          isFalse);
      expect(
          isLedgerActionAllowed(LedgerActionKind.pmWithdrawal,
              polymarketWithdrawEnabled: true),
          isTrue);
    });

    test('Polymarket legacy Safe tx is read-only (O4)', () {
      row(LedgerActionKind.pmLegacySafeTx, SigningClarity.opaque,
          LedgerReleaseGate.readOnly, false);
    });

    test('Ledger BTC PSBT is readable and allowed', () {
      row(LedgerActionKind.btcPsbt, SigningClarity.readable,
          LedgerReleaseGate.allowed, true);
    });

    test('rows outside the Ledger scope stay blocked', () {
      for (final kind in [
        LedgerActionKind.erc2612Permit,
        LedgerActionKind.pmOrderEoa,
        LedgerActionKind.hlOtherL1Action,
        LedgerActionKind.hlOtherUserSigned,
        LedgerActionKind.personalMessage,
      ]) {
        expect(isLedgerActionAllowed(kind), isFalse, reason: kind.name);
      }
    });
  });

  group('kind mapping', () {
    test('Hyperliquid L1 action types', () {
      expect(
          hyperliquidL1ActionKind({'type': 'order'}), LedgerActionKind.hlOrder);
      expect(hyperliquidL1ActionKind({'type': 'cancelByCloid'}),
          LedgerActionKind.hlCancel);
      // The HLP vault product is gone: a vault transfer is no longer a
      // kind of its own and falls into the never-exposed bucket.
      expect(hyperliquidL1ActionKind({'type': 'vaultTransfer'}),
          LedgerActionKind.hlOtherL1Action);
      expect(hyperliquidL1ActionKind({'type': 'approveAgent'}),
          LedgerActionKind.hlOtherL1Action);
    });

    test('Hyperliquid user-signed primary types', () {
      expect(
          hyperliquidUserSignedKind('HyperliquidTransaction:UsdClassTransfer'),
          LedgerActionKind.hlUsdClassTransfer);
      expect(hyperliquidUserSignedKind('HyperliquidTransaction:Withdraw'),
          LedgerActionKind.hlWithdraw3);
      expect(hyperliquidUserSignedKind('HyperliquidTransaction:ApproveAgent'),
          LedgerActionKind.hlOtherUserSigned);
    });

    test('a batch with any ERC-20 transfer is a withdrawal', () {
      expect(depositWalletBatchKind(['0x095ea7b3${'00' * 64}']),
          LedgerActionKind.pmDepositWalletBatch);
      expect(
          depositWalletBatchKind(
              ['0x095ea7b3${'00' * 64}', '0xA9059CBB${'00' * 64}']),
          LedgerActionKind.pmWithdrawal);
    });
  });
}
