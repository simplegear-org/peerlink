// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/core/relay/relay_models.dart';

abstract class ProfileTransport {
  String get peerId;

  Future<String> uploadBlob({
    required RelayBlobScopeKind scopeKind,
    required String targetId,
    required String fileName,
    required String? mimeType,
    required Uint8List bytes,
    String? blobId,
  });

  Future<RelayBlobDownload> downloadBlob(String blobId);

  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
  });
}
