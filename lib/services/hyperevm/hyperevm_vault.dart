// lib/services/hyperevm/hyperevm_vault.dart
//
// Everything that happens on the account's HyperEVM address outside an
// Orchestra settlement record:
//
//  - [HyperEvmVaultLock]: one HyperEVM step at a time per address in this
//    process. A withdrawal holds it from its HyperCore → HyperEVM transfer
//    until its ERC-20 transfer is sent; the sweeper and the float keeper
//    take it for each step, so nothing spends USDC another step relies on.
//  - [HyperEvmTxJournal]: the write-ahead record of the one HyperEVM
//    transaction a sweep or a float move has in flight (hash, nonce, kind,
//    time). Written after signing and before broadcasting; cleared once a
//    receipt or the nonce settles it. A restart reads it before signing
//    anything new. Holds only public data (a hash and a nonce).
//  - [HyperEvmFloatKeeper]: keeps the HYPE float on both sides.
//  - [HyperEvmSweeper]: moves USDC sitting on the HyperEVM address into
//    HyperCore (a deposit Orchestra delivered, a refund, a withdrawal that
//    stopped before its provider transfer). Balance driven, so a repeat
//    can never move more than is there.

import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_gas_float.dart';
import 'package:kute/services/hyperevm/hyperevm_rpc.dart';

/// One HyperEVM step at a time per address, in this process.
class HyperEvmVaultLock {
  HyperEvmVaultLock._();

  static final Map<String, Future<void>> _tails = {};

  /// Runs [body] once every earlier holder for [address] finished.
  static Future<T> run<T>(String address, Future<T> Function() body) {
    final key = address.toLowerCase();
    final previous = _tails[key] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = done.future;
    _tails[key] = tail;
    return previous.then((_) => body()).whenComplete(() {
      done.complete();
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
  }

  /// Whether a step holds [address] right now.
  static bool isHeld(String address) =>
      _tails.containsKey(address.toLowerCase());
}

/// A HyperEVM transaction a sweep or a float move signed.
class HyperEvmJournalEntry {
  const HyperEvmJournalEntry({
    required this.hash,
    required this.nonce,
    required this.kind,
    required this.at,
  });

  final String hash;
  final int nonce;
  final String kind;
  final DateTime at;

  Map<String, Object> toJson() => {
        'hash': hash,
        'nonce': nonce,
        'kind': kind,
        'atMs': at.millisecondsSinceEpoch,
      };

  static HyperEvmJournalEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final hash = json['hash'];
    final nonce = json['nonce'];
    final kind = json['kind'];
    final at = json['atMs'];
    if (hash is! String || nonce is! int || kind is! String || at is! int) {
      return null;
    }
    return HyperEvmJournalEntry(
        hash: hash,
        nonce: nonce,
        kind: kind,
        at: DateTime.fromMillisecondsSinceEpoch(at));
  }
}

abstract interface class HyperEvmTxJournal {
  Future<HyperEvmJournalEntry?> read(String address);
  Future<void> write(String address, HyperEvmJournalEntry entry);
  Future<void> clear(String address);
}

/// The journal on disk (`hyperevm_tx_journal`), flushed on every write.
class HiveHyperEvmTxJournal implements HyperEvmTxJournal {
  const HiveHyperEvmTxJournal();

  static const String boxName = 'hyperevm_tx_journal';

  Future<Box<String>> _box() => Hive.isBoxOpen(boxName)
      ? Future.value(Hive.box<String>(boxName))
      : Hive.openBox<String>(boxName);

  @override
  Future<HyperEvmJournalEntry?> read(String address) async {
    final raw = (await _box()).get(address.toLowerCase());
    if (raw == null) return null;
    try {
      return HyperEvmJournalEntry.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String address, HyperEvmJournalEntry entry) async {
    final box = await _box();
    await box.put(address.toLowerCase(), jsonEncode(entry.toJson()));
    await box.flush();
  }

  @override
  Future<void> clear(String address) async {
    final box = await _box();
    await box.delete(address.toLowerCase());
    await box.flush();
  }
}

/// A journal kept in memory (tests).
class MemoryHyperEvmTxJournal implements HyperEvmTxJournal {
  final Map<String, HyperEvmJournalEntry> entries = {};

  @override
  Future<HyperEvmJournalEntry?> read(String address) async =>
      entries[address.toLowerCase()];

  @override
  Future<void> write(String address, HyperEvmJournalEntry entry) async =>
      entries[address.toLowerCase()] = entry;

  @override
  Future<void> clear(String address) async =>
      entries.remove(address.toLowerCase());
}

/// Where a journaled transaction stands.
enum HyperEvmJournalStatus {
  /// Nothing in flight.
  clear,

