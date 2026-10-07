import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:kute/services/polymarket_backend_service.dart';

void main() {
  const account = '0x1111111111111111111111111111111111111111';
  final id = '0x${'a' * 64}';
  late Directory directory;
  late Box<String> box;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prediction-journal-');
    Hive.init(directory.path);
    box = await Hive.openBox<String>(HotPolymarketOrderGuard.boxName);
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Map<String, Object?> row(String stage, {String? token}) => {
        'version': 1,
        'walletId': 'spending',
        'depositWallet': account,
        'orderId': id,
        'stage': stage,
        'submittedAtMs': 0,
        if (token != null) 'tokenId': token,
      };
  Future<void> run(
          {String? token,
          Future<Map<String, dynamic>?> Function(String)? lookup,
          required Future<void> Function() action}) =>
      HotPolymarketOrderGuard().run<void>(
          walletId: 'spending',
          depositWallet: account,
          tokenId: token,
          lookup:
              lookup ?? (_) async => throw StateError('Must not need a lookup'),
          action: (_) => action());

  test('accepted order does not wait for a later local acknowledgement',
      () async {
    await box.put(account, jsonEncode(row('accepted')));
    var calls = 0;
    await run(
        token: '1',
        action: () async {
          calls++;
        });
    expect(calls, 1);
  });
  test('a fresh submission the venue does not know keeps blocking', () async {
    final fresh = row('submitting', token: '1')
      ..['submittedAtMs'] = DateTime.now().millisecondsSinceEpoch;
    await box.put('$account:1', jsonEncode(fresh));
    await expectLater(
        run(
            token: '1',
            lookup: (_) async => null,
            action: () async => fail('Must not submit')),
        throwsA(isA<PendingPolymarketOrder>()));
    expect(jsonDecode(box.get('$account:1')!)['stage'], 'submitting');
  });

  test('an old submission the venue does not know is settled and released',
      () async {
    // submittedAtMs 0: far older than the grace period.
    await box.put('$account:1', jsonEncode(row('submitting', token: '1')));
    var submitted = false;
    await run(
        token: '1',
        lookup: (_) async => null,
        action: () async {
          submitted = true;
        });
    expect(submitted, isTrue);
    expect(jsonDecode(box.get('$account:1')!)['stage'], 'rejected');
  });
  test('a venue that never answers is reported as unreachable, still blocking',
      () async {
    await box.put('$account:1', jsonEncode(row('submitting', token: '1')));
    await expectLater(
        run(
            token: '1',
            lookup: (_) async => throw const SocketException('offline'),
            action: () async => fail('Must not submit')),
        throwsA(isA<PolymarketOrderCheckUnavailable>()));
    // Still a pending order for every caller that only knows that type.
    expect(const PolymarketOrderCheckUnavailable(),
        isA<PendingPolymarketOrder>());
    expect(jsonDecode(box.get('$account:1')!)['stage'], 'submitting');
  });

  test('another five-minute market is not blocked by an unrelated outcome',
      () async {
    await box.put('$account:1', jsonEncode(row('submitting', token: '1')));
    var calls = 0;
    await run(
        token: '2',
        action: () async {
          calls++;
        });
    expect(calls, 1);
    expect(jsonDecode(box.get('$account:1')!)['stage'], 'submitting');
  });
  test('legacy unresolved row remains protected when its outcome is unknown',
      () async {
    // Recent enough that the venue not knowing it proves nothing yet.
    final fresh = row('submitting')
      ..['submittedAtMs'] = DateTime.now().millisecondsSinceEpoch;
    await box.put(account, jsonEncode(fresh));
    await expectLater(
        run(
            token: '2',
            lookup: (_) async => null,
            action: () async => fail('Must not submit')),
        throwsA(isA<PendingPolymarketOrder>()));
  });
  test('legacy receipt for another outcome permits the new market', () async {
    await box.put(account, jsonEncode(row('submitting')));
    var calls = 0;
    await run(
        token: '2',
        lookup: (_) async => {
              'id': id,
              'maker_address': account,
              'status': 'MATCHED',
              'asset_id': '1'
            },
        action: () async {
          calls++;
        });
    expect(calls, 1);
    expect(jsonDecode(box.get(account)!)['stage'], 'accepted');
  });
  test('acknowledged POST stays resolved if later UI work fails', () async {
    const exchange = '0xE111180000d2663C0091e4f400237545B87B996B';
    final order = OrderStructV2(
      salt: BigInt.one,
      maker: account,
      signer: account,
      tokenId: '1',
      makerAmount: BigInt.from(1000000),
      takerAmount: BigInt.from(2000000),
      side: 0,
      signatureType: 3,
      timestamp: BigInt.from(1700000000000),
      metadata: '0x${'0' * 64}',
      builder: '0x${'0' * 64}',
    );
    final hash =
        '0x${orderV2TypedData(order: order, verifyingContract: exchange).digest.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
    var posts = 0;
    await expectLater(
        HotPolymarketOrderGuard().run<void>(
            walletId: 'spending',
            depositWallet: account,
            tokenId: '1',
            lookup: (_) async => throw StateError('No previous order'),
            action: (submit) async {
              await submit(
                  order: SignedOrderV2(order: order, signature: 'fixture'),
                  exchange: exchange,
                  ensureCurrent: () {},
                  send: (beforePost) async {
                    beforePost();
                    posts++;
                    return {
                      'success': true,
                      'orderID': hash,
                      'status': 'matched'
                    };
                  });
              throw StateError('Local UI refresh failed');
            }),
        throwsStateError);
    expect(posts, 1);
    expect(jsonDecode(box.get('$account:1')!)['stage'], 'accepted');
    await run(token: '1', action: () async {});
  });
  test('a definitive FAK refusal releases the same outcome for a bounded retry',
      () async {
    const exchange = '0xE111180000d2663C0091e4f400237545B87B996B';
    final order = OrderStructV2(
        salt: BigInt.one,
        maker: account,
        signer: account,
        tokenId: '1',
        makerAmount: BigInt.from(3000000),
        takerAmount: BigInt.from(6000000),
        side: 0,
        signatureType: 3,
        timestamp: BigInt.from(1700000000000),
        metadata: '0x${'0' * 64}',
        builder: '0x${'0' * 64}');
    await expectLater(
        HotPolymarketOrderGuard().run<void>(
            walletId: 'spending',
            depositWallet: account,
            tokenId: '1',
            lookup: (_) async => fail('No pending order'),
            action: (submit) async {
              await submit(
                  order: SignedOrderV2(order: order, signature: 'fixture'),
                  exchange: exchange,
                  ensureCurrent: () {},
                  send: (beforePost) async {
                    beforePost();
                    throw const PolymarketOrderNotAcceptedException(
                        'no orders found to match with FAK order. FAK orders are partially filled or killed if no match is found.');
                  });
            }),
        throwsA(isA<PolymarketOrderNotAcceptedException>()));
    expect(jsonDecode(box.get('$account:1')!)['stage'], 'rejected');
    var nextReviewReached = false;
    await run(
        token: '1',
        action: () async {
          nextReviewReached = true;
        });
    expect(nextReviewReached, isTrue);
  });
  test('unmatched means accepted on the book, not a failed order', () async {
    await box.put(account, jsonEncode(row('submitting')));
    await expectLater(
        run(
            token: '1',
            lookup: (_) async => {
                  'id': id,
                  'maker_address': account,
                  'status': 'UNMATCHED',
                  'asset_id': '1'
                },
            action: () async => fail('Do not replace the recovered order')),
        throwsA(isA<ResolvedPolymarketOrder>()
            .having((e) => e.accepted, 'accepted', true)));
    expect(jsonDecode(box.get(account)!)['stage'], 'accepted');
  });

  group('a first prediction stuck before its order', () {
    test(
        'a placement still running here refuses the next tap as in '
        'progress, not as an unknown submission, and records nothing',
        () async {
      final release = Completer<void>();
      final first = run(token: '1', action: () => release.future);
      await pumpEventQueue();
      expect(HotPolymarketOrderGuard.isBusy(account), isTrue);
      await expectLater(
          run(token: '1', action: () async => fail('Must not submit')),
          throwsA(isA<PolymarketOrderInProgress>()));
      // Still a pending order for every caller that only knows that type,
      // so nothing new can be sent while the first one runs.
      expect(const PolymarketOrderInProgress(), isA<PendingPolymarketOrder>());
      expect(box.keys, isEmpty);
      release.complete();
      await first;
      expect(HotPolymarketOrderGuard.isBusy(account), isFalse);
    });

    test('the status check waits for the running placement, then answers',
        () async {
      final release = Completer<void>();
      final first = run(token: '1', action: () => release.future);
      await pumpEventQueue();
      final check = HotPolymarketOrderGuard().run<void>(
        walletId: 'spending',
        depositWallet: account,
        tokenId: '1',
        lookup: (_) async => fail('No submission to look up'),
        action: (_) async {},
        busyWait: const Duration(seconds: 5),
      );
      var checked = false;
      unawaited(check.then((_) => checked = true));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(checked, isFalse);
      release.complete();
      await first;
      await check;
      expect(checked, isTrue);
    });

    test('a placement never waits for another one to finish', () async {
      final release = Completer<void>();
      final first = run(token: '1', action: () => release.future);
      await pumpEventQueue();
      final clock = Stopwatch()..start();
      await expectLater(
          run(token: '1', action: () async => fail('Must not submit')),
          throwsA(isA<PolymarketOrderInProgress>()));
      expect(clock.elapsed, lessThan(const Duration(milliseconds: 200)));
      release.complete();
      await first;
    });
  });

  group('a submission the venue answered for inconclusively', () {
    Map<String, dynamic> odd(String status) =>
        {'id': id, 'maker_address': account, 'status': status};

    test('keeps blocking while recent', () async {
      final fresh = row('submitting', token: '1')
        ..['submittedAtMs'] = DateTime.now().millisecondsSinceEpoch;
      await box.put('$account:1', jsonEncode(fresh));
      await expectLater(
          run(
              token: '1',
              lookup: (_) async => odd('SOMETHING_NEW'),
              action: () async => fail('Must not submit')),
          throwsA(isA<PendingPolymarketOrder>()));
      expect(jsonDecode(box.get('$account:1')!)['stage'], 'submitting');
    });

    test(
        'past the expiry is settled as out there once (nothing sent), '
        'then the outcome is free', () async {
      final old = row('submitting', token: '1')
        ..['submittedAtMs'] = DateTime.now()
            .subtract(HotPolymarketOrderGuard.unresolvedSubmissionExpiry)
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch;
      await box.put('$account:1', jsonEncode(old));
      await expectLater(
          run(
              token: '1',
              lookup: (_) async => odd('SOMETHING_NEW'),
              action: () async => fail('Must not submit on this tap')),
          throwsA(isA<ResolvedPolymarketOrder>()
              .having((e) => e.accepted, 'accepted', true)));
      expect(jsonDecode(box.get('$account:1')!)['stage'], 'accepted');
      var submitted = false;
      await run(
          token: '1',
          action: () async {
            submitted = true;
          });
      expect(submitted, isTrue);
    });
  });

  test('hasUnsettled sees only rows still waiting for their answer', () async {
    expect(await HotPolymarketOrderGuard.hasUnsettled(account), isFalse);
    await box.put('$account:1', jsonEncode(row('accepted', token: '1')));
    expect(await HotPolymarketOrderGuard.hasUnsettled(account), isFalse);
    await box.put('$account:2', jsonEncode(row('submitting', token: '2')));
    expect(await HotPolymarketOrderGuard.hasUnsettled(account), isTrue);
    expect(
        await HotPolymarketOrderGuard.hasUnsettled(
            '0x2222222222222222222222222222222222222222'),
        isFalse);
  });
}
