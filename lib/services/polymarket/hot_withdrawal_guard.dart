import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';

/// An uncertain withdrawal is never a reason to sign another batch. This
/// journal stores public transaction references, plus the amount being sent
/// and the deposit wallet's spendable balance just before it, written before
/// any relayer POST. It stays on the device and is never tracked or logged.
/// THIS attempt reached the relayer and carries a transaction that has
/// not settled yet. Money may well have left, so this is the one case
/// the settlement runner should treat as unresolved.
class PendingPolymarketWithdrawal implements Exception {
  const PendingPolymarketWithdrawal();

  @override
  String toString() =>
      'Your withdrawal was sent and has not settled yet. It is being '
      'tracked and will not be sent again.';
}

/// An earlier withdrawal is unresolved, so this tap sent nothing. It
/// used to share a class with the case above and read as one sentence,
/// which told somebody whose transfer had not been attempted that we
/// could not say whether it left.
class EarlierPolymarketWithdrawalPending
    implements Exception, SettlementFundingNotStarted {
  const EarlierPolymarketWithdrawalPending();

  @override
  String toString() =>
      'An earlier withdrawal is still being confirmed. No new withdrawal '
      'was sent.';
}

class ResolvedPolymarketWithdrawal
    implements Exception, SettlementFundingNotStarted {
  const ResolvedPolymarketWithdrawal({required this.confirmed});
  final bool confirmed;

  @override
  String toString() => confirmed
      ? 'The previous withdrawal was confirmed. No new withdrawal was sent. '
          'Check your balance before starting another withdrawal.'
      : 'The previous withdrawal failed. No new withdrawal was sent. '
          'Review the amount and destination again to retry.';
}

typedef WithdrawalStatus = ({String state, String? hash});

/// [amountMicros] is what the batch sends and [balanceMicros] the deposit
/// wallet's spendable balance it was sized against. Both let a record whose
/// relayer reference was lost be settled later from the wallet's balance.
typedef WithdrawalBeforeSubmit = Future<void> Function(String nonce,
    {BigInt? amountMicros, BigInt? balanceMicros});
typedef WithdrawalSubmit = Future<String> Function({
  required WithdrawalBeforeSubmit beforeSubmit,
  required Future<void> Function(String txId) onSubmitted,
});

class HotPolymarketWithdrawalGuard {
  /// [settleWindow] and [settlePoll] exist so tests can exercise the
  /// "still settling past the window" outcome without waiting 75 real
  /// seconds; production always uses the defaults.
  HotPolymarketWithdrawalGuard({
    Future<Box<String>> Function()? openBox,
    Duration settleWindow = _defaultSettleWindow,
    Duration settlePoll = _defaultSettlePoll,
    DateTime Function()? clock,
  })  : _openBox = openBox ?? (() => Hive.openBox<String>(boxName)),
        _settleWindow = settleWindow,
        _settlePoll = settlePoll,
        _clock = clock ?? DateTime.now;

  static const boxName = 'polymarket_withdrawals';
  static final Set<String> _busy = {};
  static int _attemptSequence = 0;

  /// How long a submitted withdrawal is given to reach a terminal state
  /// before the tap gives up on it.
  ///
  /// The relayer settles a Safe transaction on Polygon, which takes the
  /// better part of a minute on a normal day. Asking once and treating
  /// "still going" as an answer turned every ordinary withdrawal into a
  /// transfer nobody could account for. The record keeps blocking after
  /// this, which is the point of the record; what changed is that the
  /// wait happens before anything is said.
  static const _defaultSettleWindow = Duration(seconds: 75);
  static const _defaultSettlePoll = Duration(seconds: 3);
  final Duration _settleWindow;
  final Duration _settlePoll;
  final Future<Box<String>> Function() _openBox;
  final DateTime Function() _clock;

  /// How long a record with no relayer reference blocks before the
  /// deposit wallet's balance may settle it. The signed batch carries a
  /// 10-minute deadline, after which the relayer and the wallet contract
  /// both reject it, so by now whatever it did (or did not do) is final.
  static const unreferencedWindow = Duration(minutes: 30);

