// Live supported-routes catalog from the Flashnet Orchestration API,
// exposed app-wide.
//
// Source order:
//   1. Backend proxy GET $BACKEND/api/v1/orchestra/routes (preferred —
//      lets the backend cache / filter), else
//   2. Flashnet public GET https://orchestration.flashnet.xyz
//      /v2/orchestration/routes (no credentials; the fn_ server key
//      never lives in the app),
//   3. the last-good catalog persisted to Hive (offline starts), else
//   4. the static kOrchestraSendRoutes / kOrchestraReceiveRoutes tables
//      in lib/services/orchestra_routes.dart (fallback of last resort).
//
// Refresh: on first read (self-initializing) and every 6 hours after.
// Each successful fetch also installs the derived send/receive tables
// into orchestra_routes.dart via `setLiveOrchestraRouteCatalog`, so the
// module-level helpers (orchestraSupportsSwapAsset,
// orchestraSendChainFor, orchestraReceiveChainFor) answer from the live
// set without their call sites changing. New code should prefer
// watching this provider directly (`catalog.supportsSwapAsset(...)` /
// orchestraSupportsSwapAssetLiveProvider) so the UI re-filters when the
// catalog lands.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/helpers/orchestra_router.dart'
    show setOrchestraDecimalsCatalog;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra_routes.dart'
    show OrchestraRouteCatalog, setLiveOrchestraRouteCatalog;

class OrchestraSupportedRoutesNotifier
    extends StateNotifier<OrchestraRoutesCatalog> {
  static const String _boxName = 'orchestraRoutesCatalog';
  static const String _jsonKey = 'json';
  static const String _fetchedAtKey = 'fetchedAtMs';
  static const Duration refreshInterval = Duration(hours: 6);

  Timer? _timer;
  Future<void>? _initFuture;

  OrchestraSupportedRoutesNotifier()
      : super(OrchestraRoutesCatalog.fromStatic());

  /// Loads the persisted last-good catalog, then fetches fresh and
  /// schedules the 6h cadence. Idempotent, and every caller gets the
  /// SAME future, so a screen can await the first load instead of
  /// deciding the offering is empty a few milliseconds too early.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    await _loadPersisted();
    await refresh();
    _timer = Timer.periodic(refreshInterval, (_) => refresh());
  }

  Future<void> _loadPersisted() async {
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_jsonKey) as String?;
      if (raw == null || raw.isEmpty) return;
      final fetchedMs = box.get(_fetchedAtKey) as int?;
      final catalog = OrchestraRoutesCatalog.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
        source: OrchestraCatalogSource.cached,
        fetchedAt: fetchedMs != null
            ? DateTime.fromMillisecondsSinceEpoch(fetchedMs)
            : null,
      );
      if (catalog.hasLiveData && mounted) {
        state = catalog;
        _installLegacyTables(catalog);
      }
    } catch (_) {
      // Corrupt cache → static tables stay in force until the fetch.
    }
  }

  Future<bool>? _inflight;

  /// Fetches the catalog now. Failures keep the current state (cached
  /// or static) — a flaky network must never blank the swap offering.
  /// Concurrent calls share one request. Returns whether a live catalog
  /// was installed.
  Future<bool> refresh() => _inflight ??= _refresh().whenComplete(() {
        _inflight = null;
      });

  Future<bool> _refresh() async {
    final res = await OrchestraService.getRoutesWithOrigin();
    final fetch = res.data;
    if (fetch == null) return false;
    final catalog = OrchestraRoutesCatalog.fromJson(
      fetch.json,
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime.now(),
      fromBackend: fetch.fromBackend,
      upstreamFetchedAt: fetch.upstreamFetchedAt,
    );
    // Degenerate payloads (no assets, or no Spark-BTC anchor) are
    // ignored the same way setLiveOrchestraRouteCatalog ignores empty
    // catalogs.
    if (!catalog.hasLiveData) return false;
    if (mounted) state = catalog;
    _installLegacyTables(catalog);
    await _persist(fetch.json, catalog.fetchedAt!);
    return true;
  }

  /// For a money decision that needs a live catalog (Phase 5 plan B2):
  /// returns the current catalog when it is live and no older than
  /// [maxAge], otherwise forces one refresh and returns whatever catalog
  /// stands after it. The caller still checks
  /// [OrchestraRoutesCatalog.availability]; a failed refresh leaves the
  /// route stale.
  Future<OrchestraRoutesCatalog> refreshIfOlderThan(
    Duration maxAge, {
    DateTime Function() clock = DateTime.now,
  }) async {
    if (state.isFresh(clock(), maxAge: maxAge)) return state;
    await refresh();
    return state;
  }

  void _installLegacyTables(OrchestraRoutesCatalog catalog) {
    // Decimals bridge first — even a catalog whose derived route tables
    // clip to empty still carries authoritative per-asset decimals.
    setOrchestraDecimalsCatalog(catalog);
    if (!catalog.hasLiveData) return;
    final send = catalog.sendRouteTable;
    final receive = catalog.receiveRouteTable;
    // The dollar-anchored receive table: which assets can be received
    // INTO the dollar balance, bitcoin included. It has no static
    // fallback, so it only ever reaches the helpers from here.
    final usdReceive = catalog.usdReceiveRouteTable;
    setLiveOrchestraRouteCatalog(OrchestraRouteCatalog(
      send: send,
      receive: receive,
      usdReceive: usdReceive,
      receiveExact:
          catalog.exactAccumulationRouteTable(destinationAsset: 'BTC'),
      usdReceiveExact:
          catalog.exactAccumulationRouteTable(destinationAsset: 'USDB'),
    ));
  }

  Future<void> _persist(Map<String, dynamic> json, DateTime fetchedAt) async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_jsonKey, jsonEncode(json));
      await box.put(_fetchedAtKey, fetchedAt.millisecondsSinceEpoch);
    } catch (_) {
      // Persistence is best-effort; the in-memory catalog stands.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// App-wide supported-routes catalog. Never loading/error — the state
/// is always a usable catalog (live > cached > static). Watch it in
/// offering surfaces so grids re-filter when the live set lands.
final orchestraSupportedRoutesProvider = StateNotifierProvider<
    OrchestraSupportedRoutesNotifier, OrchestraRoutesCatalog>((ref) {
  final notifier = OrchestraSupportedRoutesNotifier();
  // Fire-and-forget: the static catalog serves until Hive/network land.
  // ignore: unawaited_futures
  notifier.init();
  return notifier;
});

/// Completes when the first catalog load has finished, successfully or
/// not. Until then the state above is still the static fallback and a
/// surface that reads the offering is LOADING, not empty: telling
/// someone there is nothing to receive in that window is simply wrong,
/// and indistinguishable from a real failure. Watch this beside the
/// catalog and show a loading line while it is loading.
final orchestraRoutesReadyProvider = FutureProvider<void>((ref) {
  return ref.read(orchestraSupportedRoutesProvider.notifier).init();
});

/// Live, reactive equivalent of `orchestraSupportsSwapAsset(code)`.
/// Asset grids, destination pickers and search results should filter
/// through this (instead of the module-level function) once their
/// owners wire it, so a route Flashnet adds or drops shows up without
/// an app release.
final orchestraSupportsSwapAssetLiveProvider =
    Provider.family<bool, String>((ref, assetCode) {
  return ref
      .watch(orchestraSupportedRoutesProvider)
      .supportsSwapAsset(assetCode);
});
