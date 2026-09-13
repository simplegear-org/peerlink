// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/app/invites/invite_manifest_client.dart';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'package:peerlink/core/runtime/server_config_payload.dart';

enum InviteFlowResultType {
  completed,
  duplicate,
  retryableFailure,
  terminalFailure,
}

class InviteFlowResult {
  const InviteFlowResult._({
    required this.type,
    this.peerId,
    this.displayName,
    this.error,
  });

  const InviteFlowResult.completed({
    required String peerId,
    required String displayName,
  }) : this._(
         type: InviteFlowResultType.completed,
         peerId: peerId,
         displayName: displayName,
       );

  const InviteFlowResult.duplicate()
    : this._(type: InviteFlowResultType.duplicate);

  const InviteFlowResult.failure({
    required Object error,
    required bool retryable,
  }) : this._(
         type: retryable
             ? InviteFlowResultType.retryableFailure
             : InviteFlowResultType.terminalFailure,
         error: error,
       );

  final InviteFlowResultType type;
  final String? peerId;
  final String? displayName;
  final Object? error;

  bool get isCompleted => type == InviteFlowResultType.completed;
  bool get isRetryable => type == InviteFlowResultType.retryableFailure;
}

typedef InviteIdentityVerifier =
    Future<bool> Function(
      Map<String, dynamic> bundle, {
      required String expectedPeerId,
    });

typedef InviteContactUpserter =
    Future<void> Function({required String peerId, String? username});

typedef InviteDirectChatEnsurer =
    Future<void> Function({required String peerId, required String name});

typedef PendingInviteTokenLoader = Future<String?> Function();
typedef PendingInviteTokenWriter = Future<void> Function(String token);
typedef InviteDiagnosticLogger = void Function(String event);

/// Emits lifecycle names only: no token, peer ID, manifest, or error details.
class InviteFlowDiagnostics {
  const InviteFlowDiagnostics._();

  static void log(String event) {
    AppFileLogger.log(
      '[invite] event=$event',
      name: 'invite',
      diagnostic: true,
    );
  }
}

class InviteFlowCoordinator {
  InviteFlowCoordinator({
    required String localPeerId,
    required InviteIdentityVerifier verifyIdentity,
    required Future<void> Function() ensureInitialServerConfig,
    required Future<void> Function(ServerConfigPayload config) mergeServers,
    required InviteContactUpserter upsertContact,
    required InviteDirectChatEnsurer ensureDirectChat,
    required void Function(String peerId, String name) openChat,
    required Map<String, dynamic> localIdentityBundle,
    required InviteManifestSigner signInviteManifest,
    required String Function() localUsername,
    required ServerConfigPayload Function() currentServerConfig,
    PendingInviteTokenLoader? loadPendingInviteToken,
    PendingInviteTokenWriter? savePendingInviteToken,
    PendingInviteTokenWriter? clearPendingInviteToken,
    InviteManifestClient? manifestClient,
    InviteDiagnosticLogger? logDiagnostic,
  }) : _localPeerId = localPeerId,
       _verifyIdentity = verifyIdentity,
       _ensureInitialServerConfig = ensureInitialServerConfig,
       _mergeServers = mergeServers,
       _upsertContact = upsertContact,
       _ensureDirectChat = ensureDirectChat,
       _openChat = openChat,
       _localIdentityBundle = localIdentityBundle,
       _signInviteManifest = signInviteManifest,
       _localUsername = localUsername,
       _currentServerConfig = currentServerConfig,
       _loadPendingInviteToken = loadPendingInviteToken,
       _savePendingInviteToken = savePendingInviteToken,
       _clearPendingInviteToken = clearPendingInviteToken,
       _manifestClient = manifestClient ?? InviteManifestClient(),
       _logDiagnostic = logDiagnostic ?? InviteFlowDiagnostics.log;

