// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/services.dart';

import 'contacts_repository.dart';
import 'storage_service.dart';

enum IncomingInteractionType {
  directMessage,
  directMedia,
  messageReceipt,
  profile,
  accountPairing,
  groupInvite,
  groupControl,
  groupContent,
  call,
  push,
  invite,
}

enum IncomingInteractionDecision { allow, blockedPeer, contactsOnly }

class BlockedPeer {
  final String peerId;
  final DateTime blockedAt;
  final String? reason;

  const BlockedPeer({
    required this.peerId,
    required this.blockedAt,
    this.reason,
  });

  factory BlockedPeer.fromJson(Map<String, dynamic> json) {
    final peerId = (json['peerId'] as String? ?? '').trim();
    final blockedAtRaw = (json['blockedAt'] as String? ?? '').trim();
    return BlockedPeer(
      peerId: peerId,
      blockedAt: DateTime.tryParse(blockedAtRaw) ?? DateTime.now(),
      reason: (json['reason'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'peerId': peerId,
    'blockedAt': blockedAt.toIso8601String(),
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
  };
}

class PeerAccessControlService {
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

  Future<void> setAllowMessagesOnlyFromContacts(bool enabled) {
    return settingsBox.put(allowMessagesOnlyFromContactsKey, enabled);
  }

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

  bool isBlocked(String peerId) {
    final normalized = peerId.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return blockedPeers().any((peer) => peer.peerId == normalized);
  }

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
