// The Investing account's shared reads: one request in flight per account,
// a read sent under 950 ms ago answers the poll and the fresh read, and a
// failure (a 429 included) backs the fresh read off 1, 2, 4, 8, 15 s.

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidTradingModelProvider;

const _a = '0x1111111111111111111111111111111111111111';

HlAccountSnapshot _snap(double usd) => HlAccountSnapshot(
      accountValue: usd,
      withdrawable: usd,
      totalMarginUsed: 0,
      positions: const [],
      spotBalances: const [],
    );

/// The venue as the account notifier reads it: every read recorded with
/// its kind, answering after [latency] with the figure of the moment it
/// was SENT (as a venue answers: a request sent before a fill does not
/// show it). The light read's builder-dex part is [dexCash], the figure a
/// full read saw last (`getCreditSnapshot`).
class _Venue extends HyperliquidModel {
  double cash = 0;
  double dexCash = 0;
  double cachedDexCash = 0;
  final reads = <String>[];
  Duration latency = const Duration(milliseconds: 300);

  @override
  Future<HlAccountSnapshot> getPortfolioSnapshot(String address) async {
    reads.add('full');
    final at = _snap(cash + dexCash);
    cachedDexCash = dexCash;
    await Future<void>.delayed(latency);
    return at;
  }

  @override
  Future<HlAccountSnapshot> getCreditSnapshot(String address) async {
    reads.add('credit');
    final at = _snap(cash + cachedDexCash);
    await Future<void>.delayed(latency);
    return at;
  }
}

