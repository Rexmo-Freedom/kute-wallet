import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/polymarket/hot_withdrawal_guard.dart';
import 'package:mocktail/mocktail.dart';

class _FailingBox extends Mock implements Box<String> {}

const _wallet = '0x1111111111111111111111111111111111111111';
final _hash = '0x${'a' * 64}';

/// The production guard waits up to 75 seconds for the relayer to settle.
/// These tests only care about what happens once that window has passed,
/// so they give it no window at all.
HotPolymarketWithdrawalGuard _guard(Box<String> box) =>
    HotPolymarketWithdrawalGuard(
        openBox: () async => box,
        settleWindow: Duration.zero,
        settlePoll: const Duration(milliseconds: 1));

void main() {
  late Directory directory;
  late Box<String> box;
  late HotPolymarketWithdrawalGuard guard;
  late WithdrawalStatus? status;
  late int submissions;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pm-withdrawal-guard');
    Hive.init(directory.path);
    box = await Hive.openBox<String>(HotPolymarketWithdrawalGuard.boxName);
    guard = _guard(box);
    status = null;
    submissions = 0;
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<String> run(WithdrawalSubmit submit,
          {HotPolymarketWithdrawalGuard? instance}) =>
      (instance ?? guard).run(
          walletId: 'spending',
          depositWallet: _wallet,
          transactionState: (_) async => status,
          submit: submit);

  Future<String> acceptedTimeout({
    required Future<void> Function(String) beforeSubmit,
    required Future<void> Function(String) onSubmitted,
  }) async {
    await beforeSubmit('42');
    final written = jsonDecode(box.get(_wallet)!);
    expect(written['nonce'], '42');
    expect(written['stage'], 'submitting');
    submissions++;
    await onSubmitted('tx-42');
    expect(jsonDecode(box.get(_wallet)!)['txId'], 'tx-42');
    throw TimeoutException('accepted, response polling timed out');
  }

  Future<String> successful({
    required Future<void> Function(String) beforeSubmit,
    required Future<void> Function(String) onSubmitted,
  }) async {
    await beforeSubmit('43');
    submissions++;
    await onSubmitted('tx-43');
    return _hash;
  }

  test(
      'acceptance timeout persists, restart reconciles without submitting again',
      () async {
    await expectLater(
        run(acceptedTimeout), throwsA(isA<PendingPolymarketWithdrawal>()));
    await box.close();
    box = await Hive.openBox<String>(HotPolymarketWithdrawalGuard.boxName);
    final restarted = _guard(box);
    await expectLater(run(successful, instance: restarted),
        throwsA(isA<EarlierPolymarketWithdrawalPending>()));
    expect(submissions, 1);
    status = (state: 'STATE_CONFIRMED', hash: _hash);
    await expectLater(
        run(successful, instance: restarted),
        throwsA(isA<ResolvedPolymarketWithdrawal>()
            .having((e) => e.confirmed, 'confirmed', isTrue)));
    expect(submissions, 1); // The reconcile tap never creates a new withdrawal.
    expect(jsonDecode(box.get(_wallet)!)['stage'], 'confirmed');
  });

  test(
      'lost POST response has no transaction ID and remains blocked after restart',
      () async {
    await expectLater(
        run(({required beforeSubmit, required onSubmitted}) async {
      await beforeSubmit('42');
      submissions++;
      throw TimeoutException('response lost');
    }), throwsA(isA<PendingPolymarketWithdrawal>()));
    await box.close();
    box = await Hive.openBox<String>(HotPolymarketWithdrawalGuard.boxName);
    status = (state: 'STATE_CONFIRMED', hash: _hash);
    await expectLater(run(successful, instance: _guard(box)),
        throwsA(isA<EarlierPolymarketWithdrawalPending>()));
    expect(submissions, 1);
    expect(jsonDecode(box.get(_wallet)!)['txId'], isNull);
  });

  for (final pending in [
    'STATE_NEW',
    'STATE_EXECUTED',
    'STATE_MINED',
    'UNCONFIRMED'
  ]) {
    test('$pending with a hash is not a successful withdrawal', () async {
      status = (state: pending, hash: _hash);
      await expectLater(
          run(successful), throwsA(isA<PendingPolymarketWithdrawal>()));
      await expectLater(
          run(successful), throwsA(isA<EarlierPolymarketWithdrawalPending>()));
      expect(submissions, 1);
      expect(jsonDecode(box.get(_wallet)!)['stage'], 'submitting');
    });
  }

  test('confirmed without a valid hash remains unknown', () async {
    status = (state: 'STATE_CONFIRMED', hash: 'tx-42');
    await expectLater(
        run(successful), throwsA(isA<PendingPolymarketWithdrawal>()));
    await expectLater(
        run(successful), throwsA(isA<EarlierPolymarketWithdrawalPending>()));
    expect(submissions, 1);
  });

  test('only confirmed status for the same returned hash reports success',
      () async {
    status = (state: 'STATE_CONFIRMED', hash: _hash);
    expect(await run(successful), _hash);
    expect(submissions, 1);
    expect(jsonDecode(box.get(_wallet)!)['stage'], 'confirmed');
  });

  test(
      'failed status permits a later deliberate attempt, not the reconcile tap',
      () async {
    await expectLater(
        run(acceptedTimeout), throwsA(isA<PendingPolymarketWithdrawal>()));
    status = (state: 'STATE_FAILED', hash: null);
    await expectLater(
        run(successful),
        throwsA(isA<ResolvedPolymarketWithdrawal>()
            .having((e) => e.confirmed, 'confirmed', isFalse)));
    expect(submissions, 1);
    status = (state: 'STATE_CONFIRMED', hash: _hash);
    expect(await run(successful), _hash);
    expect(submissions, 2);
  });

  test('concurrent requests cannot both reconcile or submit', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    status = (state: 'STATE_CONFIRMED', hash: _hash);
    final first = run(({required beforeSubmit, required onSubmitted}) async {
      entered.complete();
      await release.future;
      return successful(beforeSubmit: beforeSubmit, onSubmitted: onSubmitted);
    });
    await entered.future;
    await expectLater(run(successful, instance: _guard(box)),
        throwsA(isA<EarlierPolymarketWithdrawalPending>()));
    expect(submissions, 0);
    release.complete();
    expect(await first, _hash);
    expect(submissions, 1);
  });

  test(
      'failure before journal creates no uncertainty and permits a fresh attempt',
      () async {
    await expectLater(
        run(({required beforeSubmit, required onSubmitted}) async {
      throw StateError('signing declined');
    }), throwsStateError);
    expect(box.get(_wallet), isNull);
    status = (state: 'STATE_CONFIRMED', hash: _hash);
    expect(await run(successful), _hash);
    expect(submissions, 1);
  });

  test('storage flush failure prevents POST', () async {
    final failing = _FailingBox();
    when(() => failing.get(_wallet)).thenReturn(null);
    when(() => failing.put(any(), any())).thenAnswer((_) async {});
    when(() => failing.flush()).thenThrow(StateError('disk unavailable'));
    await expectLater(
        run(successful, instance: _guard(failing)), throwsStateError);
    expect(submissions, 0);
  });

  test('accepted POST survives failure to persist its transaction ID',
      () async {
    final failing = _FailingBox();
    when(() => failing.get(_wallet)).thenAnswer((_) => box.get(_wallet));
    when(() => failing.put(any(), any())).thenAnswer((invocation) async {
      final key = invocation.positionalArguments[0] as String;
      final value = invocation.positionalArguments[1] as String;
      if ((jsonDecode(value) as Map).containsKey('txId')) {
        throw StateError('disk unavailable after relayer acceptance');
      }
      await box.put(key, value);
    });
    when(() => failing.flush()).thenAnswer((_) => box.flush());
    await expectLater(run(successful, instance: _guard(failing)),
        throwsA(isA<PendingPolymarketWithdrawal>()));
    expect(submissions, 1);
    await box.close();
    box = await Hive.openBox<String>(HotPolymarketWithdrawalGuard.boxName);
    expect(jsonDecode(box.get(_wallet)!)['stage'], 'submitting');
    expect(jsonDecode(box.get(_wallet)!)['nonce'], '43');
    expect(jsonDecode(box.get(_wallet)!)['txId'], isNull);
    await expectLater(run(successful, instance: _guard(box)),
        throwsA(isA<EarlierPolymarketWithdrawalPending>()));
    expect(submissions, 1);
  });

  test('a different confirmed hash cannot be returned as this withdrawal',
      () async {
    status = (state: 'STATE_CONFIRMED', hash: '0x${'b' * 64}');
    await expectLater(
        run(successful), throwsA(isA<PendingPolymarketWithdrawal>()));
    expect(submissions, 1);
    expect(jsonDecode(box.get(_wallet)!)['stage'], 'submitting');
  });

  for (final priorSuccess in [false, true]) {
    test(
        'terminal flush failure cannot authorize retry; prior success=$priorSuccess',
        () async {
      status = (state: 'STATE_CONFIRMED', hash: _hash);
      if (priorSuccess) expect(await run(successful), _hash);
      final failing = _FailingBox();
      when(() => failing.get(_wallet)).thenAnswer((_) => box.get(_wallet));
      when(() => failing.put(any(), any())).thenAnswer((invocation) => box.put(
          invocation.positionalArguments[0],
          invocation.positionalArguments[1] as String));
      when(() => failing.flush()).thenAnswer((_) async {
        if (jsonDecode(box.get(_wallet)!)['stage'] == 'confirmed') {
          throw StateError('terminal flush failed after cache mutation');
        }
        await box.flush();
      });
      await expectLater(run(successful, instance: _guard(failing)),
          throwsA(isA<PendingPolymarketWithdrawal>()));
      final sentBeforeRetry = submissions;
      expect(sentBeforeRetry, priorSuccess ? 2 : 1);
      expect(jsonDecode(box.get(_wallet)!)['stage'], 'confirmed');
      await box.close();
      box = await Hive.openBox<String>(HotPolymarketWithdrawalGuard.boxName);
      await expectLater(run(successful, instance: _guard(box)),
          throwsA(isA<ResolvedPolymarketWithdrawal>()));
      expect(submissions, sentBeforeRetry);
    });
  }

  test('reconciliation flush failure never turns a retry into a new POST',
      () async {
    await expectLater(
        run(acceptedTimeout), throwsA(isA<PendingPolymarketWithdrawal>()));
    status = (state: 'STATE_CONFIRMED', hash: _hash);
    final failing = _FailingBox();
    when(() => failing.get(_wallet)).thenAnswer((_) => box.get(_wallet));
    when(() => failing.put(any(), any())).thenAnswer((invocation) => box.put(
        invocation.positionalArguments[0],
        invocation.positionalArguments[1] as String));
    when(() => failing.flush())
        .thenThrow(StateError('reconciliation flush failed'));
    await expectLater(
        run(successful, instance: _guard(failing)), throwsStateError);
    expect(jsonDecode(box.get(_wallet)!)['stage'], 'confirmed');
    expect(submissions, 1);
    await expectLater(
        run(successful), throwsA(isA<ResolvedPolymarketWithdrawal>()));
    expect(submissions, 1);
  });

  test('corrupt journal blocks signing instead of discarding a possible send',
      () async {
    await box.put(_wallet, '{broken');
    await expectLater(
        run(successful), throwsA(isA<EarlierPolymarketWithdrawalPending>()));
    expect(submissions, 0);
  });

  group('a record that lost its relayer reference', () {
    // 100 USDC withdrawal sized against a 250 USDC spendable balance.
    final amount = BigInt.from(100000000);
    final before = BigInt.from(250000000);
    late DateTime clock;
    late BigInt? balance;
    late int balanceReads;

    HotPolymarketWithdrawalGuard timed() => HotPolymarketWithdrawalGuard(
        openBox: () async => box,
        settleWindow: Duration.zero,
        settlePoll: const Duration(milliseconds: 1),
        clock: () => clock);

    Future<String> runTimed(WithdrawalSubmit submit) => timed().run(
        walletId: 'spending',
        depositWallet: _wallet,
        transactionState: (_) async => status,
        depositWalletBalance: () async {
          balanceReads++;
          final value = balance;
          if (value == null) throw TimeoutException('rpc down');
          return value;
        },
        submit: submit);

    Future<String> lostResponse({
      required WithdrawalBeforeSubmit beforeSubmit,
      required Future<void> Function(String) onSubmitted,
    }) async {
      await beforeSubmit('42', amountMicros: amount, balanceMicros: before);
      submissions++;
      throw TimeoutException('response lost');
    }

    Future<String> sized({
      required WithdrawalBeforeSubmit beforeSubmit,
      required Future<void> Function(String) onSubmitted,
    }) async {
      await beforeSubmit('43', amountMicros: amount, balanceMicros: before);
      submissions++;
      await onSubmitted('tx-43');
      return _hash;
    }

    setUp(() async {
      clock = DateTime(2026, 9, 30, 12);
      balance = before;
      balanceReads = 0;
      await expectLater(
          runTimed(lostResponse), throwsA(isA<PendingPolymarketWithdrawal>()));
      final row = jsonDecode(box.get(_wallet)!);
      expect(row['txId'], isNull);
      expect(row['amountMicros'], amount.toString());
      expect(row['balanceMicros'], before.toString());
      expect(submissions, 1);
    });

    test('keeps blocking while fresh, without reading the balance', () async {
      clock = clock.add(HotPolymarketWithdrawalGuard.unreferencedWindow -
          const Duration(minutes: 1));
      await expectLater(
          runTimed(sized), throwsA(isA<EarlierPolymarketWithdrawalPending>()));
      expect(balanceReads, 0);
      expect(submissions, 1);
      expect(jsonDecode(box.get(_wallet)!)['stage'], 'submitting');
    });

    test('once stale with the funds still there, clears so the user can retry',
        () async {
      clock = clock.add(HotPolymarketWithdrawalGuard.unreferencedWindow);
      // The reconcile tap itself never sends anything.
      await expectLater(
          runTimed(sized),
          throwsA(isA<ResolvedPolymarketWithdrawal>()
              .having((e) => e.confirmed, 'confirmed', isFalse)));
      expect(balanceReads, 1);
      expect(submissions, 1);
      final row = jsonDecode(box.get(_wallet)!);
      expect(row['stage'], 'failed');
      expect(row['settledBy'], 'balance');
      // The next deliberate tap goes through.
      status = (state: 'STATE_CONFIRMED', hash: _hash);
      expect(await runTimed(sized), _hash);
      expect(submissions, 2);
    });

    test('once stale with the funds gone, is marked sent and sends nothing',
        () async {
      clock = clock.add(const Duration(hours: 2));
      balance = before - amount;
      await expectLater(
          runTimed(sized),
          throwsA(isA<ResolvedPolymarketWithdrawal>()
              .having((e) => e.confirmed, 'confirmed', isTrue)));
      expect(submissions, 1);
      final row = jsonDecode(box.get(_wallet)!);
      expect(row['stage'], 'confirmed');
      expect(row['settledBy'], 'balance');
      expect(row['hash'], isNull);
    });

    test('a balance-settled outcome whose acknowledgement was lost is '
        'reported again, never re-read or re-sent', () async {
      clock = clock.add(const Duration(hours: 2));
      balance = before - amount;
      await expectLater(runTimed(sized),
          throwsA(isA<ResolvedPolymarketWithdrawal>()));
      final row = Map<String, Object?>.from(jsonDecode(box.get(_wallet)!));
      row.remove('acknowledged');
      await box.put(_wallet, jsonEncode(row));
      balance = before; // Would read as "not moved" if it were re-read.
      await expectLater(
          runTimed(sized),
          throwsA(isA<ResolvedPolymarketWithdrawal>()
              .having((e) => e.confirmed, 'confirmed', isTrue)));
      expect(balanceReads, 1);
      expect(submissions, 1);
      expect(jsonDecode(box.get(_wallet)!)['acknowledged'], isTrue);
    });

    test('an unreadable or ambiguous balance keeps blocking', () async {
      clock = clock.add(const Duration(hours: 2));
      balance = null;
      await expectLater(
          runTimed(sized), throwsA(isA<EarlierPolymarketWithdrawalPending>()));
      // Moved by something other than this withdrawal (e.g. a trade).
      balance = before - amount ~/ BigInt.two;
      await expectLater(
          runTimed(sized), throwsA(isA<EarlierPolymarketWithdrawalPending>()));
      expect(submissions, 1);
      expect(jsonDecode(box.get(_wallet)!)['stage'], 'submitting');
    });

    test('a stale record without its amount stays blocked', () async {
      final row = Map<String, Object?>.from(jsonDecode(box.get(_wallet)!));
      row.remove('amountMicros');
      row.remove('balanceMicros');
      await box.put(_wallet, jsonEncode(row));
      clock = clock.add(const Duration(hours: 2));
      await expectLater(
          runTimed(sized), throwsA(isA<EarlierPolymarketWithdrawalPending>()));
      expect(balanceReads, 0);
      expect(submissions, 1);
    });

    test('records with a transaction id keep their relayer reconciliation',
        () async {
      await box.delete(_wallet);
      status = null;
      await expectLater(
          runTimed(sized), throwsA(isA<PendingPolymarketWithdrawal>()));
      expect(jsonDecode(box.get(_wallet)!)['txId'], 'tx-43');
      clock = clock.add(const Duration(hours: 2));
      balance = before;
      await expectLater(
          runTimed(sized), throwsA(isA<EarlierPolymarketWithdrawalPending>()));
      expect(balanceReads, 0);
      expect(submissions, 2);
    });
  });

  test('status lookup error keeps the durable record and never sends again',
      () async {
    await expectLater(
        run(acceptedTimeout), throwsA(isA<PendingPolymarketWithdrawal>()));
    await expectLater(
        guard.run(
            walletId: 'spending',
            depositWallet: _wallet,
            transactionState: (_) async =>
                throw TimeoutException('status unavailable'),
            submit: successful),
        throwsA(isA<EarlierPolymarketWithdrawalPending>()));
    expect(submissions, 1);
    expect(jsonDecode(box.get(_wallet)!)['stage'], 'submitting');
  });
}
