import 'package:ledger_flutter_plus/ledger_flutter_plus.dart'
    show LedgerDeviceType;

/// Discovers models recognized by the upstream SDK. Names can make a device a
/// scan candidate, but only a matching GATT service selects its transport.
abstract final class LedgerDeviceDiscovery {
  static final Map<String, LedgerDeviceType> _modelsByService =
      Map.unmodifiable({
    for (final model in LedgerDeviceType.ble)
      if (model.serviceId.isNotEmpty) model.serviceId.toLowerCase(): model,
  });

  static final List<String> serviceUuids =
      List.unmodifiable(_modelsByService.keys);

  static LedgerDeviceType? modelForServices(Iterable<String> services) {
    for (final service in services) {
      final model = _modelsByService[service.trim().toLowerCase()];
      if (model != null) return model;
    }
    return null;
  }

  /// Paired devices and name-only advertisements may not have connected yet.
  /// Discover GATT services only after the platform confirms the connection.
  static Future<LedgerDeviceType?> detectConnectedModel({
    required Future<void> Function() connect,
    required Future<Iterable<String>> Function() discoverServices,
  }) async {
    await connect();
    return modelForServices(await discoverServices());
  }

  static bool isCandidate(
      {required String? name, required Iterable<String> services}) {
    if (modelForServices(services) != null) return true;
    final normalizedName = name?.trim().toLowerCase() ?? '';
    return const ['ledger', 'nano', 'stax', 'flex']
        .any(normalizedName.startsWith);
  }
}
