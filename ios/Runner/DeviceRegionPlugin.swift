import Flutter
import Foundation

/// Bridges the Dart `kute/device_region` MethodChannel
/// (`lib/services/device_currency.dart`): the country set under Settings >
/// General > Language & Region, which a new install's currency follows.
/// Flutter's locales and Dart's `Platform.localeName` come from the language
/// list alone, so English (US) on an iPhone set to Germany reads "en_US"
/// there and Germany only here. Null when the system has no region.
final class DeviceRegionPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kute/device_region", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(DeviceRegionPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "region" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result((Locale.current as NSLocale).countryCode)
  }
}
