// lib/providers/chart_drawings_provider.dart
//
// Per-market persistence for the user's chart drawings (trendlines,
// levels, rays, rectangles, Fibonacci and notes). Local only:
// one Hive box ('hl_chart_drawings'), one JSON-encoded list per market
// identity, no backend. Drawings are stored in chart coordinates (time ms,
// price), so they re-anchor correctly on any timeframe.
//
// Mutations wait for the initial load, then persist captured snapshots in
// order. Closing the editor never needs an explicit save. Undo/redo keeps
// bounded local history for creations, edits and deletions.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart';

/// Max drawings kept per market — a sanity bound so the box can't grow
/// without limit; further creations wait until a drawing is removed.
const int kMaxDrawingsPerMarket = 40;

/// Display symbols can be shared by spot, native perps and builder venues.
/// Drawings follow the actual market, while remaining shared by its timeframes.
String hlChartDrawingMarketKey(HlMarket market) =>
    'hl:${market.kind.name}:${Uri.encodeComponent(market.dex)}:'
    '${Uri.encodeComponent(market.wireCoin)}';

class ChartDrawingsNotifier extends FamilyNotifier<List<ChartDrawing>, String> {
  static const _kBoxName = 'hl_chart_drawings';
  Future<void>? _initialLoad;
  bool _disposed = false;
  final List<List<ChartDrawing>> _undo = [];
  final List<List<ChartDrawing>> _redo = [];
  Future<void> _writes = Future.value();

  bool get canUndo => _undo.isNotEmpty || state.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  @override
  List<ChartDrawing> build(String arg) {
    ref.onDispose(() => _disposed = true);
    // Every mutation waits for this same read. Parallel first writes must
    // never start a second load and merge another market's legacy state.
    _initialLoad = _load(arg);
    return const [];
  }

  Future<Box<String>> _box() => Hive.openBox<String>(_kBoxName);

  Future<void> _load(String marketKey) async {
    try {
      final box = await _box();
      var raw = box.get(marketKey);
      var migrated = false;
      // The old display-symbol key was ambiguous. Preserve it only for the
      // native perp; never copy it into every spot/builder market sharing
      // that symbol. An explicit [] marker prevents deleted legacy drawings
      // from reappearing when this market is opened again.
      const nativePrefix = 'hl:perp::';
      if (raw == null && marketKey.startsWith(nativePrefix)) {
        final legacyCoin =
            Uri.decodeComponent(marketKey.substring(nativePrefix.length));
        raw = box.get(legacyCoin);
        migrated = raw != null;
      }
      if (_disposed || raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <ChartDrawing>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        try {
          final drawing = ChartDrawing.fromJson(Map<String, dynamic>.from(e));
          if (drawing.isValid) loaded.add(drawing);
        } catch (_) {/* skip a corrupt entry */}
      }
      if (_disposed) return;
      final ids = {for (final drawing in state) drawing.id};
      final merged = [
        ...loaded.where((drawing) => !ids.contains(drawing.id)),
        ...state,
      ];
      state = merged.length > kMaxDrawingsPerMarket
          ? merged.sublist(merged.length - kMaxDrawingsPerMarket)
          : merged;
      if (migrated) {
        await box.put(marketKey,
            jsonEncode([for (final drawing in state) drawing.toJson()]));
      }
    } catch (_) {/* local-only drawing storage must not block the chart */}
  }

  void _afterLoad(void Function() mutation) {
    unawaited(_initialLoad!.then((_) {
      if (!_disposed) mutation();
    }));
  }

  void _replace(List<ChartDrawing> next) {
    _undo.add(List.unmodifiable(state));
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
    state = List.unmodifiable(next);
    _persist();
  }

  void add(ChartDrawing drawing) {
    if (!drawing.isValid) return;
    _afterLoad(() {
      if (state.length >= kMaxDrawingsPerMarket) return;
      _replace([...state, drawing]);
    });
  }

  void update(ChartDrawing drawing) {
    if (!drawing.isValid) return;
    _afterLoad(() {
      final idx = state.indexWhere((d) => d.id == drawing.id);
      if (idx < 0 ||
          jsonEncode(state[idx].toJson()) == jsonEncode(drawing.toJson())) {
        return;
      }
      final next = List<ChartDrawing>.of(state)..[idx] = drawing;
      _replace(next);
    });
  }