void main() {
  test(
      'a read that must come after now (an action answered, a ledger push) '
      'is never answered by the one in flight: one more is sent when that '
      'ends, shared by everyone who asked meanwhile', () {
    fakeAsync((async) {
      final reads = HlAccountReads();
      var sent = 0;
      var figure = 1.0;
      Future<HlAccountSnapshot> fetch() async {
        sent++;
        final at = figure;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return _snap(at);
      }

      HlAccountSnapshot? first, afterA, afterB;
      reads.read(_a, fetch).then((s) => first = s);
      async.elapse(const Duration(milliseconds: 100));
      // The venue changed; two askers know it.
      figure = 2;
      reads.read(_a, fetch, after: true).then((s) => afterA = s);
      reads.read(_a, fetch, after: true).then((s) => afterB = s);
      async.elapse(const Duration(milliseconds: 300));
      expect(sent, 1, reason: 'still one request in flight');
      async.elapse(const Duration(milliseconds: 200));
      expect(first!.withdrawable, 1);
      expect(sent, 2, reason: 'one read behind it, for both');
      async.elapse(const Duration(milliseconds: 500));
      expect(afterA!.withdrawable, 2);
      expect(afterB!.withdrawable, 2);
      expect(sent, 2);
    });
  });

  test(
      'the read queued behind one in flight is the full one when any asker '
      'needs the whole account', () {
    fakeAsync((async) {
      final reads = HlAccountReads();
      final kinds = <String>[];
      Future<HlAccountSnapshot> Function() fetch(String kind) => () async {
            kinds.add(kind);
            await Future<void>.delayed(const Duration(milliseconds: 500));
            return _snap(1);
          };
      reads.read(_a, fetch('credit'), light: true);
      reads.read(_a, fetch('credit'), after: true, light: true);
      reads.read(_a, fetch('full'), after: true);
      async.elapse(const Duration(seconds: 2));
      expect(kinds, ['credit', 'full']);
    });
  });

  group('the account notifier', () {
    late Directory hiveDir;
    late _Venue venue;
    setUpAll(() {
      hiveDir = Directory.systemTemp.createTempSync('hl_account_reads_test');
      Hive.init(hiveDir.path);
    });
    tearDownAll(() async {
      await Hive.close();
      hiveDir.deleteSync(recursive: true);
    });

    ProviderContainer container() {
      venue = _Venue();
      final c = ProviderContainer(overrides: [
        hyperliquidAddressProvider.overrideWith((_) async => _a),
        hyperliquidTradingModelProvider.overrideWithValue(venue),
      ]);
      addTearDown(c.dispose);
      c.listen(hyperliquidAccountProvider, (_, __) {});
      return c;
    }

    test(
        'refresh() reads the venue NOW: a read sent a moment before (the '
        'poll, the credit watch) does not answer it', () {
      fakeAsync((async) {
        final c = container();
        venue.cash = 25;
        async.elapse(const Duration(seconds: 1));
        expect(c.read(hyperliquidWithdrawableProvider), 25);
        final notifier = c.read(hyperliquidAccountProvider.notifier);
        // The credit watch reads (sent now, answered in 300 ms).
        notifier.freshRead();
        async.elapse(const Duration(milliseconds: 400));
        // The cash left (a sweep, a bet's leg); the order slip reads the
        // account again at Confirm to size its order on what is there.
        venue.cash = 0;
        final before = venue.reads.length;
        var done = false;
        notifier.refresh().then((_) => done = true);
        async.elapse(const Duration(milliseconds: 400));
        expect(done, isTrue);
        expect(venue.reads.length, before + 1,
            reason: 'answered by the read sent 400 ms earlier, the slip '
                'sized the order on cash that had left');
        expect(c.read(hyperliquidWithdrawableProvider), 0);
      });
    });

    test(
        'an invalidation (a fill, a ledger push, an action answered) while '
        'the light credit read is in flight ends on a full read sent after '
        'it, never on that read', () {
      fakeAsync((async) {
        final c = container();
        venue.cash = 5;
        venue.dexCash = 20;
        async.elapse(const Duration(seconds: 1));
        expect(c.read(hyperliquidWithdrawableProvider), 25);
        final notifier = c.read(hyperliquidAccountProvider.notifier);
        notifier.freshRead();
        async.elapse(const Duration(milliseconds: 100));
        // A builder-dex order filled: its dex cash is margin now.
        venue.dexCash = 0;
        c.invalidate(hyperliquidAccountProvider);
        async.elapse(const Duration(seconds: 1));
        expect(venue.reads.last, 'full');
        expect(c.read(hyperliquidAccountProvider).isLoading, isFalse);
        expect(c.read(hyperliquidWithdrawableProvider), 5,
            reason: 'the light read (sent before the fill, its builder-dex '
                'part older still) was published as the account');
      });
    });
  });

  test('a read asked while one is in flight joins it', () {
    fakeAsync((async) {
      final reads = HlAccountReads();
      var sent = 0;
      Future<HlAccountSnapshot> fetch() async {
        sent++;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return _snap(1);
      }

      final a = reads.read(_a, fetch);
      final b = reads.read(_a.toUpperCase(), fetch, reuse: true);
      final c = reads.read(_a, fetch);
      async.elapse(const Duration(seconds: 1));
      expect(sent, 1);
      expect(identical(a, b) && identical(b, c), isTrue);
    });
  });

  test('reuse: a read sent under 950 ms ago answers; one past it does not; '
      'a forced read never reuses', () {
    fakeAsync((async) {
      final reads = HlAccountReads();
      var sent = 0;
      Future<HlAccountSnapshot> fetch() async => _snap((++sent).toDouble());
      reads.read(_a, fetch);
      async.elapse(const Duration(milliseconds: 500));
      reads.read(_a, fetch, reuse: true);
      async.flushMicrotasks();
      expect(sent, 1);
      reads.read(_a, fetch);
      async.flushMicrotasks();
      expect(sent, 2, reason: 'without reuse it reads');
      async.elapse(const Duration(milliseconds: 960));
      reads.read(_a, fetch, reuse: true);
      async.flushMicrotasks();
      expect(sent, 3);
    });
  });

  test('failures back off 1, 2, 4, 8, 15, 15 s; a good read ends it', () {
    fakeAsync((async) {
      final reads = HlAccountReads();
      var fail = true;
      Future<HlAccountSnapshot> fetch() async {
        if (fail) throw StateError('429');
        return _snap(1);
      }

      final seen = <Duration>[];
      for (var i = 0; i < 6; i++) {
        reads.read(_a, fetch).then((_) {}, onError: (Object _) {});
        async.flushMicrotasks();
        expect(reads.backingOff(_a), isTrue);
        seen.add(reads.backoffOf(_a));
        async.elapse(reads.backoffOf(_a));
        expect(reads.backingOff(_a), isFalse);
      }
      expect(seen, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 15),
        Duration(seconds: 15),
      ]);
      expect(reads.failed, 6);
      fail = false;
      reads.read(_a, fetch);
      async.flushMicrotasks();
      expect(reads.backoffOf(_a), Duration.zero);
      expect(reads.lastOf(_a)!.withdrawable, 1);
    });
  });
}
