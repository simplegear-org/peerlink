// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:async';

import 'package:peerlink/features/contacts/application/contact_profile_api.dart';
import 'package:peerlink/features/profile/application/profile_metadata_api.dart';
import 'package:peerlink/features/profile/application/profile_metadata_inbound_handler.dart';
import 'package:peerlink/features/profile/application/peer_profile_api.dart';
import 'package:peerlink/features/profile/application/peer_profile_store.dart';
import 'package:peerlink/features/profile/application/profile_store.dart';
import 'package:peerlink/features/profile/application/profile_peer_metadata_store.dart';
import 'package:peerlink/features/profile/application/profile_transport.dart';
import 'package:peerlink/features/profile/domain/profile.dart';
import 'package:peerlink/features/profile/domain/peer_profile.dart';

/// Owns local display-name persistence and profile username transport.
class ProfileMetadataService
    implements
        ProfileMetadataApi,
        ProfileMetadataInboundHandler,
        PeerProfileApi {
  ProfileMetadataService({
    required ProfileStore store,
    required ProfilePeerMetadataStore peerMetadataStore,
    required PeerProfileStore peerProfiles,
    required ProfileTransport transport,
    required ContactProfileApi contacts,
  }) : _store = store,
       _peerMetadataStore = peerMetadataStore,
       _peerProfiles = peerProfiles,
       _transport = transport,
       _contacts = contacts;

  final ProfileStore _store;
  final ProfilePeerMetadataStore _peerMetadataStore;
  final PeerProfileStore _peerProfiles;
  final ProfileTransport _transport;
  final ContactProfileApi _contacts;

  @override
  String get displayName => _store.profile.displayName;

  @override
  String get about => _store.profile.about;

  @override
  Future<void> updateDisplayName(String value) async {
    final normalized = Profile.normalizeDisplayName(value);
    await _store.save(_store.profile.copyWith(displayName: normalized));
    unawaited(_broadcastProfile());
  }

  @override
  Future<void> updateAbout(String value) async {
    final normalized = Profile.normalizeAbout(value);
    await _store.save(_store.profile.copyWith(about: normalized));
    unawaited(_broadcastProfile());
  }

  @override
  Future<void> sendLocalDisplayNameToPeer(String peerId) async {
    final recipient = peerId.trim();
    if (recipient.isEmpty || recipient == _transport.peerId) return;
    await _sendProfile(recipient);
  }

  Future<void> _broadcastProfile() async {
    for (final peerId in _contacts.knownPeerIds) {
      await _sendProfile(peerId);
    }
  }

  Future<void> _sendProfile(String peerId) async {
    try {
      await _transport.sendControlMessage(
        peerId,
        kind: 'profileUsername',
        text: jsonEncode(<String, dynamic>{
          'type': 'username_update',
          'v': 1,
          'username': displayName,
          'about': about,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {
      // Profile metadata sync is best effort.
    }
  }

  @override
  Future<void> handleIncomingUsernameUpdate(
    String senderPeerId,
    String payloadRaw,
  ) async {
    final sender = senderPeerId.trim();
    if (sender.isEmpty) return;
    try {
      final decoded = jsonDecode(payloadRaw);
      if (decoded is! Map ||
          decoded['type'] != 'username_update' ||
          decoded['v'] != 1) {
        return;
      }
      final username = Profile.normalizeDisplayName(decoded['username']);
      final current = _peerProfiles.profileForPeer(sender);
      final rawAbout = decoded['about'];
      final remoteAbout = rawAbout is String
          ? Profile.normalizeAbout(rawAbout)
          : current?.about ?? '';
      final updatedAtMs = decoded['updatedAtMs'] is int
          ? decoded['updatedAtMs'] as int
          : int.tryParse('${decoded['updatedAtMs']}') ?? 0;
      if (updatedAtMs <= 0 || !_acceptIncomingUpdate(sender, updatedAtMs)) {
        return;
      }
      await _peerProfiles.save(
        PeerProfile(
          peerId: sender,
          displayName: username,
          about: remoteAbout,
          updatedAtMs: updatedAtMs,
        ),
      );
      if (_contacts.hasContact(sender)) {
        await _contacts.applyRemoteUsername(peerId: sender, username: username);
      }
      await _persistUpdatedAt(sender, updatedAtMs);
    } on FormatException {
      // Ignore invalid remote profile metadata.
    } catch (_) {
      // Ignore malformed profile metadata.
    }
  }

  bool _acceptIncomingUpdate(String peerId, int updatedAtMs) {
    return updatedAtMs > _peerMetadataStore.usernameUpdatedAtMs(peerId);
  }

  Future<void> _persistUpdatedAt(String peerId, int updatedAtMs) async {
    await _peerMetadataStore.saveUsernameUpdatedAtMs(peerId, updatedAtMs);
  }

  @override
  PeerProfile? profileForPeer(String peerId) =>
      _peerProfiles.profileForPeer(peerId);
}
