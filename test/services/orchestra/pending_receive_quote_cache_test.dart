import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra/pending_receive_quote_cache.dart';

const _walletA = 'receive-test-wallet-a';
const _walletB = 'receive-test-wallet-b';
final _expiry = DateTime.utc(2030, 1, 2, 3, 4, 5);

SwapOrder _quote({String id = 'q_receive_a', String walletId = _walletA}) =>
    SwapOrder(
      id: id,
      coinFrom: 'ETH',
      networkFrom: 'ethereum',
      coinTo: 'USDB',
      networkTo: 'spark',
      depositAddress: '0x1111111111111111111111111111111111111111',
      depositExtraId: 'deposit-memo-123',
      depositAmount: '0.012345678901234567',
      withdrawalAmount: '12.345678',
      status: 'wait',
      timestamp: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      withdrawalAddress: 'spark1synthetic-receive-recipient',
      depositMin: '0.000000000000000001',
      depositMax: '100',
      rate: '1000.000001',
      refundAddress: '0x2222222222222222222222222222222222222222',
      refundExtraId: 'refund-memo-456',
      provider: 'Orchestra',
      walletId: walletId,
      purchaseSource: 'crypto_receive',
    );

Map<String, Object?> _fields(SwapOrder quote) => {
      'id': quote.id,
      'walletId': quote.walletId,
      'coinFrom': quote.coinFrom,
      'networkFrom': quote.networkFrom,
      'coinTo': quote.coinTo,
      'networkTo': quote.networkTo,
      'depositAddress': quote.depositAddress,
      'depositExtraId': quote.depositExtraId,
      'depositAmount': quote.depositAmount,
      'withdrawalAmount': quote.withdrawalAmount,
      'status': quote.status,
      'timestamp': quote.timestamp,
      'withdrawalAddress': quote.withdrawalAddress,
      'depositMin': quote.depositMin,
      'depositMax': quote.depositMax,
      'rate': quote.rate,
      'refundAddress': quote.refundAddress,
      'refundExtraId': quote.refundExtraId,
      'provider': quote.provider,
      'expiresAt': quote.expiresAt,
      'purchaseSource': quote.purchaseSource,
    };

Future<void> _save(SwapOrder quote, {DateTime? expiresAt}) =>
    PendingReceiveQuoteCache.save(
      display: quote,
      expiresAt: expiresAt ?? _expiry,
      scope: PendingReceiveQuoteCache.capture(quote.walletId!),
    );