  /// Still waiting to be mined (or not yet settled either way).
  pending,
}

/// Settles a journaled transaction from public chain data: a receipt
/// clears it, a used nonce clears it, and one no node has seen three
/// minutes after signing was never broadcast (or was dropped) and clears.
Future<HyperEvmJournalStatus> resolveHyperEvmJournal({
  required String address,
  required HyperEvmTxJournal journal,
  required HyperEvmReader reader,
  required DateTime now,
}) async {
  final entry = await journal.read(address);
  if (entry == null) return HyperEvmJournalStatus.clear;
  final receipt = await reader.receipt(entry.hash);
  if (receipt != null) {
    await journal.clear(address);
    return HyperEvmJournalStatus.clear;
  }
  if (await reader.isKnownTransaction(entry.hash)) {
    return HyperEvmJournalStatus.pending;
  }
  final nonce = await reader.nonce(address);
  if (nonce > entry.nonce ||
      now.difference(entry.at) > const Duration(minutes: 3)) {
    await journal.clear(address);
    return HyperEvmJournalStatus.clear;
  }
  return HyperEvmJournalStatus.pending;
}

/// Waits for [hash]'s receipt. Null when it is not mined in time.
Future<HyperEvmReceipt?> waitForHyperEvmReceipt(
  HyperEvmReader reader,
  String hash, {
  Duration total = const Duration(seconds: 45),
  Future<void> Function(Duration)? sleep,
}) async {
  try {
    return await pollHyperEvm<HyperEvmReceipt?>(
      read: () => reader.receipt(hash),
      done: (r) => r != null,
      schedule: hyperEvmPollSchedule(total),
      sleep: sleep,
    );
  } on HyperEvmArrivalTimeout {
    return null;
  }
}

/// The float could not be made ready for a move. Nothing was sent.
class HyperEvmFloatUnavailable implements Exception {
  const HyperEvmFloatUnavailable(this.reason);

  /// `gas_spike`, `pending`, `no_source`, `arrival_timeout`, `rebalance`.
  final String reason;

  @override
  String toString() => 'HyperEvmFloatUnavailable($reason)';
}

/// Keeps the HYPE float on both sides.
class HyperEvmFloatKeeper {
  HyperEvmFloatKeeper({
    required this.reader,
    required this.journal,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
  })  : _clock = clock ?? DateTime.now,
        _sleep = sleep;

  final HyperEvmReader reader;
  final HyperEvmTxJournal journal;
  final DateTime Function() _clock;
  final Future<void> Function(Duration)? _sleep;

  Future<HyperEvmFloatState> read(String address) async {
    final results =
        await Future.wait([reader.evm(address), reader.core(address)]);
    final evm = results[0] as HyperEvmAccountRead;
    final core = results[1] as HyperCoreHoldings;
    return HyperEvmFloatState(
        evmHypeWei: evm.hypeWei,
        coreHype: core.spotHype,
        gasPriceWei: evm.gasPriceWei);
  }

  Future<HyperEvmGasPlan> plan(String address, HyperEvmMove move) async =>
      planHyperEvmGas(await read(address), move);

  /// Makes the float ready for [move], after the person approved it.
  /// [buy] places the $1 purchase (its own settlement operation, moving
  /// nothing but the float). When [plan] says the move is not covered,
  /// waits for the purchase to land, up to [arrivalTimeout]; otherwise
  /// the purchase lands on its own and is split on a later step. Throws
  /// [HyperEvmFloatUnavailable] when the move cannot be covered.
  Future<void> prepare({
    required String address,
    required HyperEvmMove move,
    required HyperEvmSigner signer,
    required HyperEvmGasPlan plan,
    required Future<void> Function() buy,
    Duration arrivalTimeout = const Duration(minutes: 3),
  }) async {
    if (plan.gasSpike) throw const HyperEvmFloatUnavailable('gas_spike');
    if (plan.rebalances) {
      await rebalance(address: address, signer: signer, plan: plan);
    }
    if (!plan.buy) return;
    final before = await reader.evmHype(address);
    await buy();
    if (!plan.mustWait) return;
    try {
      await pollHyperEvm<BigInt>(
        read: () => reader.evmHype(address),
        done: (hype) => hype > before,
        schedule: hyperEvmPollSchedule(arrivalTimeout),
        sleep: _sleep,
      );
    } on HyperEvmArrivalTimeout {
      throw const HyperEvmFloatUnavailable('arrival_timeout');
    }
    // Landed: give HyperCore its share in one transfer, which also
    // covers a withdrawal's HyperCore gas. Only when that is not enough
    // does the plan's own rebalance run.
    final split = hyperEvmSplitToCoreWei(await read(address));
    if (split > BigInt.zero) {
      await _moveToCore(address, signer, split);
    }
    var ready = planHyperEvmGas(await read(address), move);
    if (!ready.ready && ready.rebalances) {
      await rebalance(address: address, signer: signer, plan: ready);
      ready = planHyperEvmGas(await read(address), move);
    }
    if (!ready.ready) throw const HyperEvmFloatUnavailable('rebalance');
  }

