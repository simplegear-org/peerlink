import Cocoa
import Carbon.HIToolbox
import FlutterMacOS
import ImageIO

final class DeepLinkChannel: NSObject, FlutterStreamHandler {
  static let shared = DeepLinkChannel()

  private let methodChannelName = "peerlink/deep_links/methods"
  private let eventChannelName = "peerlink/deep_links/events"
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var initialLink: String?
  private var pendingLink: String?

  func configure(rootViewController: NSViewController?) {
    guard methodChannel == nil,
      let controller = rootViewController as? FlutterViewController
    else {
      return
    }

    methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialLink" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pendingLink ?? self?.initialLink)
    }

    eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    eventChannel?.setStreamHandler(self)
  }

  @discardableResult
  func handle(url: URL) -> Bool {
    guard isSupportedDeepLink(url) else {
      NSLog("[deep_link] rejected url=%@", url.absoluteString)
      return false
    }
    let link = url.absoluteString
    NSLog("[deep_link] accepted url=%@", link)
    if initialLink == nil {
      initialLink = link
    }
    if let eventSink = eventSink {
      eventSink(link)
    } else {
      pendingLink = link
    }
    return true
  }

  private func isSupportedDeepLink(_ url: URL) -> Bool {
    if url.scheme == "peerlink",
      (url.host == "invite" || url.host == "pair" || url.host == "config" || url.host == "call")
    {
      return true
    }
    if url.scheme == "https",
      (url.host == "simplegear.org" || url.host == "simplegear-org.github.io"),
      (url.pathComponents.contains("invite")
        || url.pathComponents.contains("pair")
        || url.pathComponents.contains("config"))
    {
      return true
    }
    return false
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if let pendingLink = pendingLink {
      events(pendingLink)
      self.pendingLink = nil
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

final class MediaThumbnailChannel {
  static let shared = MediaThumbnailChannel()

  private let methodChannelName = "peerlink/media_thumbnail/methods"
  private var methodChannel: FlutterMethodChannel?

  private init() {}

  func configure(rootViewController: NSViewController?) {
    guard methodChannel == nil,
      let controller = rootViewController as? FlutterViewController
    else {
      return
    }

    methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "generateImageThumbnail" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .utility).async {
        let generated = self?.generateImageThumbnail(arguments: call.arguments) ?? false
        DispatchQueue.main.async {
          result(generated)
        }
      }
    }
  }

  private func generateImageThumbnail(arguments: Any?) -> Bool {
    guard
      let payload = arguments as? [String: Any],
      let sourcePath = payload["sourcePath"] as? String,
      let destinationPath = payload["destinationPath"] as? String
    else {
      return false
    }
    let maxWidth = CGFloat((payload["maxWidth"] as? NSNumber)?.doubleValue ?? 640)
    let maxHeight = CGFloat((payload["maxHeight"] as? NSNumber)?.doubleValue ?? 440)
    let maxPixelSize = max(maxWidth, maxHeight)
    guard
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let cgImage = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
      )
    else {
      return false
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard
      let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.76])
    else {
      return false
    }
    do {
      let destination = URL(fileURLWithPath: destinationPath)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: destination, options: .atomic)
      return true
    } catch {
      return false
    }
  }

}

@main
class AppDelegate: FlutterAppDelegate {
  override init() {
    super.init()
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    DeepLinkChannel.shared.configure(rootViewController: mainFlutterWindow?.contentViewController)
    MediaThumbnailChannel.shared.configure(rootViewController: mainFlutterWindow?.contentViewController)
    NSApplication.shared.registerForRemoteNotifications()
    NSLog("[push] registerForRemoteNotifications requested")
  }

  override func application(
    _ application: NSApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    NSLog("[push] APNs token received length=%ld token=%@", token.count, token)
  }

  override func application(
    _ application: NSApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[push] APNs registration failed error=%@", error.localizedDescription)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      NSLog("[deep_link] open-urls callback url=%@", url.absoluteString)
      _ = DeepLinkChannel.shared.handle(url: url)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @objc func handleGetURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent replyEvent: NSAppleEventDescriptor
  ) {
    guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
      let url = URL(string: urlString)
    else {
      NSLog("[deep_link] get-url invalid event")
      return
    }
    NSLog("[deep_link] get-url event url=%@", urlString)
    _ = DeepLinkChannel.shared.handle(url: url)
  }

  override func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = userActivity.webpageURL,
      DeepLinkChannel.shared.handle(url: url)
    {
      NSLog("[deep_link] user-activity handled url=%@", url.absoluteString)
      return true
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

}
