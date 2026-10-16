import CryptoKit
import Flutter
import Foundation
import LocalAuthentication
import Security
import UIKit
import UniformTypeIdentifiers

/// Bridges the Dart `com.kutewallet.app/security` MethodChannel
/// (`lib/services/secure/keychain_local.dart`,
/// `lib/helpers/secure_screen.dart`, `lib/helpers/seed_clipboard.dart`).
///
/// Keychain methods called by `KeychainLocal`:
///   * `writeLocalOnly(service, account, value)` — `SecItemUpdate` on the
///     non-synchronizable item, then `SecItemAdd` with
///     `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` when none exists.
///   * `deleteLocalOnly(service, account)` and
///     `deleteAllLocalOnly(service)` — `SecItemDelete` on
///     non-synchronizable items only.
///
/// Every query carries `kSecAttrSynchronizable: false`. The
/// flutter_secure_storage Darwin plugin deletes both variants of a key and
/// deletes a synced twin before writing a local item, which would purge
/// iCloud Keychain residue that other devices may still depend on. These
/// methods never delete or overwrite a synchronizable item.
///
/// Read-only rescue lookups called by `LegacyKeychainLookup`
/// (`lib/services/secure/legacy_keychain_rescue.dart`):
///   * `readLegacyItem(service, account, synchronizable)` —
///     `SecItemCopyMatching` for the one generic-password item with that
///     service and account, with NO `kSecAttrAccessible` in the query.
///     Items written by 1.x builds between 2026-03 and 2026-06 carry
///     `AfterFirstUnlock` (not `...ThisDeviceOnly`); the flutter_secure_storage
///     Darwin plugin puts the configured accessibility into every read
///     query, so those items read as absent there. Returns the UTF-8 value
///     or nil when there is none.
///   * `listLegacyAccounts(service, prefix, synchronizable)` — attributes
///     only (`kSecReturnAttributes`, never `kSecReturnData`): the account
///     names under that service that start with `prefix`.
/// Neither method writes, updates or deletes anything.
///
/// Capture protection methods called by `SecureScreenController`:
///   * `setSecureScreen(enabled)` — starts or stops observing
///     `UIScreen.capturedDidChangeNotification` and
///     `UIApplication.userDidTakeScreenshotNotification`, reported to Dart
///     as `captureChanged(bool)` and `screenshotTaken()`. Dart enables it
///     only while a recovery phrase surface is mounted.
///   * `isCaptured()` — `UIScreen.main.isCaptured` (recording or mirroring).
///   * `pasteboardChangeCount()` — `UIPasteboard.general.changeCount`, so
///     the recovery phrase clipboard clear never reads another app's copy
///     (which would show the iOS paste prompt).
///   * `copySensitive(text, expirySeconds)` — writes a recovery phrase or
///     private key with `UIPasteboard.setItems` and `.localOnly` (never
///     synced to other devices over Universal Clipboard) plus an
///     `.expirationDate` (default 60 s) after which iOS removes it itself.
///     Dart falls back to a plain copy if this fails.
///
/// App-switcher privacy cover methods called by `PrivacyCoverBridge`
/// (`lib/helpers/privacy_cover_bridge.dart`), read by the cover in
/// `AppDelegate`:
///   * `setPrivacyCoverStyle(background, dark)` — the app's own
///     background colour for the theme it is currently showing.
///     `UIColor.systemBackground` follows the DEVICE appearance, so a
///     charcoal Kute on a light-mode phone covered itself in white.
///   * `setBiometricPromptActive(active)` — true while Kute itself has a
///     system biometric sheet on screen. That sheet resigns the scene
///     active exactly as the app switcher does, and the cover used to go
///     up over the user's own screen for the whole scan.
///
/// Step-up (Phase 1b, D-14), called by `BiometryDomainState`:
///   * `biometryDomainStateHash()` — SHA-256 lowercase hex of
///     `LAContext.evaluatedPolicyDomainState` after
///     `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`, or nil
///     when biometry is unavailable. The value changes when a face or finger
///     is added or removed. No prompt is shown.
class SecurityNativePlugin: NSObject, FlutterPlugin {
    static let channelName = "com.kutewallet.app/security"

