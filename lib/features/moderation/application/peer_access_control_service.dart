// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/services.dart';

import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';

import 'access_policy_api.dart';
import 'access_policy_models.dart';

export 'access_policy_models.dart';

class PeerAccessControlService implements AccessPolicyApi {
  static const String allowMessagesOnlyFromContactsKey =
      'peerlink.privacy.allow_messages_only_from_contacts.v1';
  static const String blockedPeersKey = 'peerlink.blocked_peers.v1';
  static const MethodChannel _nativeChannel = MethodChannel(
    'peerlink/access_control/methods',
  );

  final SecureStorageBox settingsBox;
  final ContactsRepository contactsRepository;

  const PeerAccessControlService({
    required this.settingsBox,
    required this.contactsRepository,
  });

  factory PeerAccessControlService.forStorage(StorageService storage) {
    return PeerAccessControlService(
      settingsBox: storage.getSettings(),
      contactsRepository: ContactsRepository(storage: storage),
    );
  }

  @override
  bool get allowMessagesOnlyFromContacts {
    final raw = settingsBox.get(allowMessagesOnlyFromContactsKey);
    if (raw is bool) {
      return raw;
    }
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'false') {
        return false;
      }
      if (normalized == 'true') {
        return true;
      }
    }
    return true;
  }

  @override
  Future<void> setAllowMessagesOnlyFromContacts(bool enabled) {
    return settingsBox.put(allowMessagesOnlyFromContactsKey, enabled);
  }

  @override
  List<BlockedPeer> blockedPeers() {
    final raw = settingsBox.get(blockedPeersKey);
    if (raw is! List) {
      return const <BlockedPeer>[];
    }
    final result = <BlockedPeer>[];
    for (final item in raw.whereType<Map>()) {
      final blocked = BlockedPeer.fromJson(Map<String, dynamic>.from(item));
      if (blocked.peerId.isNotEmpty) {
        result.add(blocked);
      }
    }
    result.sort((a, b) => b.blockedAt.compareTo(a.blockedAt));
    return result;
  }

  @override
  bool isBlocked(String peerId) {
    final normalized = peerId.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return blockedPeers().any((peer) => peer.peerId == normalized);
  }

  @override
  Future<void> blockPeer(String peerId, {String? reason}) async {
    final normalized = peerId.trim();
    if (normalized.isEmpty) {
      return;
    }
    final peers = blockedPeers()
        .where((peer) => peer.peerId != normalized)
        .toList(growable: true);
    peers.insert(
      0,
      BlockedPeer(
        peerId: normalized,
        blockedAt: DateTime.now().toUtc(),
        reason: reason?.trim(),
      ),
    );
    await settingsBox.put(
      blockedPeersKey,
      peers.map((peer) => peer.toJson()).toList(growable: false),
    );
    await _syncNativeBlockedPeers(peers);
  }

  @override
  Future<void> unblockPeer(String peerId) async {
    final normalized = peerId.trim();
    if (normalized.isEmpty) {
      return;
    }
    final peers = blockedPeers()
        .where((peer) => peer.peerId != normalized)
        .toList(growable: false);
    await settingsBox.put(
      blockedPeersKey,
      peers.map((peer) => peer.toJson()).toList(growable: false),
    );
    await _syncNativeBlockedPeers(peers);
  }

  @override
  IncomingInteractionDecision evaluateIncoming({
    required String peerId,
    required IncomingInteractionType type,
  }) {
    final normalized = peerId.trim();
    if (normalized.isEmpty) {
      return IncomingInteractionDecision.allow;
    }
    if (isBlocked(normalized)) {
      return IncomingInteractionDecision.blockedPeer;
    }
    if (_requiresKnownContact(type) &&
        allowMessagesOnlyFromContacts &&
        !contactsRepository.contains(normalized)) {
      return IncomingInteractionDecision.contactsOnly;
    }
    return IncomingInteractionDecision.allow;
  }

  @override
  IncomingInteractionDecision evaluateOutgoing({
    required String peerId,
    required IncomingInteractionType type,
  }) {
    final normalized = peerId.trim();
    if (normalized.isEmpty) {
      return IncomingInteractionDecision.allow;
    }
    if (isBlocked(normalized)) {
      return IncomingInteractionDecision.blockedPeer;
    }
    return IncomingInteractionDecision.allow;
  }

  bool _requiresKnownContact(IncomingInteractionType type) {
    switch (type) {
      case IncomingInteractionType.directMessage:
      case IncomingInteractionType.directMedia:
      case IncomingInteractionType.profile:
      case IncomingInteractionType.accountPairing:
      case IncomingInteractionType.groupInvite:
      case IncomingInteractionType.call:
      case IncomingInteractionType.push:
      case IncomingInteractionType.invite:
        return true;
      case IncomingInteractionType.messageReceipt:
      case IncomingInteractionType.groupControl:
      case IncomingInteractionType.groupContent:
        return false;
    }
  }

  Future<void> _syncNativeBlockedPeers(List<BlockedPeer> peers) async {
    try {
      await _nativeChannel.invokeMethod<void>('syncBlockedPeers', <String>[
        for (final peer in peers) peer.peerId,
      ]);
    } catch (_) {
      // Native sync is best-effort; Dart access checks remain authoritative.
    }
  }
}
