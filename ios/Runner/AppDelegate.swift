import UIKit
import Flutter
import Firebase
import appsflyer_sdk
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    FirebaseApp.configure() // <-- Initialize Firebase

    // This is required to make any communication available in the background isolate.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }

    // This is required to handle silent push notifications.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    observeSceneActivation()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // UIScene lifecycle (required on iOS 27). The Flutter engine is created by
  // the scene, so plugins register here, through the implicit engine's
  // registry, instead of in `didFinishLaunchingWithOptions`.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)

    if let registrar = registry.registrar(forPlugin: "NativeBdkPlugin") {
      NativeBdkPlugin.register(with: registrar)
    }

    // Wire the Dart-side passkey-PRF MethodChannel into native iOS
    // ASAuthorization APIs. Breez SDK requires a host-side PRF
    // implementation for passkey wallets; without this every Dart
    // call to PasskeyPrfService throws MissingPluginException and
    // the wallet falls back to BIP39.
    if let registrar = registry.registrar(forPlugin: "PasskeyPrfPlugin") {
      PasskeyPrfPlugin.register(with: registrar)
    }

    // Local-only Keychain writes and deletes for seed and PIN material
    // (`com.kutewallet.app/security`), so synced iCloud Keychain items are
    // never purged.
    if let registrar = registry.registrar(forPlugin: "SecurityNativePlugin") {
      SecurityNativePlugin.register(with: registrar)
    }
  }

  // THIS IS THE CRUCIAL FUNCTION FOR BACKGROUND NOTIFICATIONS
  // It's called by iOS when a remote notification arrives, allowing background processing.
  override func application(_ application: UIApplication,
  didReceiveRemoteNotification userInfo: [AnyHashable : Any],
  fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

    // This line hands the notification payload to the Firebase SDK,
    // which then triggers your Dart background handler.
    Messaging.messaging().appDidReceiveMessage(userInfo)

    // We must call the completion handler to tell iOS our background task is complete.
    completionHandler(.newData)
  }

  // ── App-switcher privacy cover ────────────────────────────────────
  // iOS snapshots the window the moment the scene resigns active; the
  // Flutter-side cover (appVisibleProvider) can miss that snapshot if
  // no frame is pumped between `inactive` and suspension. This native
  // cover is the belt-and-suspenders: an opaque view added when the scene
  // deactivates and removed when it activates, so balances are never
  // readable in the app switcher. Under the UIScene lifecycle the app
  // delegate has no window and gets no active/inactive callbacks, so the
  // cover follows the scene notifications and the scene's own window.
  //
  // Two things it used to get wrong. It painted `UIColor.systemBackground`,
  // which follows the DEVICE appearance, so a charcoal Kute on a
  // light-mode phone covered itself in white; Dart now hands it the
  // app's own background through `setPrivacyCoverStyle`. And it asked
  // for `UIImage(named: "AppIcon")`, which never resolves (an app icon
  // set is not a loadable image), so the cover was a bare rectangle;
  // it now uses the LaunchImage mark, which has both appearances.
  private let privacyCoverTag = 0x4B555445 // "KUTE"

  private func observeSceneActivation() {
    let center = NotificationCenter.default
    center.addObserver(
      forName: UIScene.willDeactivateNotification, object: nil, queue: .main
    ) { [weak self] note in
      // Face ID resigns the scene active exactly as the app switcher
      // does, so this alone covered the user's screen for the whole
      // scan. A prompt Kute itself opened sits this edge out; see
      // `lib/helpers/privacy_cover_bridge.dart`.
      self?.addPrivacyCover(to: note.object as? UIWindowScene)
    }
    center.addObserver(
      forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] note in
      // Leaving for real. iOS takes the switcher snapshot after this
      // returns and a biometric prompt never reaches it, so the cover
      // goes up here whatever Dart last said — a Dart side that died
      // mid-prompt can never leave the snapshot uncovered.
      self?.addPrivacyCover(to: note.object as? UIWindowScene, force: true)
    }
    center.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { [weak self] note in
      self?.removePrivacyCover(from: note.object as? UIWindowScene)
    }
  }

  private func sceneWindow(_ scene: UIWindowScene?) -> UIWindow? {
    guard let scene = scene else { return nil }
    return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
  }

  private func addPrivacyCover(to scene: UIWindowScene?, force: Bool = false) {
    guard force || !PrivacyCoverState.biometricPromptActive else { return }
    guard let window = sceneWindow(scene),
          window.viewWithTag(privacyCoverTag) == nil else { return }
    let style: UIUserInterfaceStyle = PrivacyCoverState.isDark ? .dark : .light
    let cover = UIView(frame: window.bounds)
    cover.tag = privacyCoverTag
    cover.overrideUserInterfaceStyle = style
    // Never `.systemBackground`: that resolves against the DEVICE's
    // appearance, so a light-mode phone running Kute in dark got a
    // white cover, which is the exact thing this view exists to stop.
    // On a first ever launch, with nothing remembered and no frame
    // rendered, the dark background is the safer of the two: a dark
    // cover on a light app reads as the app still loading, a white one
    // on a dark app reads as a crash.
    cover.backgroundColor =
      PrivacyCoverState.background ?? PrivacyCoverState.fallbackDarkBackground
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // Resolved against the app's theme, not the device's, so the mark
    // matches the background it sits on.
    let mark = UIImage(
      named: "LaunchImage",
      in: Bundle.main,
      compatibleWith: UITraitCollection(userInterfaceStyle: style)
    )
    let logo = UIImageView(image: mark)
    logo.contentMode = .scaleAspectFit
    logo.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
    logo.center = cover.center
    logo.autoresizingMask = [
      .flexibleLeftMargin, .flexibleRightMargin,
      .flexibleTopMargin, .flexibleBottomMargin,
    ]
    cover.addSubview(logo)
    window.addSubview(cover)
  }

  private func removePrivacyCover(from scene: UIWindowScene?) {
    sceneWindow(scene)?.viewWithTag(privacyCoverTag)?.removeFromSuperview()
  }
}

