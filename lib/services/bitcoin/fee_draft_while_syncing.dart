// lib/services/bitcoin/fee_draft_while_syncing.dart
//
// A scan (background sync or pull-to-refresh) holds the wallet's native
// slot, and native admission rejects every other request with 'busy'
// while it runs. The Send flow used to surface that as an error the
// moment the user typed an amount. This file keeps fee work going during
// a scan:
//   - `buildPsbtWhenIdle` parks the draft build until the slot is free,
//     so the review keeps its loading state and the PSBT still comes
//     from the wallet's own state. Nothing about the amount, fee, input
//     and output binding to signing changes.
//   - `estimateDraftFeeSats` sizes the fee from the last synced coins so
//     the review can show an estimate meanwhile. It is display only;
//     the reviewed PSBT stays the source of truth for signing.
//
// Recommended fee rates never needed the wallet: see
// `bitcoinFeeRatePerBlockProvider`.

import 'dart:async';

import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

/// How long the hardware Sign step may spend waiting for the wallet's
/// native slot before it gives up and shows its error with Try again.
/// Short on purpose: that step has no other terminal state, so an
/// unbounded wait reads to the user as a fee that never arrives.
const Duration kSignStepSlotBudget = Duration(seconds: 15);

/// Builds [transaction] on [model]'s wallet once no other request holds
/// its native slot. Only admission failures retry; a native request that
/// timed out may still be running, so it is never re-issued here.
///
/// [budget] bounds the WHOLE call — every idle wait and every retry share
/// it, so the caller gets a PSBT or a 'busy' error within it rather than
/// one fresh timeout per attempt. It defaults to one incremental sync,
/// which the send screens already word as the wallet still syncing.
///
/// The call holds a slot reservation for its lifetime: a scan already
/// running still has to finish, but no NEW scan may start and re-take the
/// slot the moment the wait resolves. Nothing about the amount, fee,
/// inputs and outputs binding to signing changes.
Future<Psbt> buildPsbtWhenIdle(
  BitcoinModel model,
  TransactionBuilder transaction, {
  required bool drain,
  Duration? budget,
}) {
  final session = model.config.session;
  final service = session.service;
  final deadline = DateTime.now().add(budget ?? service.syncTimeout);
  Duration remaining() {
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  return service.withSlotReservation(session.walletId, () async {
    const maxAttempts = 3;
    for (var attempt = 1;; attempt++) {
      final wait = remaining();
      if (wait == Duration.zero) throw const OnchainException('busy');
      await service.whenIdle(session.walletId).timeout(
            wait,
            onTimeout: () => throw const OnchainException('busy'),
          );
      // The builder spends this wallet's own coins. With none loaded,
      // `drainWallet` + `drainTo` and a plain build both fail inside
      // `finish`, and both native plugins report every failure that is
      // not InsufficientFunds as one generic code — which the send flow
      // could only word as "Couldn't prepare this payment", naming
      // nothing the person could act on. Say what is actually true: the
      // send flow syncs this wallet while it is open, so the state
      // clears itself and the draft is rebuilt.
      if (!model.listUnspent().any((coin) => !coin.isSpent)) {
        throw const OnchainException('busy');
      }
      try {
        return drain
            ? await model.drainWalletBitcoinTransaction(transaction)
            : await model.buildBitcoinTransaction(transaction);
      } on OnchainException catch (error) {
        if (error.code != 'busy' ||
            attempt >= maxAttempts ||
            remaining() == Duration.zero) {
          rethrow;
        }
      }
    }
  });
}

/// Network fee in sats for sending [amountSats] to [toAddress] at
/// [feeRateSatVb], sized from the wallet's last synced coins. Coins are
/// picked largest first, or exactly [selectedUtxos] when the user chose
/// them. Null when there is nothing to size from or the coins cannot
/// cover the amount and fee. Never used for signing.
int? estimateDraftFeeSats({
  required List<LocalOutput> utxos,
  required int amountSats,
  required String toAddress,
  required double feeRateSatVb,
  required bool drain,
  List<OutPoint>? selectedUtxos,
  String? scriptType,
}) {
  if (!feeRateSatVb.isFinite || feeRateSatVb <= 0) return null;
  if (!drain && amountSats <= 0) return null;
  final rate = feeRateSatVb.ceil();
  final manual = selectedUtxos != null && selectedUtxos.isNotEmpty;
  final coins = utxos
      .where(
          (u) => !u.isSpent && (!manual || selectedUtxos.contains(u.outpoint)))
      .toList()
    ..sort((a, b) => b.txout.value.toSat().compareTo(a.txout.value.toSat()));
  if (coins.isEmpty) return null;

  final input = _inputVBytes(scriptType);
  final overhead = _overheadVBytes(scriptType);
  final destination = _outputVBytes(toAddress);
  final change = _changeVBytes(scriptType);
  int feeFor(int inputs, {required bool withChange}) =>
      ((overhead + inputs * input + destination + (withChange ? change : 0)) *
              rate)
          .ceil();

  if (drain || manual) {
    final total = coins.fold<int>(0, (sum, u) => sum + u.txout.value.toSat());
    final fee = feeFor(coins.length, withChange: !drain);
    if (drain) return total > fee ? fee : null;
    return total >= amountSats + fee ? fee : null;
  }

  var total = 0;
  for (var i = 0; i < coins.length; i++) {
    total += coins[i].txout.value.toSat();
    final fee = feeFor(i + 1, withChange: true);
    if (total >= amountSats + fee) return fee;
  }
  return null;
}

double _inputVBytes(String? scriptType) => switch (scriptType) {
      'bip86' => 57.5,
      'bip49' => 91,
      'bip44' => 148,
      _ => 68,
    };

double _changeVBytes(String? scriptType) => switch (scriptType) {
      'bip86' => 43,
      'bip49' => 32,
      'bip44' => 34,
      _ => 31,
    };

double _overheadVBytes(String? scriptType) => scriptType == 'bip44' ? 10 : 10.5;

double _outputVBytes(String address) {
  final a = address.trim().toLowerCase();
  if (a.startsWith('bc1p') || a.startsWith('tb1p') || a.startsWith('bcrt1p')) {
    return 43;
  }
  if (a.startsWith('bc1q') || a.startsWith('tb1q') || a.startsWith('bcrt1q')) {
    return a.length > 50 ? 43 : 31;
  }
  if (a.startsWith('3') || a.startsWith('2')) return 32;
  return 34;
}
