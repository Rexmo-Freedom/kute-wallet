// lib/services/hardware/ledger/deposit_wallet_call_allowlist.dart
//
// Allowlist for Polymarket DepositWallet batch calls signed by a Ledger
// (Wallet hardening Phase 3, plan B9).
//
// The device shows batch calldata as hex, so the phone decides what may
// be asked for. Every call must decode exactly; anything else is rejected
// before any device prompt:
//   * value is always zero,
//   * targets are pinned Polymarket contracts (USDC.e, pUSD, CTF, the
//     collateral onramp and offramp, the redeem adapters),
//   * selectors are approve, setApprovalForAll, wrap, unwrap,
//     redeemPositions or transfer,
//   * an approve spender or approval operator is pinned,
//   * wrap and unwrap send only to this deposit wallet,
//   * a transfer goes only to the bound Orchestra deposit address of a
//     quote whose refund and recipient both belong to this Ledger, and only
//     while the O3 flag is on.
//
// These pins do not help against a compromised phone (plan section E):
// the Ledger proves approval here, not content.

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/polymarket/deposit_wallet_batch_signer.dart';

enum DepositWalletCallOp { approve, setApprovalForAll, wrap, unwrap, redeem, transfer }

class DepositWalletCallRejected implements Exception {
  const DepositWalletCallRejected(this.index, this.reason);
  final int index;
  final String reason;

  @override
  String toString() => 'DepositWalletCallRejected(#$index: $reason)';
}

/// The quote a withdrawal transfer is bound to (O3).
class LedgerWithdrawalBinding {
  const LedgerWithdrawalBinding({
    required this.depositAddress,
    required this.refundAddress,
    required this.recipientAddress,
  });

  /// Orchestra deposit address on Polygon.
  final String depositAddress;

  /// Where a failed swap refunds; must belong to this Ledger.
  final String refundAddress;

  /// Where the swap delivers; must belong to this Ledger.
  final String recipientAddress;
}

const String kSelectorApprove = '095ea7b3';
const String kSelectorSetApprovalForAll = 'a22cb465';
const String kSelectorWrap = '62355638';
const String kSelectorUnwrap = '8cc7104f';
const String kSelectorRedeemPositions = '01b7037c';
const String kSelectorTransfer = 'a9059cbb';

String _l(String a) => a.toLowerCase();

final Set<String> _tokens = {
  _l(PolymarketConstants.usdcEAddress),
  _l(PolymarketConstants.pusdAddress),
};

final Set<String> _approveSpenders = {
  _l(PolymarketConstants.exchangeAddress),
  _l(PolymarketConstants.negRiskExchangeAddress),
  _l(PolymarketConstants.collateralOnrampAddress),
  _l(PolymarketConstants.collateralOfframpAddress),
  _l(PolymarketConstants.ctfCollateralAdapterAddress),
  _l(PolymarketConstants.negRiskCtfCollateralAdapterAddress),
  _l(PolymarketConstants.ctfAddress),
};

// The deprecated CLOB v1 Neg Risk Adapter (0xd91E…) is deliberately not
// pinned anywhere below: no batch may approve, operate or redeem through it.
final Set<String> _ctfOperators = {
  _l(PolymarketConstants.exchangeAddress),
  _l(PolymarketConstants.negRiskExchangeAddress),
  _l(PolymarketConstants.ctfCollateralAdapterAddress),
  _l(PolymarketConstants.negRiskCtfCollateralAdapterAddress),
};

final Set<String> _redeemTargets = {
  _l(PolymarketConstants.ctfCollateralAdapterAddress),
  _l(PolymarketConstants.negRiskCtfCollateralAdapterAddress),
  _l(PolymarketConstants.ctfAddress),
};

class DepositWalletCallAllowlist {
  DepositWalletCallAllowlist({
    required this.depositWallet,
    this.withdrawalBinding,
    bool Function(String address)? belongsToLedger,
    this.withdrawEnabled = kLedgerPolymarketWithdrawEnabled,
  }) : _belongsToLedger = belongsToLedger ?? ((_) => false);

  final String depositWallet;
  final LedgerWithdrawalBinding? withdrawalBinding;
  final bool withdrawEnabled;
  final bool Function(String address) _belongsToLedger;

  /// Returns the decoded operation of every call, or throws
  /// [DepositWalletCallRejected] for the first call that is not allowed.
  List<DepositWalletCallOp> validate(List<DepositWalletCall> calls) {
    if (calls.isEmpty) {
      throw const DepositWalletCallRejected(0, 'empty batch');
    }
    return [for (var i = 0; i < calls.length; i++) _check(i, calls[i])];
  }