/// Privacy-cover state written from Dart over the security channel
/// (`SecurityNativePlugin`, `lib/helpers/privacy_cover_bridge.dart`).
/// Main thread only, which is where both the method channel and the
/// scene notifications land.
enum PrivacyCoverState {
  /// Kute's dark background, `AppColorsExtension.dark()` in
  /// lib/theme/app_theme.dart. Duplicated here on purpose: it is the
  /// only colour available before Dart has run, and it has to be a
  /// literal to be available that early. If the theme's dark
  /// background changes, change it here too.
  static let fallbackDarkBackground = UIColor(
    red: 0x1D / 255.0, green: 0x20 / 255.0, blue: 0x24 / 255.0, alpha: 1)

  private static let backgroundKey = "kute.privacyCover.background"
  private static let isDarkKey = "kute.privacyCover.isDark"

  /// Kute's own background for the theme the app is currently showing.
  ///
  /// Persisted, because the cover can be raised before Flutter has
  /// rendered a single frame: a launch straight into the app switcher,
  /// or a backgrounding during startup. Dart sets this from `build`, so
  /// on those paths it was still nil and the cover fell back to
  /// `.systemBackground`, which follows the DEVICE's appearance rather
  /// than the app's. A phone in light mode running Kute in dark showed
  /// the white rectangle this cover exists to prevent. Remembering the
  /// last known theme across launches closes that window, since the
  /// theme a person had last time is what the app is about to show.
  static var background: UIColor? {
    get {
      if let cached = cachedBackground { return cached }
      let stored = UserDefaults.standard.object(forKey: backgroundKey)
      guard let argb = (stored as? NSNumber)?.uint32Value else { return nil }
      let color = UIColor(argb: argb)
      cachedBackground = color
      return color
    }
    set {
      cachedBackground = newValue
      guard let value = newValue else {
        UserDefaults.standard.removeObject(forKey: backgroundKey)
        return
      }
      UserDefaults.standard.set(NSNumber(value: value.argb), forKey: backgroundKey)
    }
  }

  private static var cachedBackground: UIColor?

  /// Whether that theme is the dark one, for the mark's appearance.
  /// Persisted for the same reason as [background].
  static var isDark: Bool {
    get { UserDefaults.standard.bool(forKey: isDarkKey) }
    set { UserDefaults.standard.set(newValue, forKey: isDarkKey) }
  }

  /// True while a system biometric sheet Kute itself opened is up.
  /// Deliberately NOT persisted: a prompt cannot still be on screen
  /// across a launch, and a stale true would suppress the cover.
  static var biometricPromptActive = false
}

// AppsFlyer 7.0.2 already registers its scene selectors with Flutter, but omits
// the protocol declaration. Declare that existing support so Flutter does not
// also forward the same deep link through its legacy application fallback.
// Remove this extension when the upstream plugin declares the conformance.
extension AppsflyerSdkPlugin: FlutterSceneLifeCycleDelegate {}