void main() {
  late Directory directory;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(SwapOrderAdapter().typeId)) {
      Hive.registerAdapter(SwapOrderAdapter());
    }
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pending-receive-test-');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await PendingReceiveQuoteCache.clear();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('persists exact instructions and display amounts across box reopen',
      () async {
    final quote = _quote();
    await _save(quote);
    await Hive.box<SwapOrder>(PendingReceiveQuoteCache.boxName).close();

    final restored = (await PendingReceiveQuoteCache.pending()).single;
    expect(
      _fields(restored),
      _fields(quote.copyWith(expiresAt: _expiry.millisecondsSinceEpoch)),
    );
  });

  test('same quote cannot replace previously displayed payment instructions',
      () async {
    final quote = _quote();
    await _save(quote);
    final changes = [
      quote.copyWith(depositAddress: 'another-deposit-address'),
      quote.copyWith(depositExtraId: 'another-deposit-memo'),
      quote.copyWith(depositAmount: '0.012345678901234568'),
      quote.copyWith(withdrawalAddress: 'spark1another-recipient'),
      quote.copyWith(refundAddress: 'another-refund-address'),
      quote.copyWith(refundExtraId: 'another-refund-memo'),
      quote.copyWith(walletId: _walletB),
    ];
    for (final changed in changes) {
      await expectLater(_save(changed), throwsStateError);
    }
    await expectLater(
      _save(quote, expiresAt: _expiry.add(const Duration(seconds: 1))),
      throwsStateError,
    );

    expect(
      _fields((await PendingReceiveQuoteCache.pending()).single),
      _fields(quote.copyWith(expiresAt: _expiry.millisecondsSinceEpoch)),
    );
    // Repeated identical persistence remains valid after rejected mutations.
    await _save(quote);
    expect(await PendingReceiveQuoteCache.pending(), hasLength(1));
  });

  test('expired quote survives reopen for late funding discovery', () async {
    final expired = DateTime.utc(2000, 1, 1);
    await _save(_quote(), expiresAt: expired);
    await Hive.box<SwapOrder>(PendingReceiveQuoteCache.boxName).close();

    final pending = (await PendingReceiveQuoteCache.pending()).single;
    expect(pending.id, 'q_receive_a');
    expect(pending.expiresAt, expired.millisecondsSinceEpoch);
  });

  test('completion removes only the discovered quote, durably', () async {
    await _save(_quote());
    await _save(_quote(id: 'q_receive_b'));
    await _save(_quote(id: 'q_other_wallet', walletId: _walletB));

    await PendingReceiveQuoteCache.complete('q_receive_a');
    await Hive.box<SwapOrder>(PendingReceiveQuoteCache.boxName).close();

    expect(
      (await PendingReceiveQuoteCache.pending()).map((quote) => quote.id),
      unorderedEquals(['q_receive_b', 'q_other_wallet']),
    );
  });

  test('wallet deletion fences delayed quotes while preserving another wallet',
      () async {
    await _save(_quote());
    await _save(_quote(id: 'q_other_wallet', walletId: _walletB));
    final stale = PendingReceiveQuoteCache.capture(_walletA);
    final other = PendingReceiveQuoteCache.capture(_walletB);
    final quoteReturned = Completer<void>();
    final lateSave =
        quoteReturned.future.then((_) => PendingReceiveQuoteCache.save(
              display: _quote(id: 'q_delayed'),
              expiresAt: _expiry,
              scope: stale,
            ));
    final rejected = expectLater(lateSave, throwsStateError);

    final deleting = PendingReceiveQuoteCache.deleteForWallet(_walletA);
    expect(PendingReceiveQuoteCache.isCurrent(stale), isFalse);
    expect(PendingReceiveQuoteCache.isCurrent(other), isTrue);
    await deleting;
    quoteReturned.complete();
    await rejected;

    expect(
      (await PendingReceiveQuoteCache.pending()).map((quote) => quote.id),
      ['q_other_wallet'],
    );
    await _save(_quote(id: 'q_restored_wallet'));
    expect(
      (await PendingReceiveQuoteCache.pending()).map((quote) => quote.id),
      unorderedEquals(['q_other_wallet', 'q_restored_wallet']),
    );
  });

  test('global clear fences old scopes but allows a fresh restored wallet',
      () async {
    await _save(_quote());
    await _save(_quote(id: 'q_other_wallet', walletId: _walletB));
    final staleA = PendingReceiveQuoteCache.capture(_walletA);
    final staleB = PendingReceiveQuoteCache.capture(_walletB);
    final quoteReturned = Completer<void>();
    final lateSave =
        quoteReturned.future.then((_) => PendingReceiveQuoteCache.save(
              display: _quote(id: 'q_delayed'),
              expiresAt: _expiry,
              scope: staleA,
            ));
    final rejected = expectLater(lateSave, throwsStateError);

    final clearing = PendingReceiveQuoteCache.clear();
    expect(PendingReceiveQuoteCache.isCurrent(staleA), isFalse);
    expect(PendingReceiveQuoteCache.isCurrent(staleB), isFalse);
    await clearing;
    await _save(_quote(id: 'q_restored_wallet'));
    quoteReturned.complete();
    await rejected;
    await expectLater(
      PendingReceiveQuoteCache.save(
        display: _quote(id: 'q_stale_other_wallet', walletId: _walletB),
        expiresAt: _expiry,
        scope: staleB,
      ),
      throwsStateError,
    );

    expect(
      (await PendingReceiveQuoteCache.pending()).map((quote) => quote.id),
      ['q_restored_wallet'],
    );
  });

  test('wipe fences an already queued save before its storage work starts',
      () async {
    final saving = _save(_quote());
    final rejected = expectLater(saving, throwsStateError);
    final clearing = PendingReceiveQuoteCache.clear();

    await rejected;
    await clearing;
    expect(await PendingReceiveQuoteCache.pending(), isEmpty);
    await _save(_quote(id: 'q_new_request'));
    expect(
        (await PendingReceiveQuoteCache.pending()).single.id, 'q_new_request');
  });

  test('scope cannot persist instructions for a different wallet', () async {
    await expectLater(
      PendingReceiveQuoteCache.save(
        display: _quote(),
        expiresAt: _expiry,
        scope: PendingReceiveQuoteCache.capture(_walletB),
      ),
      throwsStateError,
    );
    expect(await PendingReceiveQuoteCache.pending(), isEmpty);
  });
}
