import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/chart_drawings_provider.dart';

HlMarket _market(String coin, String wireCoin,
        {HlMarketKind kind = HlMarketKind.perp, String dex = ''}) =>
    HlMarket(
        coin: coin,
        wireCoin: wireCoin,
        assetId: 1,
        kind: kind,
        szDecimals: 2,
        maxLeverage: 1,
        onlyIsolated: false,
        markPx: 100,
        midPx: 100,
        prevDayPx: 90,
        dayNtlVlm: 0,
        dex: dex,
        isHip3: dex.isNotEmpty);

ChartDrawing _drawing(String id) => ChartDrawing(
    id: id,
    tool: ChartDrawingTool.level,
    points: const [ChartDrawingPoint(timeMs: 100, price: 110)]);

Future<void> _until(bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready() && elapsed.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue);
}

void main() {
  late Directory dir;
  late Box<String> box;
  late ProviderContainer container;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kute-drawing-isolation-');
    Hive.init(dir.path);
    box = await Hive.openBox<String>('hl_chart_drawings');
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('same symbol on spot and different perp venues has isolated drawings',
      () async {
    final keys = [
      hlChartDrawingMarketKey(_market('BTC', 'BTC')),
      hlChartDrawingMarketKey(_market('BTC', '@142', kind: HlMarketKind.spot)),
      hlChartDrawingMarketKey(_market('BTC', 'xyz:BTC', dex: 'xyz')),
      hlChartDrawingMarketKey(_market('BTC', 'abc:BTC', dex: 'abc')),
      hlChartDrawingMarketKey(_market('ETH', 'ETH')),
    ];
    expect(keys.toSet().length, keys.length);
    for (var i = 0; i < keys.length; i++) {
      container
          .read(hlChartDrawingsProvider(keys[i]).notifier)
          .add(_drawing('drawing-$i'));
    }
    await _until(() => keys.every(box.containsKey));
    container.dispose();
    container = ProviderContainer();
    for (var i = 0; i < keys.length; i++) {
      final provider = hlChartDrawingsProvider(keys[i]);
      await _until(() => container.read(provider).isNotEmpty);
      expect(container.read(provider).map((d) => d.id), ['drawing-$i']);
    }
  });

  test('legacy symbol drawings migrate only to native perp and stay deleted',
      () async {
    await box.put('BTC', jsonEncode([_drawing('legacy').toJson()]));
    final native = hlChartDrawingMarketKey(_market('BTC', 'BTC'));
    final spot = hlChartDrawingMarketKey(
        _market('BTC', '@142', kind: HlMarketKind.spot));
    final builder =
        hlChartDrawingMarketKey(_market('BTC', 'xyz:BTC', dex: 'xyz'));
    container.read(hlChartDrawingsProvider(spot));
    container.read(hlChartDrawingsProvider(builder));
    await _until(
        () => container.read(hlChartDrawingsProvider(native)).isNotEmpty);
    expect(container.read(hlChartDrawingsProvider(spot)), isEmpty);
    expect(container.read(hlChartDrawingsProvider(builder)), isEmpty);
    container.read(hlChartDrawingsProvider(native).notifier).undoLast();
    await _until(() => box.get(native) == '[]');
    container.dispose();
    container = ProviderContainer();
    // Adding immediately exercises the initial-load merge too: the old
    // display-symbol drawing must not be imported a second time.
    container
        .read(hlChartDrawingsProvider(native).notifier)
        .add(_drawing('new'));
    await _until(() => box.get(native)?.contains('new') == true);
    expect(container.read(hlChartDrawingsProvider(native)).map((d) => d.id),
        ['new']);
  });

  test('first placement merges with saved drawings without duplicating them',
      () async {
    final key = hlChartDrawingMarketKey(_market('ETH', 'ETH'));
    await box.put(key, jsonEncode([_drawing('saved').toJson()]));
    final notifier = container.read(hlChartDrawingsProvider(key).notifier);
    notifier.add(_drawing('first'));
    notifier.add(_drawing('second'));
    await _until(() => box.get(key)?.contains('second') == true);
    expect(container.read(hlChartDrawingsProvider(key)).map((d) => d.id),
        ['saved', 'first', 'second']);
  });

  test(
      'a newer build\'s tool is kept, skipped and written back byte for '
      'byte through a load, an edit and a save', () async {
    final key = hlChartDrawingMarketKey(_market('SOL', 'SOL'));
    // What a newer build wrote: its own tool (with its own fields) among
    // a known drawing that also carries a key this build does not read.
    const unknown = '{"id":"future","tool":"pitchforkSchiff",'
        '"points":[{"t":1,"p":2.5},{"t":3,"p":4},{"t":5,"p":6}],'
        '"color":4280391411,"w":3,"mystery":{"a":[1,2]}}';
    const known = '{"id":"lvl","tool":"level",'
        '"points":[{"t":100,"p":110.0}],"glow":true}';
    await box.put(key, '[$unknown,$known]');
    final provider = hlChartDrawingsProvider(key);
    await _until(() => container.read(provider).isNotEmpty);
    // Never shown, never turned into a trend line.
    expect(container.read(provider).map((d) => d.id), ['lvl']);
    expect(container.read(provider).single.tool, ChartDrawingTool.level);

    final notifier = container.read(provider.notifier);
    notifier.update(container.read(provider).single.copyWith(dashed: true));
    notifier.add(_drawing('new'));
    await _until(() => box.get(key)?.contains('"new"') == true);
    final saved = box.get(key)!;
    expect(saved.startsWith('[$unknown,'), isTrue, reason: saved);
    // The known drawing keeps the key it does not read, too.
    final back = (jsonDecode(saved) as List).cast<Map>();
    expect(back[1]['glow'], isTrue);
    expect(back[1]['dash'], isTrue);

    // A second load sees the same: one unknown kept, two drawings.
    container.dispose();
    container = ProviderContainer();
    await _until(() => container.read(provider).length == 2);
    container.read(provider.notifier).remove('new');
    await _until(() => box.get(key)?.contains('"new"') == false);
    expect(box.get(key)!.startsWith('[$unknown,'), isTrue);
  });
}
