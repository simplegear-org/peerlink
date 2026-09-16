// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/server_config_payload.dart';
import 'package:peerlink/features/invites/domain/invite_manifest.dart';

typedef InviteManifestSigner =
    Future<String> Function(Map<String, dynamic> manifest);

class InviteCreateRequest {
  const InviteCreateRequest({
    required this.peerId,
    required this.identityBundle,
    required this.sign,
    this.username,
    this.serverConfig,
  });

  final String peerId;
  final Map<String, dynamic> identityBundle;
  final InviteManifestSigner sign;
  final String? username;
  final ServerConfigPayload? serverConfig;
}

abstract interface class InviteApi {
  Future<InviteManifest> resolve(String token);

  Future<String> create(InviteCreateRequest request);
}

/// Ошибка Invite API с признаком возможности безопасного повторного запроса.
class InviteResolveException implements Exception {
  const InviteResolveException(this.message, {required this.retryable});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}