  void remove(String id) => _afterLoad(() {
        final next = state.where((d) => d.id != id).toList(growable: false);
        if (next.length != state.length) _replace(next);
      });

  /// Clears every drawing on this market in one undoable step.
  void removeAll() => _afterLoad(() {
        if (state.isNotEmpty) _replace(const []);
      });

  /// Undo edits and deletions as well as creation. On a freshly reopened
  /// chart, retain the previous remove-last behavior for saved drawings.
  void undoLast() => _afterLoad(() {
        if (!canUndo) return;
        _redo.add(List.unmodifiable(state));
        state = _undo.isNotEmpty
            ? _undo.removeLast()
            : List.unmodifiable(state.sublist(0, state.length - 1));
        _persist();
      });

  void redo() => _afterLoad(() {
        if (_redo.isEmpty) return;
        _undo.add(List.unmodifiable(state));
        state = _redo.removeLast();
        _persist();
      });

  void _persist() {
    final key = arg;
    final encoded = jsonEncode([for (final d in state) d.toJson()]);
    // Serialize captured snapshots: a slow earlier disk write cannot undo
    // a later edit. Already queued writes survive closing the chart.
    _writes = _writes.then((_) async {
      try {
        final box = await _box();
        await box.put(key, encoded);
      } catch (_) {/* local chart storage must not interrupt the UI */}
    });
  }
}

/// Saved drawings for [hlChartDrawingMarketKey], kept alive across reopening.
final hlChartDrawingsProvider =
    NotifierProvider.family<ChartDrawingsNotifier, List<ChartDrawing>, String>(
  ChartDrawingsNotifier.new,
);

/// Preferences follow the canonical market identity, independent of wallet.
/// The legacy global indicators are used once as migration defaults only.
/// The chart style and candle interval are not here: like a TradingView
/// layout they are one global choice for every Hyperliquid market (see
/// hlChartLayoutProvider). Older records still carry 'timeframe', 'asLine'
/// and 'style' keys; they are ignored.
class ChartPreferences {
  const ChartPreferences({
    this.indicators = const {'vol'},
    this.magnet = true,
    this.params = const {},
    this.logScale = false,
  });

  /// The indicators on, in the order they were switched on (the oldest
  /// first: the sheet's limits turn that one off).
  final Set<String> indicators;

  /// The drawing magnet (snap to candle prices). On by default; stored
  /// as 'snap', so the old 'magnet' key (written false for everyone
  /// while it defaulted off) is ignored.
  final bool magnet;

  /// Each indicator's settings where they differ from its defaults
  /// (hl_chart_indicator_catalog.dart: hlIndParams resolves them).
  final Map<String, List<num>> params;

  /// The price axis maps ln(price): equal percentage moves look equal.
  final bool logScale;

  ChartPreferences copyWith({
    Set<String>? indicators,
    bool? magnet,
    Map<String, List<num>>? params,
    bool? logScale,
  }) =>
      ChartPreferences(
        indicators: indicators ?? this.indicators,
        magnet: magnet ?? this.magnet,
        params: params ?? this.params,
        logScale: logScale ?? this.logScale,
      );

  Map<String, Object> toJson() => {
        'indicators': indicators.toList(),
        'snap': magnet,
        if (params.isNotEmpty) 'params': params,
        if (logScale) 'log': true,
      };
}

/// The Hyperliquid chart's layers. They are toggled in the same list as
/// the indicators and stored beside them, per market. All are OFF until
/// switched on, except the buy/sell pressure strip and the person's own
/// trades, each on until its off key ([kHlLayerPressureOff],
/// [kHlLayerMyTradesOff]) is stored.
const String kHlLayerPressureOff = 'nopressure';
const String kHlLayerMyTradesOff = 'nomytrades';
const String kHlLayerBigTrades = 'bigtrades';
const String kHlLayerFunding = 'fundflip';
const String kHlLayerOi = 'oisignal';
const String kHlLayerCrowd = 'crowd';
const String kHlLayerMacro = 'macro';

