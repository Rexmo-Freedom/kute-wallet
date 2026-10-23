import 'dart:convert';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/orchestra/receive_route_availability.dart'
    show ReceiveRouteAvailability;

/// The legacy Orchestra accumulation addresses this device handed out
/// before the receive screens moved to standing deposit addresses.
///
/// Read-only: the app never creates, reuses or shows one any more (no
/// deposit to one ever completed, and the provider calls the model
/// legacy). What stays is the silent watch: an address already given out
/// may still take a late deposit, and the order it spawns must still get
/// its Activity row, so background sync's sweep reads [sweepTargets]
/// (background_sync_provider.dart). The address itself never reaches a
/// screen, a QR, a copy or a share.
class AccumulationAddressCache {
  static const _boxName = 'accumulation_addresses';

  /// Every stored accumulation address with a usable deposit address,
  /// including the ones an older build moved under its `retired:` prefix
  /// (a late deposit may land on any of them). Corrupt entries are
  /// skipped.
  static List<OrchestraAccumulationAddress> getAll() {
    // Box opens at startup (hive_boot.dart); the guard covers early callers
    // racing startup — returning empty just delays the sweep one tick.
    if (!Hive.isBoxOpen(_boxName)) return const [];
    final box = Hive.box<String>(_boxName);
    final out = <OrchestraAccumulationAddress>[];
    for (final raw in box.values) {
      try {
        final addr = OrchestraAccumulationAddress.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        if (addr.depositAddress != null && addr.depositAddress!.isNotEmpty) {
          out.add(addr);
        }
      } catch (_) {
        // Corrupt cache entry — skip
      }
    }
    return out;
  }

  /// The entries background sync's off-screen sweep watches: [getAll]
  /// minus any HyperCore-source entry. Flashnet cannot verify a HyperCore
  /// deposit independently ("existing addresses require reconciliation"),
  /// so polling history for one can never credit it; the app never minted
  /// one, and a stray entry is left to the provider's reconciliation
  /// rather than queried every tick.
  static List<OrchestraAccumulationAddress> sweepTargets() => getAll()
      .where((a) => !ReceiveRouteAvailability.isHyperCoreSource(a.sourceChain))
      .toList();

  /// Opens the box if nothing has yet (tests). At startup
  /// `openStartupHiveBoxes` (lib/services/hive_boot.dart) has already
  /// opened it; the open is then a no-op.
  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
  }
}