  final String _localPeerId;
  final InviteIdentityVerifier _verifyIdentity;
  final Future<void> Function() _ensureInitialServerConfig;
  final Future<void> Function(ServerConfigPayload config) _mergeServers;
  final InviteContactUpserter _upsertContact;
  final InviteDirectChatEnsurer _ensureDirectChat;
  final void Function(String peerId, String name) _openChat;
  final Map<String, dynamic> _localIdentityBundle;
  final InviteManifestSigner _signInviteManifest;
  final String Function() _localUsername;
  final ServerConfigPayload Function() _currentServerConfig;
  final PendingInviteTokenLoader? _loadPendingInviteToken;
  final PendingInviteTokenWriter? _savePendingInviteToken;
  final PendingInviteTokenWriter? _clearPendingInviteToken;
  final InviteManifestClient _manifestClient;
  final InviteDiagnosticLogger _logDiagnostic;
  final Set<String> _handledTokens = <String>{};

  Future<String> createInviteUrl() => _manifestClient.create(
    peerId: _localPeerId,
    identityBundle: _localIdentityBundle,
    sign: _signInviteManifest,
    username: _localUsername(),
    servers: _currentServerConfig(),
  );

  Future<InviteFlowResult> handleInviteUrl(Uri uri) async {
    _logDiagnostic('invite_received');
    final segments = uri.pathSegments;
    if (uri.host != 'simplegear.org' ||
        segments.length != 2 ||
        segments.first != 'i') {
      _logDiagnostic('invite_failed_terminal');
      return const InviteFlowResult.failure(
        error: FormatException('Это не short invite PeerLink'),
        retryable: false,
      );
    }
    final token = segments.last;
    if (!_handledTokens.add(token)) {
      _logDiagnostic('invite_duplicate_delivery');
      return const InviteFlowResult.duplicate();
    }
    try {
      _logDiagnostic('invite_resolve_start');
      final invite = await _manifestClient.resolve(token);
      _logDiagnostic('invite_resolve_success');
      if (invite.peerId == _localPeerId) {
        throw const FormatException('Нельзя принять собственное приглашение');
      }
      // Settings initialization owns the existing empty-config bootstrapper.
      _logDiagnostic('default_config_required');
      await _ensureInitialServerConfig();
      _logDiagnostic('default_config_ready');
      await _mergeServers(invite.serverConfig);
      if (_hasCustomServers(invite.serverConfig)) {
        _logDiagnostic('custom_servers_merged');
      }
      final trusted = await _verifyIdentity(
        invite.identityBundleV3,
        expectedPeerId: invite.peerId,
      );
      if (!trusted) {
        throw const FormatException('Identity пригласившего не подтверждена');
      }
      _logDiagnostic('identity_verified');
      _logDiagnostic('username_resolved');
      await _upsertContact(peerId: invite.peerId, username: invite.username);
      _logDiagnostic('contact_ready');
      final name = invite.username ?? invite.peerId;
      await _ensureDirectChat(peerId: invite.peerId, name: name);
      _logDiagnostic('chat_ready');
      _openChat(invite.peerId, name);
      _logDiagnostic('chat_opened');
      await _clearPendingInviteToken?.call(token);
      _logDiagnostic('invite_completed');
      return InviteFlowResult.completed(
        peerId: invite.peerId,
        displayName: name,
      );
    } catch (error) {
      _handledTokens.remove(token);
      final retryable = _isRetryable(error);
      if (retryable) {
        await _savePendingInviteToken?.call(token);
        _logDiagnostic('pending_invite_stored');
      } else {
        await _clearPendingInviteToken?.call(token);
      }
      _logDiagnostic(
        retryable ? 'invite_failed_retryable' : 'invite_failed_terminal',
      );
      return InviteFlowResult.failure(error: error, retryable: retryable);
    }
  }

  /// Replays the only persisted short-token invite after startup or resume.
  Future<InviteFlowResult?> resumePendingInvite() async {
    final token = await _loadPendingInviteToken?.call();
    if (token == null || token.isEmpty) return null;
    _logDiagnostic('pending_invite_resumed');
    return handleInviteUrl(Uri.https('simplegear.org', '/i/$token'));
  }

  bool _hasCustomServers(ServerConfigPayload config) =>
      config.bootstrap.isNotEmpty ||
      config.relay.isNotEmpty ||
      config.turn.isNotEmpty ||
      config.push.isNotEmpty;

  bool _isRetryable(Object error) =>
      error is! FormatException &&
      (error is! InviteResolveException || error.retryable);
}