class ChartPreferencesNotifier
    extends FamilyNotifier<ChartPreferences, String> {
  /// The indicators the Chart sheet offers (the curated catalog, founder
  /// 4 November 2026) and the market-signal layers stored beside them.
  /// Anything else a record still carries (MA 20/50 under 'ma' before it
  /// became SMA 50/200, Stoch, Vol MA) loads as off.
  static final supportedIndicators = {
    ...kHlIndicatorKeys,
    kHlLayerPressureOff,
    kHlLayerMyTradesOff,
    kHlLayerBigTrades,
    kHlLayerFunding,
    kHlLayerOi,
    kHlLayerCrowd,
    kHlLayerMacro,
  };

  /// What a stored record may switch on: the catalog, and the layer the
  /// Chart sheet offers.
  static final Set<String> shownIndicators = {
    ...kHlIndicatorKeys,
    kHlLayerMyTradesOff,
  };

  bool _disposed = false;
  late Future<void> _loaded;
  Future<void> _writes = Future.value();

  @override
  ChartPreferences build(String arg) {
    ref.onDispose(() => _disposed = true);
    _loaded = _load();
    return const ChartPreferences();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>('hl_chart_preferences');
      final encoded = box.get(arg);
      Object? raw;
      if (encoded != null) {
        raw = jsonDecode(encoded);
      } else {
        final legacy = await Hive.openBox('settings');
        raw = {
          'indicators': legacy.get('hlChartIndicators') ?? ['vol']
        };
      }
      if (_disposed || raw is! Map) return;
      final indicators = raw['indicators'];
      state = ChartPreferences(
        indicators: indicators is List
            ? Set.unmodifiable(indicators
                .whereType<String>()
                .where(shownIndicators.contains))
            : const {'vol'},
        magnet: raw['snap'] != false,
        params: _readParams(raw['params']),
        // An older build kept the log axis among the indicators.
        logScale: raw['log'] == true ||
            (indicators is List && indicators.contains('log')),
      );
      if (encoded == null) await box.put(arg, jsonEncode(state.toJson()));
    } catch (_) {
      /* keep safe chart defaults when local storage is unavailable */
    }
  }

  void _update(ChartPreferences Function(ChartPreferences) change) {
    unawaited(_loaded.then((_) {
      if (_disposed) return;
      state = change(state);
      final key = arg;
      final encoded = jsonEncode(state.toJson());
      _writes = _writes.then((_) async {
        try {
          final box = await Hive.openBox<String>('hl_chart_preferences');
          await box.put(key, encoded);
        } catch (_) {/* chart preferences never block use */}
      });
    }));
  }

  void toggleIndicator(String key) {
    if (!supportedIndicators.contains(key)) return;
    _update((old) {
      final next = {...old.indicators};
      if (!next.add(key)) next.remove(key);
      return old.copyWith(indicators: Set.unmodifiable(next));
    });
  }

  /// Replaces the whole set at once (the sheet's two-pane rule and its
  /// Reset), keeping the given order: the oldest pane comes first.
  void setIndicators(Iterable<String> keys) {
    _update((old) => old.copyWith(
        indicators: Set.unmodifiable(keys.where(supportedIndicators.contains))));
  }

  void toggleMagnet() => _update((old) => old.copyWith(magnet: !old.magnet));

  void setLogScale(bool on) => _update((old) => old.copyWith(logScale: on));

  /// Sets [key]'s settings; its defaults (or null) drop the stored entry.
  void setParams(String key, List<num>? values) {
    final spec = hlIndSpec(key);
    if (spec == null) return;
    _update((old) {
      final next = {...old.params};
      final clamped = values == null
          ? null
          : [
              for (var i = 0; i < spec.params.length; i++)
                spec.params[i].clamp(i < values.length
                    ? values[i]
                    : spec.params[i].defaultValue),
            ];
      if (clamped == null || _sameList(clamped, spec.defaults)) {
        next.remove(key);
      } else {
        next[key] = List.unmodifiable(clamped);
      }
      return old.copyWith(params: Map.unmodifiable(next));
    });
  }

  /// Every indicator back to its defaults.
  void clearParams() =>
      _update((old) => old.copyWith(params: const <String, List<num>>{}));

  static bool _sameList(List<num> a, List<num> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Map<String, List<num>> _readParams(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<num>>{};
    raw.forEach((key, value) {
      if (key is! String || value is! List || hlIndSpec(key) == null) return;
      out[key] = List.unmodifiable(hlIndParams(key, {
        key: [for (final v in value) v is num ? v : double.nan],
      }));
    });
    return Map.unmodifiable(out);
  }
}

final hlChartPreferencesProvider =
    NotifierProvider.family<ChartPreferencesNotifier, ChartPreferences, String>(
        ChartPreferencesNotifier.new);
