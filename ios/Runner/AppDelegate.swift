import CallKit
import Flutter
import ImageIO
import Photos
import PushKit
import UIKit
import UserNotifications
import WebRTC

final class DeepLinkChannel: NSObject, FlutterStreamHandler {
  static let shared = DeepLinkChannel()

  private let methodChannelName = "peerlink/deep_links/methods"
  private let eventChannelName = "peerlink/deep_links/events"
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var initialLink: String?
  private var pendingLink: String?

  private override init() {
    super.init()
  }

  func configure(rootViewController: UIViewController?) {
    guard methodChannel == nil,
      let controller = rootViewController as? FlutterViewController
    else {
      return
    }

    methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialLink" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.initialLink)
    }

    eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel?.setStreamHandler(self)
  }

  @discardableResult
  func handle(url: URL) -> Bool {
    guard isSupportedDeepLink(url) else {
      return false
    }
    let link = url.absoluteString
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

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
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

  func configure(rootViewController: UIViewController?) {
    guard methodChannel == nil,
      let controller = rootViewController as? FlutterViewController
    else {
      return
    }
    methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: controller.binaryMessenger
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
    let thumbnail = UIImage(cgImage: cgImage)
    guard let data = thumbnail.jpegData(compressionQuality: 0.76) else {
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

  private func fittedSize(source: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
    guard source.width > 0, source.height > 0 else {
      return CGSize(width: max(1, maxWidth), height: max(1, maxHeight))
    }
    let scale = min(maxWidth / source.width, maxHeight / source.height, 1)
    return CGSize(
      width: max(1, source.width * scale),
      height: max(1, source.height * scale)
    )
  }

  private func renderThumbnail(image: UIImage, targetSize: CGSize) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

}

final class VoipCallBridge: NSObject, FlutterStreamHandler, PKPushRegistryDelegate, CXProviderDelegate {
  static let shared = VoipCallBridge()

  private let methodChannelName = "peerlink/callkit/methods"
  private let eventChannelName = "peerlink/callkit/events"
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var pendingEvents: [[String: Any]] = []

  private var voipRegistry: PKPushRegistry?
  private var voipToken: String?
  private var activeCallByUuid: [UUID: [String: String]] = [:]
  private var callUuidByCallId: [String: UUID] = [:]
  private var suppressedEndActionUuids: Set<UUID> = []
  private let callController = CXCallController()
  private lazy var provider: CXProvider = {
    let config = CXProviderConfiguration(localizedName: "PeerLink X")
    config.supportsVideo = true
    config.includesCallsInRecents = true
    config.supportedHandleTypes = [.generic]
    config.maximumCallsPerCallGroup = 1
    config.maximumCallGroups = 1
    let provider = CXProvider(configuration: config)
    provider.setDelegate(self, queue: nil)
    return provider
  }()

  private override init() {
    super.init()
  }

  func configure(rootViewController: UIViewController?) {
    guard methodChannel == nil,
      let controller = rootViewController as? FlutterViewController
    else {
      return
    }
    methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "getVoipToken":
        result(self.voipToken)
      case "refreshVoipRegistration":
        self.refreshVoipRegistration()
        result(nil)
      case "endSystemCall":
        self.endSystemCall()
        result(nil)
      case "startOutgoingCall":
        guard
          let args = call.arguments as? [String: Any],
          let callId = (args["callId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let peerId = (args["peerId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !callId.isEmpty,
          !peerId.isEmpty
        else {
          result(FlutterError(code: "invalid_args", message: "callId/peerId required", details: nil))
          return
        }
        let mediaType = ((args["mediaType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap {
          $0.isEmpty ? nil : $0
        } ?? "audio"
        let displayName = ((args["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
          $0.isEmpty ? nil : $0
        }
        self.startOutgoingCall(callId: callId, peerId: peerId, mediaType: mediaType, displayName: displayName)
        result(nil)
      case "updateOutgoingCall":
        guard
          let args = call.arguments as? [String: Any],
          let callId = (args["callId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !callId.isEmpty
        else {
          result(FlutterError(code: "invalid_args", message: "callId required", details: nil))
          return
        }
        let connected = args["connected"] as? Bool ?? false
        let displayName = ((args["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
          $0.isEmpty ? nil : $0
        }
        self.updateOutgoingCall(callId: callId, connected: connected, displayName: displayName)
        result(nil)
      case "updateIncomingCallerName":
        guard
          let args = call.arguments as? [String: Any],
          let callId = (args["callId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let displayName = (args["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !callId.isEmpty,
          !displayName.isEmpty
        else {
          result(FlutterError(code: "invalid_args", message: "callId/displayName required", details: nil))
          return
        }
        self.updateIncomingCallerName(callId: callId, displayName: displayName)
        result(nil)
      case "callUiPresented":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel?.setStreamHandler(self)
    configurePushRegistryIfNeeded()
  }

  private func configurePushRegistryIfNeeded() {
    guard voipRegistry == nil else {
      return
    }
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }

  private func refreshVoipRegistration() {
    voipRegistry?.delegate = nil
    voipRegistry = nil
    configurePushRegistryIfNeeded()
    if let voipToken {
      emit([
        "type": "voip_token",
        "token": voipToken,
      ])
    }
  }

  private func emit(_ payload: [String: Any]) {
    guard let eventSink else {
      NSLog(
        "[CallKit] emit queued type=%@ keys=%@",
        String(describing: payload["type"] ?? ""),
        String(describing: Array(payload.keys))
      )
      pendingEvents.append(payload)
      return
    }
    NSLog(
      "[CallKit] emit immediate type=%@ keys=%@",
      String(describing: payload["type"] ?? ""),
      String(describing: Array(payload.keys))
    )
    eventSink(payload)
  }

  private func uuid(for callId: String) -> UUID {
    if let existing = callUuidByCallId[callId] {
      return existing
    }
    let created = UUID()
    callUuidByCallId[callId] = created
    return created
  }

  private func reportIncomingCall(payload: [AnyHashable: Any], completion: (() -> Void)? = nil) {
    defer { completion?() }
    let callId =
      extractString(from: payload, keys: ["callId", "call_id"])?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let callAction =
      extractString(from: payload, keys: ["callAction", "call_action"])?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let callerUserId =
      extractString(from: payload, keys: ["callerUserId", "senderUserId", "fromPeerId", "peerId"])?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let mediaType =
      extractString(from: payload, keys: ["mediaType", "media_type"])?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "audio"
    let serversJson = extractJsonString(from: payload, keys: ["servers"])
    let priorityServersJson = extractJsonString(from: payload, keys: ["priority_servers"])
    NSLog(
      "[CallKit] voip payload parsed callId=%@ caller=%@ mediaType=%@ action=%@ serversLength=%ld priorityServersLength=%ld",
      callId,
      callerUserId,
      mediaType,
      callAction,
      serversJson?.count ?? 0,
      priorityServersJson?.count ?? 0
    )
    if callAction == "end" {
      NSLog("[CallKit] voip payload resolved as end callId=%@", callId)
      endSystemCall(callId: callId)
      return
    }
    if callId.isEmpty || callerUserId.isEmpty {
      NSLog("[CallKit] voip payload missing callId/callerUserId keys=%@", String(describing: Array(payload.keys)))
      return
    }
    if UIApplication.shared.applicationState == .active {
      NSLog("[CallKit] foreground incoming call routed to app UI callId=%@ caller=%@", callId, callerUserId)
      emit([
        "type": "call_incoming",
        "callId": callId,
        "fromPeerId": callerUserId,
        "callerUserId": callerUserId,
        "mediaType": mediaType,
        "servers": serversJson ?? "",
        "priority_servers": priorityServersJson ?? "",
      ])
      return
    }
    let callUuid = uuid(for: callId)
    if var existing = activeCallByUuid[callUuid] {
      existing["fromPeerId"] = callerUserId
      existing["mediaType"] = mediaType
      existing["servers"] = serversJson ?? ""
      existing["priority_servers"] = priorityServersJson ?? ""
      activeCallByUuid[callUuid] = existing
      NSLog(
        "[CallKit] duplicate incoming push ignored callId=%@ uuid=%@ state=%@",
        callId,
        callUuid.uuidString,
        existing["state"] ?? "unknown"
      )
      return
    }
    activeCallByUuid[callUuid] = [
      "callId": callId,
      "fromPeerId": callerUserId,
      "mediaType": mediaType,
      "state": "incoming",
      "servers": serversJson ?? "",
      "priority_servers": priorityServersJson ?? "",
    ]
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callerUserId)
    update.localizedCallerName = callerUserId
    update.hasVideo = mediaType == "video"
    NSLog(
      "[CallKit] reportNewIncomingCall start callId=%@ uuid=%@ caller=%@ hasVideo=%@",
      callId,
      callUuid.uuidString,
      callerUserId,
      update.hasVideo.description
    )
    provider.reportNewIncomingCall(with: callUuid, update: update) { [weak self] error in
      if let error {
        NSLog("[CallKit] report incoming failed: %@", error.localizedDescription)
        return
      }
      NSLog(
        "[CallKit] report incoming ok callId=%@ uuid=%@ caller=%@",
        callId,
        callUuid.uuidString,
        callerUserId
      )
      self?.emit([
        "type": "call_incoming",
        "callId": callId,
        "fromPeerId": callerUserId,
        "callerUserId": callerUserId,
        "mediaType": mediaType,
        "servers": serversJson ?? "",
        "priority_servers": priorityServersJson ?? "",
      ])
    }
  }

  private func extractString(from payload: [AnyHashable: Any], keys: [String]) -> String? {
    for key in keys {
      if let value = payload[key] as? String, !value.isEmpty {
        return value
      }
    }
    for nested in nestedPayloadContainers(from: payload) {
      for key in keys {
        if let value = nested[key] as? String, !value.isEmpty {
          return value
        }
      }
    }
    return nil
  }

  private func extractJsonString(from payload: [AnyHashable: Any], keys: [String]) -> String? {
    for key in keys {
      if let value = payload[key] as? String, !value.isEmpty {
        return value
      }
      if let value = payload[key] {
        if JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let json = String(data: data, encoding: .utf8),
          !json.isEmpty
        {
          return json
        }
      }
    }
    for nested in nestedPayloadContainers(from: payload) {
      for key in keys {
        if let value = nested[key] as? String, !value.isEmpty {
          return value
        }
        if let value = nested[key] {
          if JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value),
            let json = String(data: data, encoding: .utf8),
            !json.isEmpty
          {
            return json
          }
        }
      }
    }
    return nil
  }

  private func nestedPayloadContainers(from payload: [AnyHashable: Any]) -> [[AnyHashable: Any]] {
    var containers: [[AnyHashable: Any]] = []
    for containerKey in ["data", "payload", "aps"] {
      if let nested = payload[containerKey] as? [AnyHashable: Any] {
        containers.append(nested)
        continue
      }
      guard let raw = payload[containerKey] as? String, !raw.isEmpty else {
        continue
      }
      guard let data = raw.data(using: .utf8) else {
        continue
      }
      if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        containers.append(Dictionary(uniqueKeysWithValues: decoded.map { ($0.key as AnyHashable, $0.value) }))
      }
    }
    return containers
  }

  private func endSystemCall() {
    guard let metadata = activeCallByUuid.first else {
      return
    }
    endSystemCall(callId: metadata.value["callId"])
  }

  private func endSystemCall(callId: String?) {
    let trimmedCallId = callId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let metadata: (UUID, [String: String])?
    if trimmedCallId.isEmpty {
      metadata = activeCallByUuid.first
    } else if let uuid = callUuidByCallId[trimmedCallId], let item = activeCallByUuid[uuid] {
      metadata = (uuid, item)
    } else {
      metadata = activeCallByUuid.first(where: { $0.value["callId"] == trimmedCallId })
    }
    guard let entry = metadata else {
      return
    }
    let uuid = entry.0
    let resolvedCallId = entry.1["callId"] ?? trimmedCallId
    suppressedEndActionUuids.insert(uuid)
    let action = CXEndCallAction(call: uuid)
    let transaction = CXTransaction(action: action)
    callController.request(transaction) { error in
      if let error {
        NSLog("[CallKit] endSystemCall transaction failed: %@", error.localizedDescription)
        self.suppressedEndActionUuids.remove(uuid)
      }
    }
    if !resolvedCallId.isEmpty {
      callUuidByCallId.removeValue(forKey: resolvedCallId)
    }
    activeCallByUuid.removeValue(forKey: uuid)
  }

  private func startOutgoingCall(callId: String, peerId: String, mediaType: String, displayName: String?) {
    let callUuid = uuid(for: callId)
    if activeCallByUuid[callUuid] != nil {
      updateOutgoingCall(callId: callId, connected: false, displayName: displayName)
      return
    }
    let handleValue = displayName ?? peerId
    activeCallByUuid[callUuid] = [
      "callId": callId,
      "fromPeerId": peerId,
      "mediaType": mediaType,
      "state": "outgoing",
      "callerDisplayName": handleValue,
    ]
    let handle = CXHandle(type: .generic, value: handleValue)
    let action = CXStartCallAction(call: callUuid, handle: handle)
    action.isVideo = mediaType == "video"
    let transaction = CXTransaction(action: action)
    callController.request(transaction) { error in
      if let error {
        NSLog("[CallKit] startOutgoingCall transaction failed: %@", error.localizedDescription)
        self.callUuidByCallId.removeValue(forKey: callId)
        self.activeCallByUuid.removeValue(forKey: callUuid)
        return
      }
      let update = CXCallUpdate()
      update.remoteHandle = handle
      update.localizedCallerName = handleValue
      update.hasVideo = mediaType == "video"
      self.provider.reportCall(with: callUuid, updated: update)
      self.provider.reportOutgoingCall(with: callUuid, startedConnectingAt: Date())
      NSLog(
        "[CallKit] startOutgoingCall ok callId=%@ uuid=%@ peer=%@ hasVideo=%@",
        callId,
        callUuid.uuidString,
        peerId,
        update.hasVideo.description
      )
    }
  }

  private func updateOutgoingCall(callId: String, connected: Bool, displayName: String?) {
    guard let callUuid = callUuidByCallId[callId] else {
      return
    }
    if let displayName, !displayName.isEmpty {
      let handle = CXHandle(type: .generic, value: displayName)
      let update = CXCallUpdate()
      update.remoteHandle = handle
      update.localizedCallerName = displayName
      update.hasVideo = (activeCallByUuid[callUuid]?["mediaType"] ?? "audio") == "video"
      provider.reportCall(with: callUuid, updated: update)
      activeCallByUuid[callUuid]?["callerDisplayName"] = displayName
    }
    if connected {
      let currentState = activeCallByUuid[callUuid]?["state"] ?? ""
      if currentState != "active" {
        provider.reportOutgoingCall(with: callUuid, connectedAt: Date())
        activeCallByUuid[callUuid]?["state"] = "active"
        NSLog("[CallKit] updateOutgoingCall connected callId=%@", callId)
      }
    }
  }

  private func updateIncomingCallerName(callId: String, displayName: String) {
    guard let uuid = callUuidByCallId[callId] else {
      return
    }
    let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedDisplayName.isEmpty else {
      return
    }
    let update = CXCallUpdate()
    update.localizedCallerName = normalizedDisplayName
    update.remoteHandle = CXHandle(type: .generic, value: normalizedDisplayName)
    provider.reportCall(with: uuid, updated: update)
    activeCallByUuid[uuid]?["callerDisplayName"] = normalizedDisplayName
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP else {
      return
    }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    voipToken = token
    emit([
      "type": "voip_token",
      "token": token,
    ])
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else {
      return
    }
    voipToken = nil
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    NSLog(
      "[CallKit] received voip push type=%@ keys=%@ payload=%@",
      type.rawValue,
      String(describing: Array(payload.dictionaryPayload.keys)),
      String(describing: payload.dictionaryPayload)
    )
    if JSONSerialization.isValidJSONObject(payload.dictionaryPayload),
      let data = try? JSONSerialization.data(withJSONObject: payload.dictionaryPayload, options: []),
      let json = String(data: data, encoding: .utf8)
    {
      NSLog("[CallKit] voip push stored in PushPayloadBridge length=%ld", json.count)
      PushPayloadBridge.shared.pushPayload(json: json)
    }
    reportIncomingCall(payload: payload.dictionaryPayload, completion: completion)
  }

  func providerDidReset(_ provider: CXProvider) {
    activeCallByUuid.removeAll()
    callUuidByCallId.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    let metadata = activeCallByUuid[action.callUUID]
    activeCallByUuid[action.callUUID]?["state"] = "active"
    let callId = metadata?["callId"] ?? ""
    emit([
      "type": "call_action",
      "action": "accept",
      "callId": callId,
      "fromPeerId": metadata?["fromPeerId"] ?? "",
      "mediaType": metadata?["mediaType"] ?? "audio",
      "servers": metadata?["servers"] ?? "",
      "priority_servers": metadata?["priority_servers"] ?? "",
    ])
    emit([
      "type": "open_call_screen",
      "callId": callId,
      "fromPeerId": metadata?["fromPeerId"] ?? "",
      "mediaType": metadata?["mediaType"] ?? "audio",
    ])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    if var metadata = activeCallByUuid[action.callUUID] {
      metadata["state"] = "outgoing"
      activeCallByUuid[action.callUUID] = metadata
    }
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    if suppressedEndActionUuids.contains(action.callUUID) {
      suppressedEndActionUuids.remove(action.callUUID)
      let metadata = activeCallByUuid[action.callUUID]
      if let callId = metadata?["callId"] {
        callUuidByCallId.removeValue(forKey: callId)
      }
      activeCallByUuid.removeValue(forKey: action.callUUID)
      action.fulfill()
      return
    }
    let metadata = activeCallByUuid[action.callUUID]
    let state = metadata?["state"] ?? "incoming"
    let actionType = state == "incoming" ? "reject" : "end"
    emit([
      "type": "call_action",
      "action": actionType,
      "callId": metadata?["callId"] ?? "",
      "fromPeerId": metadata?["fromPeerId"] ?? "",
      "mediaType": metadata?["mediaType"] ?? "audio",
    ])
    if let callId = metadata?["callId"] {
      callUuidByCallId.removeValue(forKey: callId)
    }
    activeCallByUuid.removeValue(forKey: action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    let routeOutputs = audioSession.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
    NSLog(
      "[CallKit] audio session activated category=%@ mode=%@ route=%@",
      audioSession.category.rawValue,
      audioSession.mode.rawValue,
      routeOutputs
    )
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    emit([
      "type": "audio_session_activated",
    ])
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    NSLog("[CallKit] audio session deactivated")
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    emit([
      "type": "audio_session_deactivated",
    ])
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    NSLog(
      "[CallKit] event stream listen pendingEvents=%ld hasVoipToken=%@",
      pendingEvents.count,
      (voipToken != nil).description
    )
    eventSink = events
    if !pendingEvents.isEmpty {
      for event in pendingEvents {
        NSLog(
          "[CallKit] replay pending event type=%@ keys=%@",
          String(describing: event["type"] ?? ""),
          String(describing: Array(event.keys))
        )
        events(event)
      }
      pendingEvents.removeAll(keepingCapacity: false)
    }
    if let voipToken {
      NSLog("[CallKit] emit current voip token to listener")
      events([
        "type": "voip_token",
        "token": voipToken,
      ])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

}

final class PushPayloadBridge: NSObject {
  static let shared = PushPayloadBridge()

  private let methodChannelName = "peerlink/push_payload/methods"
  private var methodChannel: FlutterMethodChannel?
  private var latestPayloadJson: String?

  private override init() {
    super.init()
  }

  func configure(registrar: FlutterPluginRegistrar) {
    guard methodChannel == nil else {
      return
    }
    methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "consumeLatestPushPayload":
        let payload = self.latestPayloadJson
        self.latestPayloadJson = nil
        result(payload)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func pushPayload(json: String, notifyFlutter: Bool = false) {
    NSLog("[PushPayloadBridge] store payload length=%ld", json.count)
    latestPayloadJson = json
    if notifyFlutter {
      DispatchQueue.main.async { [weak self] in
        self?.methodChannel?.invokeMethod("pushPayloadAvailable", arguments: nil)
      }
    }
  }
}

final class MediaGalleryChannel: NSObject {
  static let shared = MediaGalleryChannel()

  private let methodChannelName = "peerlink/media_gallery/methods"
  private let workQueue = DispatchQueue(
    label: "org.simplegear.peerlink.media_gallery",
    qos: .utility
  )
  private var methodChannel: FlutterMethodChannel?

  private override init() {
    super.init()
  }

  func configure(rootViewController: UIViewController?) {
    guard methodChannel == nil,
      let controller = rootViewController as? FlutterViewController
    else {
      return
    }

    methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      guard call.method == "saveMediaIfMissing" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let filePath = args["filePath"] as? String,
        let fileName = args["fileName"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "filePath and fileName are required",
            details: nil
          )
        )
        return
      }
      self.saveMediaIfMissing(filePath: filePath, fileName: fileName, result: result)
    }
  }

  private func saveMediaIfMissing(
    filePath: String,
    fileName: String,
    result: @escaping FlutterResult
  ) {
    let normalizedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
      result(
        FlutterError(code: "invalid_args", message: "fileName is empty", details: nil)
      )
      return
    }

    requestAccessIfNeeded { [weak self] granted in
      guard let self else {
        result(nil)
        return
      }
      guard granted else {
        result(
          FlutterError(
            code: "permission_denied",
            message: "Photo library access denied",
            details: nil
          )
        )
        return
      }

      self.workQueue.async {
        if self.assetExists(named: normalizedName) {
          DispatchQueue.main.async {
            result(nil)
          }
          return
        }

        self.saveAsset(filePath: filePath, fileName: normalizedName, result: result)
      }
    }
  }

  private func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
    if #available(iOS 14, *) {
      let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
      switch status {
      case .authorized, .limited:
        completion(true)
      case .notDetermined:
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
          DispatchQueue.main.async {
            completion(newStatus == .authorized || newStatus == .limited)
          }
        }
      default:
        completion(false)
      }
      return
    }

    let status = PHPhotoLibrary.authorizationStatus()
    switch status {
    case .authorized:
      completion(true)
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization { newStatus in
        DispatchQueue.main.async {
          completion(newStatus == .authorized)
        }
      }
    default:
      completion(false)
    }
  }

  private func assetExists(named fileName: String) -> Bool {
    let assets = PHAsset.fetchAssets(with: PHFetchOptions())
    var found = false
    assets.enumerateObjects { asset, _, stop in
      let resources = PHAssetResource.assetResources(for: asset)
      if resources.contains(where: { $0.originalFilename == fileName }) {
        found = true
        stop.pointee = true
      }
    }
    return found
  }

  private func saveAsset(
    filePath: String,
    fileName: String,
    result: @escaping FlutterResult
  ) {
    let fileUrl = URL(fileURLWithPath: filePath)
    let lowercasedName = fileName.lowercased()
    let isImage = [
      ".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif", ".bmp",
    ].contains { lowercasedName.hasSuffix($0) }
    let isVideo = UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(filePath)

    guard isImage || isVideo else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "unsupported_type",
            message: "Unsupported media type",
            details: nil
          )
        )
      }
      return
    }

    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = fileName
      if isImage {
        request.addResource(with: .photo, fileURL: fileUrl, options: options)
      } else if isVideo {
        request.addResource(with: .video, fileURL: fileUrl, options: options)
      }
    }) { success, error in
      DispatchQueue.main.async {
        if success {
          result(nil)
        } else {
          result(
            FlutterError(
              code: "save_failed",
              message: error?.localizedDescription ?? "Failed to save media",
              details: nil
            )
          )
        }
      }
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private func writeToPeerlinkAppLog(_ line: String) {
    let tempDir = NSTemporaryDirectory()
    let logDir = (tempDir as NSString).appendingPathComponent(".peerlink/logs")
    let logPath = (logDir as NSString).appendingPathComponent("app.log")
    let fileManager = FileManager.default
    do {
      if !fileManager.fileExists(atPath: logDir) {
        try fileManager.createDirectory(atPath: logDir, withIntermediateDirectories: true)
      }
      if !fileManager.fileExists(atPath: logPath) {
        fileManager.createFile(atPath: logPath, contents: nil)
      }
      let timestamp = ISO8601DateFormatter().string(from: Date())
      let fullLine = "[\(timestamp)][AppDelegate] \(line)\n"
      if let data = fullLine.data(using: .utf8),
        let handle = FileHandle(forWritingAtPath: logPath)
      {
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
      }
    } catch {
      NSLog("[AppDelegate][push][logfile] write failed: %@", error.localizedDescription)
    }
  }

  private func logRemoteNotificationPayload(
    _ userInfo: [AnyHashable: Any],
    source: String,
    notifyFlutter: Bool = false
  ) {
    if JSONSerialization.isValidJSONObject(userInfo) {
      do {
        let data = try JSONSerialization.data(withJSONObject: userInfo, options: [])
        if let json = String(data: data, encoding: .utf8) {
          NSLog("[AppDelegate][push][%@] %@", source, json)
          writeToPeerlinkAppLog("[push][\(source)] \(json)")
          PushPayloadBridge.shared.pushPayload(json: json, notifyFlutter: notifyFlutter)
          return
        }
      } catch {
        NSLog("[AppDelegate][push][%@] failed to encode json: %@", source, error.localizedDescription)
        writeToPeerlinkAppLog("[push][\(source)] failed to encode json: \(error.localizedDescription)")
      }
    }
    let fallback = String(describing: userInfo)
    NSLog("[AppDelegate][push][%@] %@", source, fallback)
    writeToPeerlinkAppLog("[push][\(source)] \(fallback)")
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      granted, error in
      if let error = error {
        NSLog("[AppDelegate] Notification permission request error: %@", error.localizedDescription)
        return
      }
      NSLog("[AppDelegate] Notification permission granted: %d", granted)
    }

    if let flutterController = window?.rootViewController {
      DeepLinkChannel.shared.configure(rootViewController: flutterController)
      VoipCallBridge.shared.configure(rootViewController: flutterController)
      MediaGalleryChannel.shared.configure(rootViewController: flutterController)
      MediaThumbnailChannel.shared.configure(rootViewController: flutterController)
    }
    if let registrar = self.registrar(forPlugin: "PushPayloadBridge") {
      PushPayloadBridge.shared.configure(registrar: registrar)
    } else {
      writeToPeerlinkAppLog("[push][bridge] registrar missing")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if DeepLinkChannel.shared.handle(url: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = userActivity.webpageURL,
      DeepLinkChannel.shared.handle(url: url)
    {
      return true
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    logRemoteNotificationPayload(
      notification.request.content.userInfo,
      source: "willPresent",
      notifyFlutter: true
    )
    completionHandler([])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    logRemoteNotificationPayload(response.notification.request.content.userInfo, source: "didReceiveResponse")
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    logRemoteNotificationPayload(userInfo, source: "didReceiveRemoteNotification")
    super.application(
      application,
      didReceiveRemoteNotification: userInfo,
      fetchCompletionHandler: completionHandler
    )
  }
}