  /// Settles a withdrawal whose relayer response was lost (no txId), once
  /// its batch can no longer execute, from a fresh balance read. Always
  /// throws: it only reports the outcome and never sends anything itself.
  /// Anything it cannot prove keeps the record blocking.
  Future<Never> _settleUnreferenced(Box<String> box, String key, Map decoded,
      Future<BigInt> Function()? depositWalletBalance) async {
    if (decoded['settledBy'] == 'balance' &&
        (decoded['stage'] == 'confirmed' || decoded['stage'] == 'failed')) {
      // Settled earlier, but the acknowledgement did not land: report the
      // same outcome again rather than reading the balance a second time.
      await _writeTerminal(box, key, Map<String, Object?>.from(decoded));
      throw ResolvedPolymarketWithdrawal(
          confirmed: decoded['stage'] == 'confirmed');
    }
    final submittedAtMs = decoded['submittedAtMs'];
    final amount = BigInt.tryParse('${decoded['amountMicros']}');
    final before = BigInt.tryParse('${decoded['balanceMicros']}');
    if (depositWalletBalance == null ||
        decoded['stage'] != 'submitting' ||
        submittedAtMs is! int ||
        amount == null ||
        amount <= BigInt.zero ||
        before == null ||
        before < amount) {
      throw const EarlierPolymarketWithdrawalPending();
    }
    final submittedAt = DateTime.fromMillisecondsSinceEpoch(submittedAtMs);
    if (_clock().difference(submittedAt) < unreferencedWindow) {
      throw const EarlierPolymarketWithdrawalPending();
    }
    final BigInt now;
    try {
      now = await depositWalletBalance();
    } catch (_) {
      throw const EarlierPolymarketWithdrawalPending();
    }
    if (now < BigInt.zero) throw const EarlierPolymarketWithdrawalPending();
    // Rounding slack: 1% of the amount, never under one cent.
    final slack = amount ~/ BigInt.from(100) > BigInt.from(10000)
        ? amount ~/ BigInt.from(100)
        : BigInt.from(10000);
    final dropped = before - now;
    final bool sent;
    if (dropped >= amount - slack) {
      sent = true;
    } else if (dropped <= slack) {
      sent = false;
    } else {
      // The balance moved by something other than this withdrawal. Neither
      // outcome is shown, so the record keeps blocking.
      throw const EarlierPolymarketWithdrawalPending();
    }
    final row = Map<String, Object?>.from(decoded);
    row['stage'] = sent ? 'confirmed' : 'failed';
    row['settledBy'] = 'balance';
    await _writeTerminal(box, key, row);
    throw ResolvedPolymarketWithdrawal(confirmed: sent);
  }

  static bool _confirmed(WithdrawalStatus? status) =>
      status != null &&
      const {'STATE_CONFIRMED', 'CONFIRMED', 'DONE'}.contains(status.state) &&
      RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(status.hash ?? '');

  static bool _failed(WithdrawalStatus? status) =>
      status != null &&
      const {'STATE_FAILED', 'FAILED', 'STATE_INVALID', 'INVALID'}
          .contains(status.state);

  Future<void> _write(
      Box<String> box, String key, Map<String, Object?> row) async {
    await box.put(key, jsonEncode(row));
    await box.flush();
  }

  /// Records a terminal outcome, then marks it as surfaced.
  ///
  /// The terminal state is written and flushed first, without the
  /// acknowledgement. Hive can change its cache, and the file, before a
  /// flush fails, so a record written as terminal and acknowledged in one
  /// go let the next tap send a brand new withdrawal after this tap had
  /// reported an unresolved one (or failed outright) and the person had
  /// never been told the first one landed. The acknowledgement is only
  /// added once the terminal write is durable, and losing it is harmless:
  /// the next tap reconciles and reports the same outcome again.
  Future<void> _writeTerminal(
      Box<String> box, String key, Map<String, Object?> row) async {
    row.remove('acknowledged');
    await _write(box, key, row);
    try {
      await _write(box, key, {...row, 'acknowledged': true});
    } catch (_) {
      // Unacknowledged terminal records are reconciled, never re-sent.
    }
  }