  DepositWalletCallOp _check(int i, DepositWalletCall call) {
    Never reject(String reason) => throw DepositWalletCallRejected(i, reason);

    if (call.value != BigInt.zero) reject('non-zero value');
    final target = call.target.toLowerCase();
    if (!RegExp(r'^0x[0-9a-f]{40}$').hasMatch(target)) reject('bad target');
    var data = call.data.toLowerCase();
    if (data.startsWith('0x')) data = data.substring(2);
    if (data.length < 8 || data.length.isOdd ||
        !RegExp(r'^[0-9a-f]*$').hasMatch(data)) {
      reject('malformed calldata');
    }
    final selector = data.substring(0, 8);
    final args = data.substring(8);
    if (args.length % 64 != 0) reject('calldata not word aligned');
    final words = [
      for (var w = 0; w < args.length; w += 64) args.substring(w, w + 64),
    ];

    String address(int index) {
      final word = words[index];
      if (!word.startsWith('0' * 24)) reject('dirty address word');
      return '0x${word.substring(24)}';
    }

    BigInt uint(int index) => BigInt.parse(words[index], radix: 16);
    final wallet = depositWallet.toLowerCase();

    switch (selector) {
      case kSelectorApprove:
        if (words.length != 2) reject('approve arity');
        if (!_tokens.contains(target)) reject('approve target not pinned');
        if (!_approveSpenders.contains(address(0))) {
          reject('approve spender not pinned');
        }
        return DepositWalletCallOp.approve;
      case kSelectorSetApprovalForAll:
        if (words.length != 2) reject('setApprovalForAll arity');
        if (target != _l(PolymarketConstants.ctfAddress)) {
          reject('setApprovalForAll target not CTF');
        }
        if (!_ctfOperators.contains(address(0))) {
          reject('operator not pinned');
        }
        if (uint(1) != BigInt.one) reject('only approvals are allowed');
        return DepositWalletCallOp.setApprovalForAll;
      case kSelectorWrap:
      case kSelectorUnwrap:
        final isWrap = selector == kSelectorWrap;
        if (words.length != 3) reject('wrap arity');
        final expectedTarget = isWrap
            ? PolymarketConstants.collateralOnrampAddress
            : PolymarketConstants.collateralOfframpAddress;
        if (target != _l(expectedTarget)) reject('wrap target not pinned');
        if (address(0) != _l(PolymarketConstants.usdcEAddress)) {
          reject('wrap asset not USDC.e');
        }
        if (address(1) != wallet) reject('wrap recipient is not this wallet');
        if (uint(2) == BigInt.zero) reject('zero amount');
        return isWrap ? DepositWalletCallOp.wrap : DepositWalletCallOp.unwrap;
      case kSelectorRedeemPositions:
        // redeemPositions(address, bytes32, bytes32 conditionId, uint256[])
        if (!_redeemTargets.contains(target)) reject('redeem target not pinned');
        if (words.length < 5) reject('redeem arity');
        if (uint(3) != BigInt.from(128)) reject('redeem array offset');
        final length = uint(4);
        if (length > BigInt.from(8) ||
            words.length != 5 + length.toInt()) {
          reject('redeem array length');
        }
        final collateral = address(0);
        if (target == _l(PolymarketConstants.ctfAddress)) {
          if (!_tokens.contains(collateral)) reject('redeem collateral');
        } else if (collateral != '0x${'0' * 40}') {
          reject('adapter placeholder must be zero');
        }
        return DepositWalletCallOp.redeem;
      case kSelectorTransfer:
        if (words.length != 2) reject('transfer arity');
        if (!_tokens.contains(target)) reject('transfer token not pinned');
        if (!withdrawEnabled) reject('withdrawal is disabled');
        final binding = withdrawalBinding;
        if (binding == null) reject('transfer without a bound quote');
        if (address(0) != binding.depositAddress.toLowerCase()) {
          reject('transfer recipient is not the bound deposit address');
        }
        if (!_belongsToLedger(binding.refundAddress) ||
            !_belongsToLedger(binding.recipientAddress)) {
          reject('quote refund or recipient is not this Ledger');
        }
        if (uint(1) == BigInt.zero) reject('zero amount');
        return DepositWalletCallOp.transfer;
      default:
        reject('selector not allowed');
    }
  }
}

// ── Calldata encoders for Ledger batches ──────────────────────────────

String _addressWord(String address) =>
    address.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');

String _uintWord(BigInt value) {
  if (value.isNegative) throw ArgumentError('negative uint');
  return value.toRadixString(16).padLeft(64, '0');
}

String encodeApproveCall(String spender, BigInt amount) =>
    '0x$kSelectorApprove${_addressWord(spender)}${_uintWord(amount)}';

String encodeWrapCall(String asset, String to, BigInt amount) =>
    '0x$kSelectorWrap${_addressWord(asset)}${_addressWord(to)}${_uintWord(amount)}';

String encodeUnwrapCall(String asset, String to, BigInt amount) =>
    '0x$kSelectorUnwrap${_addressWord(asset)}${_addressWord(to)}${_uintWord(amount)}';

String encodeTransferCall(String to, BigInt amount) =>
    '0x$kSelectorTransfer${_addressWord(to)}${_uintWord(amount)}';

/// Adapter redeem: `redeemPositions(0x0, 0x0, conditionId, [])`. Only the
/// condition ID is used by the collateral adapters.
String encodeAdapterRedeemCall(String conditionId) {
  final condition = conditionId.toLowerCase().replaceFirst('0x', '');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(condition)) {
    throw ArgumentError('conditionId must be bytes32');
  }
  return '0x$kSelectorRedeemPositions${'0' * 64}${'0' * 64}$condition'
      '${_uintWord(BigInt.from(128))}${_uintWord(BigInt.zero)}';
}
