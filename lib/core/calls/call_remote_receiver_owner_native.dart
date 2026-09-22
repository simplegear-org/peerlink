// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
// flutter_webrtc does not export receiver ownership through webrtc_interface.
// Confine this dependency on the pinned plugin to this native-only adapter.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';

// Keep the plugin-specific receiver identity at the calls infrastructure seam.
// Android resolves explicit renderer track IDs within this peer connection.
String? remoteReceiverOwner(MediaStreamTrack? track) {
  if (defaultTargetPlatform != TargetPlatform.android ||
      track is! MediaStreamTrackNative) {
    return null;
  }
  final owner = track.peerConnectionId;
  return owner.isEmpty || owner == 'local' ? null : owner;
}