  /// The lock covers reconciliation, key access, signing and submission.
  /// A retry only reconciles a previous uncertain operation and then stops.
  /// Even if its outcome becomes known, that tap never sends a new transfer.
  ///
  /// [depositWalletBalance] reads the deposit wallet's spendable balance
  /// (micro-USDC) fresh from the chain. Without it a record that lost its
  /// relayer reference blocks for good.
  Future<String> run({
    required String walletId,
    required String depositWallet,
    required Future<WithdrawalStatus?> Function(String txId) transactionState,
    required WithdrawalSubmit submit,
    Future<BigInt> Function()? depositWalletBalance,
  }) async {
    final key = depositWallet.toLowerCase();
    if (!_busy.add(key)) throw const EarlierPolymarketWithdrawalPending();
    try {
      final box = await _openBox();
      final raw = box.get(key);
      if (raw != null) {
        final Object? decoded;
        try {
          decoded = jsonDecode(raw);
        } catch (_) {
          // Corrupt history cannot prove that no payment was sent.
          throw const EarlierPolymarketWithdrawalPending();
        }
        if (decoded is! Map ||
            decoded['version'] != 1 ||
            decoded['depositWallet'] != key ||
            !const {'submitting', 'confirmed', 'failed'}
                .contains(decoded['stage'])) {
          throw const PendingPolymarketWithdrawal();
        }
        // The acknowledgement lives on the record, not in memory. It was
        // a static map, so every relaunch reopened a withdrawal that had
        // already been accounted for and spent the person's next tap
        // telling them about it.
        if (decoded['stage'] == 'submitting' ||
            decoded['attemptId'] is! String ||
            decoded['acknowledged'] != true) {
          final txId = decoded['txId'];
          if (txId is! String || txId.isEmpty) {
            // A lost POST response has no authoritative lookup ID. Nonce
            // advancement/elapsed time alone cannot prove this transfer
            // failed; once the batch is past its deadline, the balance can.
            await _settleUnreferenced(box, key, decoded, depositWalletBalance);
          }
          // Give the relayer time to land before concluding anything. A
          // status that is neither confirmed nor failed means the
          // transfer is still on its way, which is the ordinary case for
          // about a minute, not an outcome worth alarming anyone with.
          WithdrawalStatus? status;
          final deadline = DateTime.now().add(_settleWindow);
          while (true) {
            try {
              status = await transactionState(txId);
            } catch (_) {
              status = null;
            }
            if (_confirmed(status) || _failed(status)) break;
            if (!DateTime.now().isBefore(deadline)) {
              throw const EarlierPolymarketWithdrawalPending();
            }
            await Future<void>.delayed(_settlePoll);
          }
          final row = Map<String, Object?>.from(decoded);
          row['stage'] = _confirmed(status) ? 'confirmed' : 'failed';
          if (_confirmed(status)) row['hash'] = status!.hash;
          await _writeTerminal(box, key, row);
          throw ResolvedPolymarketWithdrawal(confirmed: _confirmed(status));
        }
      }

      Map<String, Object?>? record;
      try {
        final hash = await submit(
          beforeSubmit: (nonce, {amountMicros, balanceMicros}) async {
            if (record != null ||
                BigInt.tryParse(nonce) == null ||
                BigInt.parse(nonce) < BigInt.zero) {
              throw StateError('Invalid withdrawal submission nonce.');
            }
            final next = <String, Object?>{
              'version': 1,
              'attemptId':
                  '${_clock().microsecondsSinceEpoch}-${++_attemptSequence}',
              'walletId': walletId,
              'depositWallet': key,
              'nonce': nonce,
              'stage': 'submitting',
              'submittedAtMs': _clock().millisecondsSinceEpoch,
              if (amountMicros != null) 'amountMicros': amountMicros.toString(),
              if (balanceMicros != null)
                'balanceMicros': balanceMicros.toString(),
            };
            // No POST starts unless this write and flush both succeed.
            await _write(box, key, next);
            record = next;
          },
          onSubmitted: (txId) async {
            final row = record;
            if (row == null || txId.isEmpty) {
              throw StateError('Missing withdrawal submission record.');
            }
            row['txId'] = txId;
            await _write(box, key, row);
          },
        );
        final row = record;
        final txId = row?['txId'];
        if (row == null || txId is! String) {
          throw StateError('Missing withdrawal submission reference.');
        }
        // The relayer has the transaction; it has not settled it yet.
        // Asking once, the instant the POST returns, and treating "still
        // going" as a failure is what turned every ordinary withdrawal
        // into one nobody could account for: Polygon takes the better
        // part of a minute. Wait for it, then decide.
        WithdrawalStatus? status;
        final deadline = DateTime.now().add(_settleWindow);
        while (true) {
          try {
            status = await transactionState(txId);
          } catch (_) {
            status = null;
          }
          if (_confirmed(status) || _failed(status)) break;
          if (!DateTime.now().isBefore(deadline)) {
            throw const PendingPolymarketWithdrawal();
          }
          await Future<void>.delayed(_settlePoll);
        }
        if (!_confirmed(status) ||
            status!.hash!.toLowerCase() != hash.toLowerCase()) {
          throw const PendingPolymarketWithdrawal();
        }
        row['stage'] = 'confirmed';
        row['hash'] = status.hash;
        await _writeTerminal(box, key, row);
        return hash;
      } catch (error) {
        if (record != null) {
          // Do not classify timeouts, RPC errors or arbitrary exception text
          // as failure. The durable submitting record blocks any new attempt.
          throw const PendingPolymarketWithdrawal();
        }
        rethrow;
      }
    } finally {
      _busy.remove(key);
    }
  }
}
