import Flutter
import UIKit

/// DragonTrack uses UIScene (see UIApplicationSceneManifest in
/// Info.plist), so for a single-window app like this one, iOS delivers
/// every "open this file" event to the SCENE delegate — never to
/// AppDelegate.application(_:open:options:) — for both a cold launch
/// (via connectionOptions.urlContexts below) and while already
/// running/backgrounded (via openURLContexts below). Previously this
/// class overrode nothing at all, so a tapped .salsfarm file's URL was
/// silently dropped before it ever reached the receive_sharing_intent
/// plugin (see GeneratedPluginRegistrant.m), no matter how correctly
/// that plugin or the Dart side was configured.
///
/// Rather than reimplement file receiving, security-scoped resource
/// access, or add a second Flutter communication channel, both overrides
/// below simply forward the incoming URL to
/// `UIApplication.shared.delegate?.application?(_:open:url:options:)` —
/// the exact entry point iOS itself would call on a non-Scene app, and
/// the one receive_sharing_intent's iOS plugin already implements.
/// FlutterAppDelegate (AppDelegate's superclass) forwards that call to
/// every registered plugin that implements it, so the plugin's own
/// existing, already-working logic — including whatever security-scoped
/// resource access and temp-copy it performs before handing a path back
/// to Dart — runs completely unchanged. This keeps DragonTrack to exactly
/// one file-import architecture (ReceiveSharingIntent.instance.
/// getInitialMedia()/getMediaStream() → main.dart/HomeScreen →
/// ImportFarmPreviewScreen) instead of a second, parallel one.
class SceneDelegate: FlutterSceneDelegate {

  /// Cold launch (app fully closed) and the "app was backgrounded, iOS is
  /// (re)connecting the scene to bring it forward" half of a resume: the
  /// file that launched/resumed the app arrives as one of
  /// `connectionOptions.urlContexts`, not as a separate openURLContexts
  /// call.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    if let url = connectionOptions.urlContexts.first?.url {
      forwardToPlugins(url)
    }
  }

  /// App already running, or already in the foreground: iOS calls this
  /// directly instead of reconnecting the scene.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url {
      forwardToPlugins(url)
    }
  }

  private func forwardToPlugins(_ url: URL) {
    _ = UIApplication.shared.delegate?.application?(
      UIApplication.shared,
      open: url,
      options: [:]
    )
  }
}
