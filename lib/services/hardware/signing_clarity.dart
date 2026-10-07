// lib/services/hardware/signing_clarity.dart
//
// Clarity classification and default release gates for every venue
// action a Ledger could sign (Wallet hardening Phase 3, plan B4).
//
// "Readable" means the device shows the named fields raw in full EIP-712
// mode, without ERC-7730 filtering (`eip712.md:83, :101`). It is a claim
// about what the device DISPLAYS, never a claim that the Ledger verified
// amounts or destinations. If the device matrix (plan section D) shows a
// row needs the blind-signing setting or shows a blind-signing warning,
// that row becomes opaque and its readable claim is dropped here.
//
// Opaque rows are blocked unless an explicit flag (default off, owner
// acceptance required) opens them.

import 'package:kute/constants/feature_flags.dart';

enum SigningClarity { readable, partial, opaque }

enum LedgerActionKind {
  // Hyperliquid user-signed actions.
  hlUsdClassTransfer,
  hlUsdSend,
  hlSpotSend,
  hlApproveBuilderFee,
  hlWithdraw3,
  hlOtherUserSigned,
  // Hyperliquid L1 actions (phantom Agent, chainId 1337).
  hlOrder,
  hlCancel,
  hlUpdateLeverage,
  hlUpdateIsolatedMargin,
  hlTrailingStop,
  hlTwapOrder,
  hlTwapCancel,
  hlOtherL1Action,
  // EIP-2612 permit (Arbitrum Bridge2 deposit, hot funding only).
  erc2612Permit,
  // Polymarket.
  pmClobAuth,
  pmOrder, // sigType 3, TypedDataSign<Order>
  pmOrderEoa, // sigType 0/1/2, bare Order
  pmDepositWalletBatch,
  pmWithdrawal,
  pmLegacySafeTx,
  // Bitcoin app.
  btcPsbt,
  // No Kute caller signs personal messages today.
  personalMessage,
}

enum LedgerReleaseGate {
  /// Allowed by default.
  allowed,

  /// Allowed once O7 (HyperCore reverse source action) is confirmed.
  afterO7,

  /// Allowed as one explicit, readable prompt (O17).
  explicitOneTime,

  /// Allowed only when every batch call passes the allowlist (B9).
  allowlistOnly,

  /// Partial clarity accepted by default (O2).
  partialO2,

  /// Opaque; needs [kLedgerHyperliquidOpaqueActionsEnabled] (O1).
  flagO1,

  /// Opaque destination; needs [kLedgerPolymarketWithdrawEnabled] (O3).
  flagO3,

  /// Read-only for Ledger (O4).
  readOnly,

  /// Never exposed for a Ledger account.
  notExposed,
}

class LedgerActionClass {
  const LedgerActionClass({
    required this.clarity,
    required this.gate,
    required this.deviceShows,
  });

  final SigningClarity clarity;
  final LedgerReleaseGate gate;

  /// What the device should show, as field descriptions for review copy.
  /// Empty for opaque rows. Never evidence that content was verified.
  final List<String> deviceShows;

  /// Opaque actions always show "Your Ledger shows a code, not the
  /// details" before the prompt.
  bool get needsOpaqueNote => clarity != SigningClarity.readable;
}

LedgerActionClass classifyLedgerAction(LedgerActionKind kind) {
  switch (kind) {
    case LedgerActionKind.hlUsdClassTransfer:
      return const LedgerActionClass(
          clarity: SigningClarity.readable,
          gate: LedgerReleaseGate.allowed,
          deviceShows: ['amount', 'direction']);
    case LedgerActionKind.hlSpotSend:
      return const LedgerActionClass(
          clarity: SigningClarity.readable,
          gate: LedgerReleaseGate.allowed,
          deviceShows: ['destination', 'token', 'amount']);
    case LedgerActionKind.hlUsdSend:
      return const LedgerActionClass(
          clarity: SigningClarity.readable,
          gate: LedgerReleaseGate.allowed,
          deviceShows: ['destination', 'amount']);
    case LedgerActionKind.hlApproveBuilderFee:
      return const LedgerActionClass(
          clarity: SigningClarity.readable,
          gate: LedgerReleaseGate.explicitOneTime,
          deviceShows: ['fee rate', 'builder']);
    case LedgerActionKind.hlWithdraw3:
      return const LedgerActionClass(
          clarity: SigningClarity.readable,
          gate: LedgerReleaseGate.notExposed,
          deviceShows: ['destination', 'amount']);
    case LedgerActionKind.hlOrder:
    case LedgerActionKind.hlCancel:
    case LedgerActionKind.hlUpdateLeverage:
    case LedgerActionKind.hlUpdateIsolatedMargin:
    case LedgerActionKind.hlTrailingStop:
    case LedgerActionKind.hlTwapOrder:
    case LedgerActionKind.hlTwapCancel:
      return const LedgerActionClass(
          clarity: SigningClarity.opaque,
          gate: LedgerReleaseGate.flagO1,
          deviceShows: []);
    case LedgerActionKind.hlOtherL1Action:
    case LedgerActionKind.hlOtherUserSigned:
      return const LedgerActionClass(
          clarity: SigningClarity.opaque,
          gate: LedgerReleaseGate.notExposed,
          deviceShows: []);
    case LedgerActionKind.erc2612Permit:
      // Kute has no Ledger Arbitrum surface; funds would be stranded.
      return const LedgerActionClass(
          clarity: SigningClarity.readable,
          gate: LedgerReleaseGate.notExposed,
          deviceShows: ['spender', 'value']);
    case LedgerActionKind.pmClobAuth:
      // Moves no value; shows address, timestamp and message.
      return const LedgerActionClass(
          clarity: SigningClarity.partial,
          gate: LedgerReleaseGate.allowed,
          deviceShows: ['address', 'timestamp', 'message']);
    case LedgerActionKind.pmOrder:
      return const LedgerActionClass(
          clarity: SigningClarity.partial,
          gate: LedgerReleaseGate.partialO2,
          deviceShows: ['token ID', 'raw base units']);
    case LedgerActionKind.pmOrderEoa:
      // Ledger orders use sigType 3 with a deposit wallet (B9).
      return const LedgerActionClass(
          clarity: SigningClarity.partial,
          gate: LedgerReleaseGate.notExposed,
          deviceShows: ['token ID', 'raw base units']);
    case LedgerActionKind.pmDepositWalletBatch:
      return const LedgerActionClass(
          clarity: SigningClarity.opaque,
          gate: LedgerReleaseGate.allowlistOnly,
          deviceShows: ['call targets']);
    case LedgerActionKind.pmWithdrawal:
      return const LedgerActionClass(
          clarity: SigningClarity.opaque,
          gate: LedgerReleaseGate.flagO3,
          deviceShows: []);
    case LedgerActionKind.pmLegacySafeTx:
      return const LedgerActionClass(
          clarity: SigningClarity.opaque,
          gate: LedgerReleaseGate.readOnly,
          deviceShows: []);
    case LedgerActionKind.btcPsbt:
      return const LedgerActionClass(
          clarity: SigningClarity.readable,
          gate: LedgerReleaseGate.allowed,
          deviceShows: ['outputs', 'amounts', 'fee']);
    case LedgerActionKind.personalMessage:
      return const LedgerActionClass(
          clarity: SigningClarity.readable,
          gate: LedgerReleaseGate.notExposed,
          deviceShows: ['message']);
  }
}