  /// Moves HYPE between the sides as [plan] says and waits for it to land.
  Future<void> rebalance({
    required String address,
    required HyperEvmSigner signer,
    required HyperEvmGasPlan plan,
  }) async {
    if (plan.toCoreWei > BigInt.zero) {
      await _moveToCore(address, signer, plan.toCoreWei);
    } else if (plan.toEvmCore > BigInt.zero) {
      final before = await reader.evmHype(address);
      await signer.coreToEvm(
        token: HyperCoreTokens.hype,
        amount: plan.toEvmCore,
        sourceDex: HyperCoreTokens.spotDex,
        onBeforePost: (_) async {},
      );
      try {
        await pollHyperEvm<BigInt>(
          read: () => reader.evmHype(address),
          done: (hype) => hype > before,
          schedule: hyperEvmPollSchedule(const Duration(seconds: 45)),
          sleep: _sleep,
        );
      } on HyperEvmArrivalTimeout {
        throw const HyperEvmFloatUnavailable('rebalance');
      }
    }
  }

  /// After a deposit sweep, sends HyperEVM's surplus to HyperCore so the
  /// next withdrawal finds its share there. Best effort.
  Future<void> splitIfDue(String address, HyperEvmSigner signer) async {
    try {
      final split = hyperEvmSplitToCoreWei(await read(address));
      if (split > BigInt.zero) await _moveToCore(address, signer, split);
    } catch (_) {
      // The next move tries again.
    }
  }

  Future<void> _moveToCore(
      String address, HyperEvmSigner signer, BigInt wei) async {
    if (await resolveHyperEvmJournal(
            address: address,
            journal: journal,
            reader: reader,
            now: _clock()) ==
        HyperEvmJournalStatus.pending) {
      throw const HyperEvmFloatUnavailable('pending');
    }
    final coreBefore = (await reader.core(address)).spotHype;
    final hash = await signer.sendEvmTx(
      kind: HyperEvmTxKind.hypeToCore,
      amount: wei,
      onSigned: (hash, nonce) => journal.write(
          address,
          HyperEvmJournalEntry(
              hash: hash, nonce: nonce, kind: 'hype_to_core', at: _clock())),
    );
    final receipt =
        await waitForHyperEvmReceipt(reader, hash, sleep: _sleep);
    if (receipt == null) throw const HyperEvmFloatUnavailable('pending');
    await journal.clear(address);
    if (!receipt.success) throw const HyperEvmFloatUnavailable('rebalance');
    try {
      await pollHyperEvm<BigInt>(
        read: () async => (await reader.core(address)).spotHype,
        done: (hype) => hype > coreBefore,
        schedule: hyperEvmPollSchedule(const Duration(seconds: 30)),
        sleep: _sleep,
      );
    } on HyperEvmArrivalTimeout {
      throw const HyperEvmFloatUnavailable('rebalance');
    }
  }
}

/// What one sweep did.
enum HyperEvmSweepOutcome {
  /// No USDC on the HyperEVM address.
  idle,

  /// USDC moved into HyperCore.
  swept,

  /// A transaction is still in flight, or a withdrawal holds the USDC.
  waiting,

  /// The HyperEVM side of the float cannot pay the deposit's gas yet.
  noGas,

  /// The deposit transaction was mined and reverted (nothing moved).
  failed,
}

/// Moves USDC sitting on the HyperEVM address into HyperCore.
class HyperEvmSweeper {
  HyperEvmSweeper({
    required this.reader,
    required this.journal,
    required this.keeper,
    required this.openSigner,
    required this.reservedByWithdrawal,
    this.onParked,
    this.onSwept,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
  })  : _clock = clock ?? DateTime.now,
        _sleep = sleep;

  final HyperEvmReader reader;
  final HyperEvmTxJournal journal;
  final HyperEvmFloatKeeper keeper;

  /// Opens the spending wallet's Hyperliquid key for [address], or null
  /// while the session is locked or the wallet changed.
  final Future<HyperEvmSigner?> Function(String address) openSigner;

