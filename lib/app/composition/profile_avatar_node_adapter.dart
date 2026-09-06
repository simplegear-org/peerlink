// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/relay/relay_models.dart';
import 'package:peerlink/features/profile/application/profile_avatar_transport.dart';

class ProfileAvatarNodeAdapter implements ProfileAvatarTransport {
  final NodeFacade _facade;

  const ProfileAvatarNodeAdapter(this._facade);

  @override
  String get peerId => _facade.peerId;

  @override
  Future<String> uploadBlob({
    required RelayBlobScopeKind scopeKind,
    required String targetId,
    required String fileName,
    required String? mimeType,
    required Uint8List bytes,
    String? blobId,
  }) {
    return _facade.uploadBlob(
      scopeKind: scopeKind,
      targetId: targetId,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      blobId: blobId,
    );
  }

  @override
  Future<RelayBlobDownload> downloadBlob(String blobId) {
    return _facade.downloadBlob(blobId);
  }

  @override
  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) {
    return _facade.sendControlMessage(peerId, kind: kind, text: text);
  }
}
