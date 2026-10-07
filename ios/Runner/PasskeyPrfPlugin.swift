import AuthenticationServices
import CryptoKit
import Flutter
import Security
import UIKit

/// Bridges the Dart `com.kutewallet.app/passkey_prf` MethodChannel to
/// iOS's `ASAuthorizationPlatformPublicKeyCredentialProvider` with the
/// WebAuthn PRF extension.
///
/// Implements three methods called by `lib/services/passkey_prf_service.dart`:
///   * `registerCredential(rpId, rpName, userName, userDisplayName)` —
///     creates a fresh platform passkey for the relying party and
///     records that it supports PRF.
///   * `isPrfAvailable(rpId)` — currently a coarse signal: returns
///     true on iOS 18.4+, false otherwise. The OS doesn't expose a
///     direct "does this credential have PRF" query before the
///     ceremony.
///   * `derivePrfSeed(salt, rpId)` — performs a no-UI-overhead
///     assertion ceremony that returns the 32-byte PRF output for
///     the supplied salt. The Breez SDK calls this on every wallet
///     connect to re-derive the seed.
///
/// Min iOS for PRF: 18.4. Apple confirmed in Developer Forums thread
/// 764730 that iOS 18.0–18.3 has a bug where cross-device PRF
/// outputs differ from local platform auth on the same credential,
/// which would silently produce a different wallet seed on restore.
/// We gate below 18.4 so the Dart side falls back to BIP39.
///
/// Relying-party association: the host `keys.breez.technology` must
/// list our team-id+bundle-id in its `apple-app-site-association`
/// `webcredentials.apps` array. The OS validates association at
/// ceremony time, including the app's signing team.
class PasskeyPrfPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.kutewallet.app/passkey_prf"

    private let channel: FlutterMethodChannel
    /// Active controllers retained while the OS UI is on screen.
    /// `ASAuthorizationController.delegate` and
    /// `presentationContextProvider` are `weak`, so without holding
    /// the controller AND its delegate-wrapper somewhere strong the
    /// callbacks never fire and the ceremony silently times out.
    private var activeControllers: [ObjectIdentifier: PasskeyPrfDelegate] = [:]
    /// Strong ref so the plugin lives for the engine's lifetime even
    /// after `register(with:)` returns. The registrar's
    /// `publish(_:)` API holds this for us, but we keep an explicit
    /// static reference as belt-and-braces.
    private static var instance: PasskeyPrfPlugin?

    /// A failed CSPRNG call must never produce an all-zero or partial
    /// challenge/user identifier. The injected generator exercises that
    /// failure path without changing the production randomness source.
    static func ceremonyRandomBytes(
        generator: (Int, UnsafeMutableRawPointer) -> Int32 = {
            SecRandomCopyBytes(kSecRandomDefault, $0, $1)
        }
    ) -> Data? {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            generator(buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { return nil }
        return bytes
    }

    static func authorizationError(_ error: Error) -> FlutterError {
        let isCancelled = (error as? ASAuthorizationError)?.code == .canceled
        return FlutterError(
            code: isCancelled ? "USER_CANCELLED" : "PRF_ERROR",
            message: isCancelled ? "User cancelled" : error.localizedDescription,
            details: nil
        )
    }

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    /// Standard `FlutterPlugin` registration entry point. Replaces
    /// the older "grab rootViewController from AppDelegate" approach
    /// — that path triggers a deprecation warning under the
    /// UISceneDelegate migration because `rootViewController` isn't
    /// set yet inside `application:didFinishLaunchingWithOptions:`.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let plugin = PasskeyPrfPlugin(channel: channel)
        instance = plugin
        registrar.addMethodCallDelegate(plugin, channel: channel)
        registrar.publish(plugin)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        handle(call: call, result: result)
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isPrfAvailable":
            // Coarse OS-version gate. The 18.0 → 18.3 PRF bug
            // (Developer Forums 764730) makes cross-device restore
            // unsound, so report unsupported on those versions.
            if #available(iOS 18.4, *) {
                result(true)
            } else {
                result(false)
            }
        case "registerCredential":
            guard #available(iOS 18.4, *) else {
                result(FlutterError(
                    code: "PRF_UNAVAILABLE",
                    message: "Passkey registration requires iOS 18.4 or newer",
                    details: nil
                ))
                return
            }
            guard let args = call.arguments as? [String: Any],
                  let rpId = args["rpId"] as? String else {
                result(FlutterError(
                    code: "BAD_ARGS",
                    message: "Missing rpId",
                    details: nil
                ))
                return
            }
            let userName = (args["userName"] as? String) ?? "kute-wallet-user"
            startRegistration(
                rpId: rpId,
                userName: userName,
                result: result
            )
        case "derivePrfSeed":
            guard #available(iOS 18.4, *) else {
                result(FlutterError(
                    code: "PRF_UNAVAILABLE",
                    message: "Passkey PRF requires iOS 18.4 or newer",
                    details: nil
                ))
                return
            }
            guard let args = call.arguments as? [String: Any],
                  let rpId = args["rpId"] as? String,
                  let saltString = args["salt"] as? String else {
                result(FlutterError(
                    code: "BAD_ARGS",
                    message: "Missing rpId or salt",
                    details: nil
                ))
                return
            }
            // Optional allow-list — when the caller knows which
            // credential to assert against (we recorded it at
            // registration), pass it through so the OS skips the
            // account-picker sheet and runs the ceremony directly
            // on that credential.
            let credentialIds: [Data] =
                (args["credentialIds"] as? [FlutterStandardTypedData])?
                    .map { $0.data } ?? []
            startAssertion(
                rpId: rpId,
                saltString: saltString,
                credentialIds: credentialIds,
                result: result
            )
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 18.4, *)
    private func startRegistration(
        rpId: String,
        userName: String,
        result: @escaping FlutterResult
    ) {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpId
        )
        // User-id can be anything stable per-user, per-RP. The Breez
        // SDK doesn't read it back, so a per-install random is fine
        // — the credential ID returned by the OS is what links the
        // passkey to assertions later.
        guard let challenge = Self.ceremonyRandomBytes(),
              let userId = Self.ceremonyRandomBytes() else {
            result(FlutterError(
                code: "PRF_ERROR",
                message: "Secure random generation failed",
                details: nil
            ))
            return
        }
        let req = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: userName,
            userID: userId
        )
        req.userVerificationPreference = .required
        // Mark the credential as PRF-capable. We don't pass salt
        // values at registration; assertions provide them.
        req.prf = ASAuthorizationPublicKeyCredentialPRFRegistrationInput.checkForSupport

        runController(requests: [req], onResult: { authorization in
            guard let reg = authorization.credential as?
                    ASAuthorizationPlatformPublicKeyCredentialRegistration else {
                result(FlutterError(
                    code: "PRF_ERROR",
                    message: "Unexpected credential type",
                    details: nil
                ))
                return
            }
            // Return the freshly-minted credentialID so the Dart
            // side can persist it and pin future assertions to this
            // specific credential — without that, the next sign-in
            // shows the account-picker sheet.
            result(FlutterStandardTypedData(bytes: reg.credentialID))
        }, onError: { err in
            result(Self.authorizationError(err))
        })
    }

    @available(iOS 18.4, *)
    private func startAssertion(
        rpId: String,
        saltString: String,
        credentialIds: [Data],
        result: @escaping FlutterResult
    ) {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpId
        )
        guard let challenge = Self.ceremonyRandomBytes() else {
            result(FlutterError(
                code: "PRF_ERROR",
                message: "Secure random generation failed",
                details: nil
            ))
            return
        }
        let req = provider.createCredentialAssertionRequest(challenge: challenge)
        req.userVerificationPreference = .required
        if !credentialIds.isEmpty {
            // Pinning the allowed credential makes the OS bypass the
            // picker sheet — it goes straight to the biometric
            // ceremony for this credential, which is the right UX
            // when we already know which passkey to use.
            req.allowedCredentials = credentialIds.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(
                    credentialID: $0
                )
            }
        }
        // Salt encoding: raw UTF-8 of the Dart-side string. iOS / the
        // authenticator internally apply `"WebAuthn PRF" || 0x00 ||
        // salt` before HMAC-SHA256, matching the WebAuthn spec — do
        // NOT pre-hash here or our seed won't match the web/Android
        // siblings on the same passkey.
        guard let salt = saltString.data(using: .utf8) else {
            result(FlutterError(
                code: "BAD_ARGS",
                message: "salt is not valid UTF-8",
                details: nil
            ))
            return
        }
        let inputs = ASAuthorizationPublicKeyCredentialPRFAssertionInput.InputValues(
            saltInput1: salt
        )
        req.prf = ASAuthorizationPublicKeyCredentialPRFAssertionInput.inputValues(inputs)

        runController(requests: [req], onResult: { authorization in
            guard let assertion = authorization.credential as?
                    ASAuthorizationPlatformPublicKeyCredentialAssertion else {
                result(FlutterError(
                    code: "PRF_ERROR",
                    message: "Unexpected credential type",
                    details: nil
                ))
                return
            }
            // `assertion.prf` is optional (nil when the credential
            // wasn't created with PRF support); `.first` is a
            // non-optional `SymmetricKey` in the iOS 18.4 SDK, so
            // we only `guard let` the outer PRF object.
            guard let prf = assertion.prf else {
                result(FlutterError(
                    code: "PRF_UNAVAILABLE",
                    message: "Credential did not return PRF output",
                    details: nil
                ))
                return
            }
            let first = prf.first
            let bytes = first.withUnsafeBytes { Data($0) }
            if bytes.count != 32 {
                result(FlutterError(
                    code: "PRF_ERROR",
                    message: "PRF output length \(bytes.count) bytes, expected 32",
                    details: nil
                ))
                return
            }
            // Return both the PRF bytes and the credentialID the OS
            // resolved against — Dart persists the credentialID on
            // first sight so subsequent assertions can pin to it and
            // skip the account picker. Recover-flow users get the
            // picker once at restore time and never again.
            result([
                "prf": FlutterStandardTypedData(bytes: bytes),
                "credentialId":
                    FlutterStandardTypedData(bytes: assertion.credentialID),
            ])
        }, onError: { err in
            result(Self.authorizationError(err))
        })
    }

    private func runController(
        requests: [ASAuthorizationRequest],
        onResult: @escaping (ASAuthorization) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        let controller = ASAuthorizationController(authorizationRequests: requests)
        let delegate = PasskeyPrfDelegate(
            onResult: { [weak self] auth in
                onResult(auth)
                self?.releaseController(for: controller)
            },
            onError: { [weak self] err in
                onError(err)
                self?.releaseController(for: controller)
            }
        )
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        activeControllers[ObjectIdentifier(controller)] = delegate
        controller.performRequests()
    }

    private func releaseController(for controller: ASAuthorizationController) {
        activeControllers.removeValue(forKey: ObjectIdentifier(controller))
    }
}

/// Strong holder for ASAuthorizationController's weak delegate +
/// presentation context. Without this the OS prompt fires once, the
/// delegate is deallocated, and the callback never reaches Dart.
private final class PasskeyPrfDelegate: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private let onResult: (ASAuthorization) -> Void
    private let onError: (Error) -> Void

    init(
        onResult: @escaping (ASAuthorization) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onResult = onResult
        self.onError = onError
        super.init()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        onResult(authorization)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        onError(error)
    }

    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        // Fall back to whatever window the app currently shows.
        // UIApplication.shared.connectedScenes is the iOS 13+ path;
        // we filter to foreground-active scenes to dodge background
        // window-scenes that produce a black ASAuthorization sheet.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        if let window = scenes.first?.windows.first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first {
            return window
        }
        // Last resort — should never happen on iPhone in foreground.
        return ASPresentationAnchor()
    }
}