  /// True while a withdrawal may still spend the USDC on [address]: one
  /// in progress in this process, or one whose provider transfer was
  /// signed and is not settled.
  final Future<bool> Function(String address) reservedByWithdrawal;

  /// The USDC last read on the HyperEVM address, shown as pending
  /// Investing balance so it never looks gone.
  final void Function(String address, BigInt micros)? onParked;

  /// USDC that reached HyperCore.
  final void Function(String address, BigInt micros)? onSwept;

  final DateTime Function() _clock;
  final Future<void> Function(Duration)? _sleep;
  final Map<String, Future<void>> _watching = {};

  Future<HyperEvmSweepOutcome> sweepOnce(String address) =>
      HyperEvmVaultLock.run(address, () => _sweep(address));

  Future<HyperEvmSweepOutcome> _sweep(String address) async {
    if (await resolveHyperEvmJournal(
            address: address,
            journal: journal,
            reader: reader,
            now: _clock()) ==
        HyperEvmJournalStatus.pending) {
      return HyperEvmSweepOutcome.waiting;
    }
    final account = await reader.evm(address);
    onParked?.call(address, account.usdcMicros);
    if (account.usdcMicros <= BigInt.zero) return HyperEvmSweepOutcome.idle;
    if (account.hasPendingTransaction || await reservedByWithdrawal(address)) {
      return HyperEvmSweepOutcome.waiting;
    }
    final signer = await openSigner(address);
    if (signer == null) return HyperEvmSweepOutcome.waiting;
    final plan = await keeper.plan(address, HyperEvmMove.deposit);
    if (plan.gasSpike) return HyperEvmSweepOutcome.noGas;
    if (plan.rebalances) {
      // HyperCore's HYPE pays for the deposit's gas on HyperEVM.
      try {
        await keeper.rebalance(address: address, signer: signer, plan: plan);
      } catch (_) {
        return HyperEvmSweepOutcome.noGas;
      }
    } else if (plan.mustWait) {
      return HyperEvmSweepOutcome.noGas;
    }
    final holdings = await reader.core(address);
    final dex = holdings.mode == HyperCoreAccountMode.unified
        ? HyperEvmChain.spotDex
        : HyperEvmChain.perpsDex;
    final amount = account.usdcMicros;
    final String hash;
    try {
      hash = await signer.sendEvmTx(
        kind: HyperEvmTxKind.depositToCore,
        amount: amount,
        destinationDex: dex,
        onSigned: (hash, nonce) => journal.write(
            address,
            HyperEvmJournalEntry(
                hash: hash, nonce: nonce, kind: 'deposit', at: _clock())),
      );
    } on HyperEvmGasShort {
      return HyperEvmSweepOutcome.noGas;
    } on HyperEvmGasSpike {
      return HyperEvmSweepOutcome.noGas;
    } on HyperEvmTransactionPending {
      return HyperEvmSweepOutcome.waiting;
    } on HyperEvmBroadcastUncertain {
      return HyperEvmSweepOutcome.waiting;
    }
    final receipt =
        await waitForHyperEvmReceipt(reader, hash, sleep: _sleep);
    if (receipt == null) return HyperEvmSweepOutcome.waiting;
    await journal.clear(address);
    if (!receipt.success) return HyperEvmSweepOutcome.failed;
    onParked?.call(address, BigInt.zero);
    onSwept?.call(address, amount);
    await keeper.splitIfDue(address, signer);
    return HyperEvmSweepOutcome.swept;
  }

  /// Sweeps once now and then, while nothing landed yet, on a backoff for
  /// up to [total]: a deposit Orchestra is still delivering. One watch per
  /// address; a second call joins it. Never polls when no watch runs.
  Future<void> watch(String address,
      {Duration total = const Duration(minutes: 15)}) {
    final key = address.toLowerCase();
    final running = _watching[key];
    if (running != null) return running;
    final future = _watch(address, total).whenComplete(() {
      _watching.remove(key);
    });
    _watching[key] = future;
    return future;
  }

  Future<void> _watch(String address, Duration total) async {
    final wait = _sleep ?? (Duration d) => Future<void>.delayed(d);
    final started = _clock();
    var delay = const Duration(seconds: 5);
    while (_clock().difference(started) < total) {
      HyperEvmSweepOutcome outcome;
      try {
        outcome = await sweepOnce(address);
      } catch (_) {
        outcome = HyperEvmSweepOutcome.waiting;
      }
      if (outcome == HyperEvmSweepOutcome.swept ||
          outcome == HyperEvmSweepOutcome.failed) {
        return;
      }
      await wait(delay);
      final next = delay * 2;
      delay = next > const Duration(seconds: 60)
          ? const Duration(seconds: 60)
          : next;
    }
  }
}
