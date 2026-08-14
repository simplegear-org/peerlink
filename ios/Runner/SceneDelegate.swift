// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    DeepLinkChannel.shared.configure(rootViewController: window?.rootViewController)
    VoipCallBridge.shared.configure(rootViewController: window?.rootViewController)
    MediaGalleryChannel.shared.configure(rootViewController: window?.rootViewController)
    if let urlContext = connectionOptions.urlContexts.first {
      _ = DeepLinkChannel.shared.handle(url: urlContext.url)
    }
    if let activity = connectionOptions.userActivities.first,
       activity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = activity.webpageURL {
      _ = DeepLinkChannel.shared.handle(url: url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    DeepLinkChannel.shared.configure(rootViewController: window?.rootViewController)
    VoipCallBridge.shared.configure(rootViewController: window?.rootViewController)
    MediaGalleryChannel.shared.configure(rootViewController: window?.rootViewController)
    for context in URLContexts {
      if DeepLinkChannel.shared.handle(url: context.url) {
        return
      }
    }
    super.scene(scene, openURLContexts: URLContexts)
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    DeepLinkChannel.shared.configure(rootViewController: window?.rootViewController)
    VoipCallBridge.shared.configure(rootViewController: window?.rootViewController)
    MediaGalleryChannel.shared.configure(rootViewController: window?.rootViewController)
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL,
       DeepLinkChannel.shared.handle(url: url) {
      return
    }
    super.scene(scene, continue: userActivity)
  }
}
