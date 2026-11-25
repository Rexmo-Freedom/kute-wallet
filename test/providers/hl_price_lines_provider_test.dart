import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/hl_price_line.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hl_price_lines_provider.dart';

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 100,
  midPx: 100,
  prevDayPx: 90,
  dayNtlVlm: 0,
);
const _spot = HlMarket(
  coin: 'QQQ',
  wireCoin: '@142',
  assetId: 10142,
  kind: HlMarketKind.spot,
  szDecimals: 2,
  maxLeverage: 1,
  onlyIsolated: false,
  markPx: 100,
  midPx: 100,
  prevDayPx: 90,
  dayNtlVlm: 0,
);
const _btcKey = 'hl:perp::BTC';
const _spotKey = 'hl:spot::%40142';

String _sameWire(String coin) => coin;

Future<void> _settle(Box<String> box, bool Function() ready,
    {String? reason}) async {
  final elapsed = Stopwatch()..start();
  while (!ready() && elapsed.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue, reason: '$reason ${box.toMap()}');
}

void main() {
  late Directory dir;
  late Box<String> box;
  late ProviderContainer container;
  HlPriceLinesNotifier notifier() =>
      container.read(hlPriceLinesProvider.notifier);
  List<HlPriceLine> lines() => container.read(hlPriceLinesProvider);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kute-price-lines-');
    Hive.init(dir.path);
    box = await Hive.openBox<String>(HlPriceLinesNotifier.kBoxName);
    container = ProviderContainer();
  });

  tearDown(() async {
    await notifier().debugWrites;
    container.dispose();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  HlPriceLineRefusal? addBtc(double level, {double? now = 100}) => notifier()
      .add(market: _btc, marketKey: _btcKey, level: level, reference: now);

  test('the direction comes from the price when the line was set', () {
    expect(addBtc(110), isNull);
    expect(addBtc(90), isNull);
    expect(lines().map((l) => l.direction),
        [HlPriceLineDirection.above, HlPriceLineDirection.below]);
    expect(lines().every((l) => !l.isReached), isTrue);
    expect(lines().first.kind, HlMarketKind.perp);
  });

  test('a crossing marks a line once, and only the side it waits on', () {
    addBtc(110);
    addBtc(90);
    notifier().applyLiveTicks({'BTC': 105}, _sameWire);
    expect(lines().every((l) => !l.isReached), isTrue);

    notifier().applyLiveTicks({'BTC': 111}, _sameWire);
    final first = lines().first.reachedAtMs;
    expect(first, isNotNull);
    expect(lines().last.isReached, isFalse);

    // Once: the next ticks leave the stamp as it is, and a list that did
    // not change is not written again.
    final before = lines();
    notifier().applyLiveTicks({'BTC': 200}, _sameWire);
    expect(identical(lines(), before), isTrue);
    expect(lines().first.reachedAtMs, first);

    notifier().applyLiveTicks({'BTC': 89}, _sameWire);
    expect(lines().last.isReached, isTrue);
  });

  test('a price jumped past the line while nobody watched still marks it', () {
    addBtc(110);
    notifier().applyLiveTicks({'BTC': 150}, _sameWire);
    expect(lines().single.isReached, isTrue);
  });

  test('another market with the same display coin never marks a line', () {
    notifier()
        .add(market: _spot, marketKey: _spotKey, level: 110, reference: 100);
    notifier().applyLiveTicks({'QQQ': 500}, (coin) => 'xyz:QQQ');
    expect(lines().single.isReached, isFalse);
    notifier().applyLiveTicks({'QQQ': 500}, (coin) => '@142');
    expect(lines().single.isReached, isTrue);
  });

  test('refusals change nothing, and the limit counts every market', () {
    expect(addBtc(100), HlPriceLineRefusal.atPrice);
    expect(addBtc(5000), HlPriceLineRefusal.tooFar);
    expect(lines(), isEmpty);
    for (var i = 0; i < kHlPriceLineLimit - 1; i++) {
      expect(addBtc(110.0 + i), isNull);
    }
    expect(
        notifier().add(
            market: _spot, marketKey: _spotKey, level: 110, reference: 100),
        isNull);
    expect(addBtc(150), HlPriceLineRefusal.limit);
    expect(lines().length, kHlPriceLineLimit);
  });

  test('saved per market, removed for good, reached survives a restart',
      () async {
    addBtc(110);
    notifier()
        .add(market: _spot, marketKey: _spotKey, level: 90, reference: 100);
    final btcId = lines().first.id;
    notifier().applyLiveTicks({'BTC': 120}, _sameWire);
    await _settle(box, () {
      final raw = box.get(_btcKey);
      return raw != null && raw.contains('"hit"') && box.get(_spotKey) != null;
    }, reason: 'written');
    expect((jsonDecode(box.get(_btcKey)!) as List).single['coin'], 'BTC');
    expect((jsonDecode(box.get(_spotKey)!) as List).single['wire'], '@142');

    container.dispose();
    container = ProviderContainer();
    container.read(hlPriceLinesProvider);
    await _settle(box, () => lines().length == 2, reason: 'reload');
    expect(lines().firstWhere((l) => l.id == btcId).isReached, isTrue);

    notifier().remove(btcId);
    await _settle(box, () => box.get(_btcKey) == '[]', reason: 'removed');
    expect(lines().single.coin, 'QQQ');
  });

  test('one market reads its own lines, waiting first, newest first', () {
    addBtc(110);
    addBtc(120);
    addBtc(130);
    notifier()
        .add(market: _spot, marketKey: _spotKey, level: 90, reference: 100);
    notifier().applyLiveTicks({'BTC': 111}, _sameWire);
    final mine = container.read(hlPriceLinesForMarketProvider(_btcKey));
    expect(mine.length, 3);
    expect(mine.last.level, 110);
    expect(mine.last.isReached, isTrue);
    expect(mine.first.isReached, isFalse);
  });

  test('a corrupt stored list is skipped, the rest still loads', () async {
    await box.put('broken', 'not json');
    await box.put(
        _btcKey,
        jsonEncode([
          {'id': 'x'},
          HlPriceLine(
            id: 'ok',
            marketKey: _btcKey,
            coin: 'BTC',
            wireCoin: 'BTC',
            kind: HlMarketKind.perp,
            level: 110,
            direction: HlPriceLineDirection.above,
            createdAtMs: 1,
          ).toJson(),
        ]));
    container.read(hlPriceLinesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // The broken key must not take the good one down with it.
    expect(lines().map((l) => l.id), ['ok']);
  });
}
