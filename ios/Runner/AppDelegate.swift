import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Local reminders (flutter_local_notifications): deliver taps and
    // foreground presentation to the plugin.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Completion sounds (Phase 12G): NextRep's own channel, beside the
    // generated plugins.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "NextRepCompletionSounds")
    {
      CompletionSoundPlayer.register(with: registrar)
    }
  }
}

/// The completion sounds on iOS (`lib/data/native_sound_player.dart`):
/// bundled files played by `AVAudioPlayer` in the ambient audio session,
/// which respects the silent switch and mixes with other audio (music is
/// never paused or lowered). No permission and no network.
///
/// iOS is not released (ARC_CONTROL_SPEC § 8.5): build-compatible and
/// simulator-smoke only.
final class CompletionSoundPlayer: NSObject, FlutterPlugin {
  static let channelName = "com.nextrep.nextrep/completion_sound"

  private let registrar: FlutterPluginRegistrar
  private var players: [String: AVAudioPlayer] = [:]
  private var sessionConfigured = false

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(
      CompletionSoundPlayer(registrar: registrar), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "prepare":
      guard let sounds = arguments?["sounds"] as? [String: String] else {
        result(FlutterError(code: "bad_arguments", message: "prepare needs sounds", details: nil))
        return
      }
      result(prepare(sounds))
    case "play":
      guard let id = arguments?["sound"] as? String else {
        result(FlutterError(code: "bad_arguments", message: "play needs sound", details: nil))
        return
      }
      result(play(id))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Loads every sound not loaded yet; returns how many were loaded.
  private func prepare(_ sounds: [String: String]) -> Int {
    if !sessionConfigured {
      // Ambient: silent when the switch is on, mixed with other audio. If it
      // can't be set, nothing is loaded or played: the default session
      // (solo ambient) would stop the user's music.
      do {
        try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        sessionConfigured = true
      } catch {
        return 0
      }
    }
    var loaded = 0
    for (id, asset) in sounds where players[id] == nil && Self.isBundledSound(asset) {
      let key = registrar.lookupKey(forAsset: asset)
      guard let path = Bundle.main.path(forResource: key, ofType: nil),
        let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      else { continue }
      player.prepareToPlay()
      players[id] = player
      loaded += 1
    }
    return loaded
  }

  /// Plays a loaded sound once, now; skipped if it isn't loaded.
  private func play(_ id: String) -> String {
    guard let player = players[id] else { return "NOT_READY" }
    // One sound at a time: nothing overlaps.
    for other in players.values where other !== player && other.isPlaying {
      other.stop()
    }
    player.currentTime = 0
    return player.play() ? "PLAYED" : "FAILED"
  }

  /// Only the app's own bundled sound files are ever opened.
  static func isBundledSound(_ asset: String) -> Bool {
    asset.range(of: "^assets/sounds/[a-z_]+\\.wav$", options: .regularExpression) != nil
  }
}
