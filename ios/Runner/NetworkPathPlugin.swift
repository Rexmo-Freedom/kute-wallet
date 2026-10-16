import Flutter
import Network

/// Bridges the Dart `kute/network_path` EventChannel
/// (`lib/services/network_change_signal.dart`): one `"changed"` event each
/// time the phone's network path changes, so the app asks every region
/// answer again (Polymarket's geoblock, Hyperliquid's legal check, Kute's
/// policy) instead of keeping the one it got on the old network.
///
///   * `NWPathMonitor` (all interface types) watches the path. A VPN coming
///     up or going down adds or drops its virtual interface (`.other`,
///     "virtual networks or networks of unknown types") from the path's
///     interfaces, so a VPN toggle is a path change like Wi-Fi to cellular;
///   * the first update after start is the baseline, not a change;
///   * updates that leave the path's shape alone (status, interfaces,
///     expensive / constrained, gateway count) are dropped here, so Dart
///     only hears real changes. Dart debounces what is left;
///   * the event carries no detail: no interface names, no addresses.
///
/// Nothing here throws. The monitor runs only while Dart listens (the
/// stream's listen / cancel), on its own serial queue; events are sent on
/// the main thread, as Flutter requires.
final class NetworkPathPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "kute/network_path", binaryMessenger: registrar.messenger())
    channel.setStreamHandler(NetworkPathPlugin())
  }

  private let queue = DispatchQueue(label: "com.kutewallet.network_path")
  private var monitor: NWPathMonitor?
  private var sink: FlutterEventSink?
  /// Read and written on [queue] only.
  private var lastSignature: String?

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    stopMonitor()
    sink = events
    queue.async { [weak self] in self?.lastSignature = nil }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in self?.pathChanged(path) }
    self.monitor = monitor
    monitor.start(queue: queue)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopMonitor()
    sink = nil
    return nil
  }

  private func stopMonitor() {
    monitor?.pathUpdateHandler = nil
    monitor?.cancel()
    monitor = nil
  }

  /// On [queue].
  private func pathChanged(_ path: NWPath) {
    let signature = Self.signature(of: path)
    guard let previous = lastSignature else {
      lastSignature = signature
      return
    }
    guard previous != signature else { return }
    lastSignature = signature
    DispatchQueue.main.async { [weak self] in self?.sink?("changed") }
  }

  /// The parts of a path a VPN, a Wi-Fi join or a SIM swap changes. Kept
  /// on the device; only the fact that it changed reaches Dart.
  private static func signature(of path: NWPath) -> String {
    let interfaces = path.availableInterfaces
      .map { "\($0.name):\($0.type)" }
      .joined(separator: ",")
    return [
      "\(path.status)",
      interfaces,
      "\(path.isExpensive)",
      "\(path.isConstrained)",
      "\(path.gateways.count)",
    ].joined(separator: "|")
  }
}
