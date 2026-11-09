import Flutter
import UIKit

/// Bridges the Dart `kute/background_grace` MethodChannel
/// (`lib/services/platform/background_grace.dart`): a short stay of
/// execution for a bet or trade still being placed when the person leaves
/// the app.
///
/// `hold(id, reason)` begins one `UIApplication.beginBackgroundTask` per
/// Dart token, while the app is still in the foreground (Apple's advice:
/// begin before the transition, not in it). iOS grants roughly 30 seconds
/// after the app leaves the screen, then runs the expiration handler: the
/// task is ended there, as iOS requires, and Dart is told (`expired`, id)
/// so the token is dead on its side too. `release(id)` ends the task
/// early. Ending an unknown or already-ended id does nothing, so a Dart
/// release that races an expiry is harmless.
///
/// What this cannot do: nothing runs after iOS suspends the app. An order
/// that outlives the window sits where it was until the app comes back;
/// the Dart binder then holds a new task for the next trip out.
final class BackgroundGracePlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var tasks: [Int: UIBackgroundTaskIdentifier] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kute/background_grace", binaryMessenger: registrar.messenger())
    let plugin = BackgroundGracePlugin()
    plugin.channel = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "hold":
      guard let id = args?["id"] as? Int else {
        result(FlutterError(code: "BAD_ARGS", message: "hold needs an id", details: nil))
        return
      }
      let reason = (args?["reason"] as? String) ?? "order"
      hold(id: id, reason: reason)
      result(true)
    case "release":
      guard let id = args?["id"] as? Int else {
        result(FlutterError(code: "BAD_ARGS", message: "release needs an id", details: nil))
        return
      }
      release(id: id)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func hold(id: Int, reason: String) {
    // The same id twice replaces the first task.
    release(id: id)
    var identifier = UIBackgroundTaskIdentifier.invalid
    identifier = UIApplication.shared.beginBackgroundTask(
      withName: "kute.grace.\(reason)"
    ) { [weak self] in
      // iOS is about to suspend the app: end the task first (mandatory),
      // then tell Dart the token is gone. Runs on the main thread.
      self?.expire(id: id)
    }
    if identifier == .invalid {
      // Background execution refused (Low Power Mode, or the system said
      // no): Dart hears it at once and the order simply has no window.
      channel?.invokeMethod("expired", arguments: ["id": id])
      return
    }
    tasks[id] = identifier
  }

  private func release(id: Int) {
    guard let identifier = tasks.removeValue(forKey: id) else { return }
    UIApplication.shared.endBackgroundTask(identifier)
  }

  private func expire(id: Int) {
    release(id: id)
    channel?.invokeMethod("expired", arguments: ["id": id])
  }
}