    /// Strong ref so the plugin lives for the engine's lifetime, as in
    /// `PasskeyPrfPlugin`.
    private static var instance: SecurityNativePlugin?

    private var channel: FlutterMethodChannel?
    private var captureObservers: [NSObjectProtocol] = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let plugin = SecurityNativePlugin()
        plugin.channel = channel
        instance = plugin
        registrar.addMethodCallDelegate(plugin, channel: channel)
        registrar.publish(plugin)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "writeLocalOnly":
            guard let service = args["service"] as? String,
                  let account = args["account"] as? String,
                  let value = args["value"] as? String else {
                result(FlutterError(
                    code: "BAD_ARGS",
                    message: "writeLocalOnly requires service, account and value",
                    details: nil
                ))
                return
            }
            respond(writeLocalOnly(service: service, account: account, value: value), result)
        case "deleteLocalOnly":
            guard let service = args["service"] as? String,
                  let account = args["account"] as? String else {
                result(FlutterError(
                    code: "BAD_ARGS",
                    message: "deleteLocalOnly requires service and account",
                    details: nil
                ))
                return
            }
            respond(deleteLocalOnly(service: service, account: account), result)
        case "deleteAllLocalOnly":
            guard let service = args["service"] as? String else {
                result(FlutterError(
                    code: "BAD_ARGS",
                    message: "deleteAllLocalOnly requires service",
                    details: nil
                ))
                return
            }
            respond(deleteLocalOnly(service: service, account: nil), result)
        case "readLegacyItem":
            guard let service = args["service"] as? String,
                  let account = args["account"] as? String else {
                result(FlutterError(
                    code: "BAD_ARGS",
                    message: "readLegacyItem requires service and account",
                    details: nil
                ))
                return
            }
            let synchronizable = (args["synchronizable"] as? Bool) ?? false
            switch readLegacyItem(service: service, account: account, synchronizable: synchronizable) {
            case .success(let value):
                result(value)
            case .failure(let error):
                respond(error.status, result)
            }
        case "listLegacyAccounts":
            guard let service = args["service"] as? String else {
                result(FlutterError(
                    code: "BAD_ARGS",
                    message: "listLegacyAccounts requires service",
                    details: nil
                ))
                return
            }
            let prefix = (args["prefix"] as? String) ?? ""
            let synchronizable = (args["synchronizable"] as? Bool) ?? false
            switch listLegacyAccounts(service: service, prefix: prefix, synchronizable: synchronizable) {
            case .success(let accounts):
                result(accounts)
            case .failure(let error):
                respond(error.status, result)
            }
        case "setSecureScreen":
            setCaptureMonitoring((args["enabled"] as? Bool) ?? false)
            result(nil)
        case "isCaptured":
            result(UIScreen.main.isCaptured)
        case "pasteboardChangeCount":
            result(UIPasteboard.general.changeCount)
        case "copySensitive":
            guard let text = args["text"] as? String else {
                result(FlutterError(
                    code: "BAD_ARGS",
                    message: "copySensitive requires text",
                    details: nil
                ))
                return
            }
            let seconds = (args["expirySeconds"] as? NSNumber)?.doubleValue ?? 60
            UIPasteboard.general.setItems(
                [[UTType.plainText.identifier: text]],
                options: [
                    .localOnly: true,
                    .expirationDate: Date().addingTimeInterval(max(1, seconds)),
                ]
            )
            result(nil)
        case "setPrivacyCoverStyle":
            if let argb = args["background"] as? NSNumber {
                PrivacyCoverState.background = UIColor(argb: argb.uint32Value)
            }
            PrivacyCoverState.isDark = (args["dark"] as? Bool) ?? false
            result(nil)
        case "setBiometricPromptActive":
            PrivacyCoverState.biometricPromptActive =
                (args["active"] as? Bool) ?? false
            result(nil)
        case "biometryDomainStateHash":
            result(biometryDomainStateHash())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func biometryDomainStateHash() -> String? {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              let state = context.evaluatedPolicyDomainState else {
            return nil
        }
        return SHA256.hash(data: state).map { String(format: "%02x", $0) }.joined()
    }