/// Whether a Ledger may be asked to sign [kind] at all. The flags default
/// to the compile-time release flags; tests pass explicit values.
///
/// [LedgerReleaseGate.allowlistOnly] returns true here: the allowlist is
/// enforced by the Polymarket executor (P3.8) before it builds the
/// request, and a batch containing an ERC-20 transfer is classified as
/// [LedgerActionKind.pmWithdrawal], which stays behind O3.
bool isLedgerActionAllowed(
  LedgerActionKind kind, {
  bool opaqueHyperliquidEnabled = kLedgerHyperliquidOpaqueActionsEnabled,
  bool polymarketWithdrawEnabled = kLedgerPolymarketWithdrawEnabled,
  bool o7Confirmed = false,
}) {
  switch (classifyLedgerAction(kind).gate) {
    case LedgerReleaseGate.allowed:
    case LedgerReleaseGate.explicitOneTime:
    case LedgerReleaseGate.allowlistOnly:
    case LedgerReleaseGate.partialO2:
      return true;
    case LedgerReleaseGate.afterO7:
      return o7Confirmed;
    case LedgerReleaseGate.flagO1:
      return opaqueHyperliquidEnabled;
    case LedgerReleaseGate.flagO3:
      return polymarketWithdrawEnabled;
    case LedgerReleaseGate.readOnly:
    case LedgerReleaseGate.notExposed:
      return false;
  }
}

/// Thrown before any device command when [isLedgerActionAllowed] is false.
class LedgerActionBlockedException implements Exception {
  const LedgerActionBlockedException(this.kind);
  final LedgerActionKind kind;

  @override
  String toString() => 'LedgerActionBlockedException(${kind.name})';
}

// ───────────────────────────── kind mapping ─────────────────────────────

LedgerActionKind hyperliquidL1ActionKind(Map<String, dynamic> action) {
  switch (action['type']) {
    case 'order':
      return LedgerActionKind.hlOrder;
    case 'cancel':
    case 'cancelByCloid':
      return LedgerActionKind.hlCancel;
    case 'updateLeverage':
      return LedgerActionKind.hlUpdateLeverage;
    case 'updateIsolatedMargin':
      return LedgerActionKind.hlUpdateIsolatedMargin;
    case 'trailingStop':
      return LedgerActionKind.hlTrailingStop;
    case 'twapOrder':
      return LedgerActionKind.hlTwapOrder;
    case 'twapCancel':
      return LedgerActionKind.hlTwapCancel;
    default:
      return LedgerActionKind.hlOtherL1Action;
  }
}

LedgerActionKind hyperliquidUserSignedKind(String primaryType) {
  switch (primaryType) {
    case 'HyperliquidTransaction:UsdClassTransfer':
      return LedgerActionKind.hlUsdClassTransfer;
    case 'HyperliquidTransaction:UsdSend':
      return LedgerActionKind.hlUsdSend;
    case 'HyperliquidTransaction:SpotSend':
      return LedgerActionKind.hlSpotSend;
    case 'HyperliquidTransaction:ApproveBuilderFee':
      return LedgerActionKind.hlApproveBuilderFee;
    case 'HyperliquidTransaction:Withdraw':
      return LedgerActionKind.hlWithdraw3;
    default:
      return LedgerActionKind.hlOtherUserSigned;
  }
}

/// ERC-20 `transfer(address,uint256)` selector.
const String kErc20TransferSelector = 'a9059cbb';

/// A DepositWallet batch containing any ERC-20 transfer moves value to a
/// destination hidden in calldata, so it is a withdrawal (O3).
LedgerActionKind depositWalletBatchKind(Iterable<String> callData) {
  for (final data in callData) {
    final clean =
        (data.startsWith('0x') ? data.substring(2) : data).toLowerCase();
    if (clean.startsWith(kErc20TransferSelector)) {
      return LedgerActionKind.pmWithdrawal;
    }
  }
  return LedgerActionKind.pmDepositWalletBatch;
}
