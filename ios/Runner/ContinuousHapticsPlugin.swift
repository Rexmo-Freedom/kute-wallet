import CoreHaptics
import Flutter
import UIKit

/// Bridges the Dart `kute/continuous_haptics` MethodChannel
/// (`lib/services/continuous_haptics.dart`): the rubber band's felt pull,
/// modelled on Instagram's vanish-mode pull.
///
///   * `start(intensity, sharpness)` — one continuous Core Haptics event
///     (`hapticContinuous`, intensity 1, sharpness [baseSharpness], 30 s)
///     played by a looping `CHHapticAdvancedPatternPlayer`, so it is
///     re-armed natively before it ends and plays for as long as Dart
///     wants it;
///   * `update(intensity, sharpness)` — `CHHapticDynamicParameter`s on that
///     player (`hapticIntensityControl` scales the event's full intensity,
///     `hapticSharpnessControl` offsets its sharpness), so the strength
///     changes smoothly while it plays. Dart sends at most ~30 a second;
///   * `stop()` — stops the rumble;
///   * `tick(intensity, sharpness)` — one transient, a ratchet click over
///     the rumble;
///   * `pulse(intensity)` — one soft, dull transient (a long wait's
///     heartbeat);
///   * `snap()` — stops the rumble, then a 90 ms continuous swell (the
///     whoosh) into a transient at full intensity and sharpness (the snap);
///   * `softTap()` — stops the rumble, then one soft transient.
///
/// Every method answers `nil` at once and never fails: a device without
/// haptics (`CHHapticEngine.capabilitiesForHardware().supportsHaptics`),
/// an engine that cannot start, or a player error plays nothing (the snap
/// and the soft tap fall back to `UIImpactFeedbackGenerator`). The engine's
/// `stoppedHandler` and `resetHandler` drop the players; a rumble Dart
/// still wants is rebuilt on the next update (reset: at once). The rumble
/// stops and the engine stops when the app enters the background. The
/// system haptics setting applies on its own.
final class ContinuousHapticsPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kute/continuous_haptics", binaryMessenger: registrar.messenger())
    let instance = ContinuousHapticsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  /// The rumble event's own sharpness; the sharpness control offsets it.
  private static let baseSharpness: Float = 0.5

  /// The rumble event's length; the player loops it.
  private static let rumbleSeconds: TimeInterval = 30

  private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
  private var engine: CHHapticEngine?
  private var engineRunning = false
  private var rumble: CHHapticAdvancedPatternPlayer?

  /// Dart wants the rumble playing, at these values.
  private var wantRumble = false
  private var intensity: Float = 0.3
  private var sharpness: Float = 0.1

  /// The last time a lost rumble was rebuilt, so a failing engine is not
  /// retried 30 times a second.
  private var lastRebuild: CFTimeInterval = 0

  private var observers: [NSObjectProtocol] = []

  override init() {
    super.init()
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.enterBackground()
      })
  }

  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let i = Self.unit(args?["intensity"], fallback: 0.5)
    let s = Self.unit(args?["sharpness"], fallback: 0.5)
    switch call.method {
    case "start":
      wantRumble = true
      intensity = i
      sharpness = s
      startRumble()
    case "update":
      intensity = i
      sharpness = s
      if wantRumble {
        if rumble == nil {
          let now = CACurrentMediaTime()
          if now - lastRebuild > 0.5 {
            lastRebuild = now
            startRumble()
          }
        } else {
          sendParameters()
        }
      }
    case "stop":
      stopRumble()
    case "tick":
      _ = transient(intensity: i, sharpness: s)
    case "pulse":
      _ = transient(intensity: i * 0.8, sharpness: 0.12)
    case "snap":
      stopRumble()
      if !playSnap() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
      }
    case "softTap":
      stopRumble()
      if !transient(intensity: 0.45, sharpness: 0.2) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      }
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  // MARK: - Engine

  private func readyEngine() -> CHHapticEngine? {
    guard supported else { return nil }
    if engine == nil {
      do {
        let e = try CHHapticEngine()
        e.playsHapticsOnly = true
        e.isAutoShutdownEnabled = true
        e.stoppedHandler = { [weak self] _ in
          DispatchQueue.main.async {
            self?.engineRunning = false
            self?.rumble = nil
          }
        }
        e.resetHandler = { [weak self] in
          DispatchQueue.main.async {
            guard let self = self else { return }
            self.engineRunning = false
            self.rumble = nil
            if self.wantRumble { self.startRumble() }
          }
        }
        engine = e
      } catch {
        return nil
      }
    }
    guard let e = engine else { return nil }
    if !engineRunning {
      do {
        try e.start()
        engineRunning = true
      } catch {
        return nil
      }
    }
    return e
  }

  private func enterBackground() {
    stopRumble()
    if engineRunning {
      engine?.stop(completionHandler: nil)
      engineRunning = false
    }
  }

  // MARK: - Rumble

  private func startRumble() {
    if let old = rumble {
      try? old.stop(atTime: CHHapticTimeImmediate)
      rumble = nil
    }
    guard wantRumble, let e = readyEngine() else { return }
    do {
      let event = CHHapticEvent(
        eventType: .hapticContinuous,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: Self.baseSharpness),
        ],
        relativeTime: 0,
        duration: Self.rumbleSeconds)
      // The level rides in the pattern too, so the first frame already
      // plays at it (no blip at the event's full intensity). Dart's
      // updates (~30 a second) carry it from there.
      let pattern = try CHHapticPattern(events: [event], parameters: levelParameters())
      let player = try e.makeAdvancedPlayer(with: pattern)
      player.loopEnabled = true
      player.loopEnd = Self.rumbleSeconds
      player.completionHandler = { [weak self, weak player] _ in
        DispatchQueue.main.async {
          guard let self = self, let player = player else { return }
          if self.rumble === player { self.rumble = nil }
        }
      }
      try player.start(atTime: CHHapticTimeImmediate)
      rumble = player
    } catch {
      rumble = nil
    }
  }

  private func levelParameters() -> [CHHapticDynamicParameter] {
    [
      CHHapticDynamicParameter(
        parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
      CHHapticDynamicParameter(
        parameterID: .hapticSharpnessControl, value: sharpness - Self.baseSharpness,
        relativeTime: 0),
    ]
  }

  private func sendParameters() {
    guard let player = rumble else { return }
    do {
      try player.sendParameters(levelParameters(), atTime: CHHapticTimeImmediate)
    } catch {
      // The player went with the engine; the next update rebuilds it.
      rumble = nil
    }
  }

  private func stopRumble() {
    wantRumble = false
    if let player = rumble {
      try? player.stop(atTime: CHHapticTimeImmediate)
      rumble = nil
    }
  }

  // MARK: - One-shots

  @discardableResult
  private func transient(intensity: Float, sharpness: Float) -> Bool {
    guard let e = readyEngine() else { return false }
    do {
      let event = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ],
        relativeTime: 0)
      let player = try e.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
      try player.start(atTime: CHHapticTimeImmediate)
      return true
    } catch {
      return false
    }
  }

  /// The whoosh (a 90 ms swell, soft to full) into the snap (a transient
  /// at full intensity and sharpness).
  private func playSnap() -> Bool {
    guard let e = readyEngine() else { return false }
    let whoosh: TimeInterval = 0.09
    do {
      let swell = CHHapticEvent(
        eventType: .hapticContinuous,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
        ],
        relativeTime: 0,
        duration: whoosh)
      let snap = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: 1),
        ],
        relativeTime: whoosh)
      let rise = CHHapticParameterCurve(
        parameterID: .hapticIntensityControl,
        controlPoints: [
          CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.15),
          CHHapticParameterCurve.ControlPoint(relativeTime: whoosh, value: 1),
        ],
        relativeTime: 0)
      let edge = CHHapticParameterCurve(
        parameterID: .hapticSharpnessControl,
        controlPoints: [
          CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: -0.2),
          CHHapticParameterCurve.ControlPoint(relativeTime: whoosh, value: 0.4),
        ],
        relativeTime: 0)
      let pattern = try CHHapticPattern(
        events: [swell, snap], parameterCurves: [rise, edge])
      let player = try e.makePlayer(with: pattern)
      try player.start(atTime: CHHapticTimeImmediate)
      return true
    } catch {
      return false
    }
  }

  private static func unit(_ value: Any?, fallback: Float) -> Float {
    let v: Double
    if let d = value as? Double {
      v = d
    } else if let n = value as? NSNumber {
      v = n.doubleValue
    } else {
      return fallback
    }
    guard v.isFinite else { return fallback }
    return Float(min(1, max(0, v)))
  }
}