    private func setCaptureMonitoring(_ enabled: Bool) {
        let center = NotificationCenter.default
        guard enabled else {
            captureObservers.forEach { center.removeObserver($0) }
            captureObservers.removeAll()
            return
        }
        guard captureObservers.isEmpty else { return }
        captureObservers.append(center.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.channel?.invokeMethod("captureChanged", arguments: UIScreen.main.isCaptured)
        })
        captureObservers.append(center.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.channel?.invokeMethod("screenshotTaken", arguments: nil)
        })
    }

    private func localQuery(service: String, account: String?) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: false,
        ]
        if let account = account {
            query[kSecAttrAccount] = account
        }
        return query
    }

    private func writeLocalOnly(service: String, account: String, value: String) -> OSStatus {
        let data = Data(value.utf8)
        let query = localQuery(service: service, account: account)
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var add = query
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }

    private func deleteLocalOnly(service: String, account: String?) -> OSStatus {
        let status = SecItemDelete(localQuery(service: service, account: account) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }

    /// The one item for `service` + `account`, whatever accessibility it was
    /// stored with. `nil` when there is none. Never mutates.
    private func readLegacyItem(
        service: String, account: String, synchronizable: Bool
    ) -> Result<String?, KeychainStatusError> {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .success(nil) }
        guard status == errSecSuccess else { return .failure(KeychainStatusError(status: status)) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return .failure(KeychainStatusError(status: errSecDecode))
        }
        return .success(value)
    }

    /// Account names under `service` starting with `prefix`. Attributes
    /// only: no item data is read. Never mutates.
    private func listLegacyAccounts(
        service: String, prefix: String, synchronizable: Bool
    ) -> Result<[String], KeychainStatusError> {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: synchronizable,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return .success([]) }
        guard status == errSecSuccess else { return .failure(KeychainStatusError(status: status)) }
        let attributes = items as? [[CFString: Any]] ?? []
        let accounts = attributes
            .compactMap { $0[kSecAttrAccount] as? String }
            .filter { $0.hasPrefix(prefix) }
        return .success(accounts)
    }

    /// A Keychain call that did not succeed, for `Result` plumbing.
    private struct KeychainStatusError: Error {
        let status: OSStatus
    }

    /// Mirrors flutter_secure_storage's error shape: OSStatus in `details`.
    private func respond(_ status: OSStatus, _ result: FlutterResult) {
        if status == errSecSuccess {
            result(nil)
            return
        }
        let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
        result(FlutterError(
            code: "Unexpected security result code",
            message: message,
            details: status
        ))
    }
}

// Not private: `PrivacyCoverState` in AppDelegate.swift persists the
// cover colour across launches and needs both directions.
extension UIColor {
    /// Packed 0xAARRGGBB, the shape Dart's `Color.toARGB32()` produces.
    convenience init(argb: UInt32) {
        self.init(
            red: CGFloat((argb >> 16) & 0xFF) / 255.0,
            green: CGFloat((argb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(argb & 0xFF) / 255.0,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255.0
        )
    }

    /// The same packing, back out again, so the colour can be stored.
    /// Resolved against no trait collection because the values that
    /// reach here are literal Kute theme colours, never dynamic ones.
    var argb: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
        func byte(_ v: CGFloat) -> UInt32 {
            UInt32((v * 255.0).rounded().clamped(to: 0...255))
        }
        return (byte(a) << 24) | (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
