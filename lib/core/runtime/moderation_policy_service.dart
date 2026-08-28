// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'storage_service.dart';

enum ModerationPolicyState {
  clear,
  warning,
  banned;

  static ModerationPolicyState fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'warning':
      case 'warned':
        return ModerationPolicyState.warning;
      case 'banned':
      case 'ban':
        return ModerationPolicyState.banned;
      default:
        return ModerationPolicyState.clear;
    }
  }
}

class ModerationPolicySnapshot {
  final ModerationPolicyState state;
  final String message;
  final String messageKey;
  final int reportCount;
  final int reporterCount;
  final Map<String, dynamic>? signedStatus;
  final DateTime updatedAt;
  final bool appealSubmitted;
  final String warningAcknowledgedKey;

  const ModerationPolicySnapshot({
    required this.state,
    required this.message,
    required this.messageKey,
    required this.reportCount,
    required this.reporterCount,
    required this.signedStatus,
    required this.updatedAt,
    this.appealSubmitted = false,
    this.warningAcknowledgedKey = '',
  });

  bool get isBanned => state == ModerationPolicyState.banned;
  bool get isWarning => state == ModerationPolicyState.warning;
  String get warningNoticeKey => noticeKeyFor(
    state: state,
    reportCount: reportCount,
    reporterCount: reporterCount,
  );
  bool get shouldShowRestrictionScreen => isBanned && !appealSubmitted;
  bool get shouldShowWarningScreen =>
      isWarning && warningAcknowledgedKey != warningNoticeKey;
  bool get restrictsOutgoingCommunication => isBanned;

  static String noticeKeyFor({
    required ModerationPolicyState state,
    required int reportCount,
    required int reporterCount,
  }) => '${state.name}|$reportCount|$reporterCount';

  ModerationPolicySnapshot copyWith({
    ModerationPolicyState? state,
    String? message,
    String? messageKey,
    int? reportCount,
    int? reporterCount,
    Map<String, dynamic>? signedStatus,
    DateTime? updatedAt,
    bool? appealSubmitted,
    String? warningAcknowledgedKey,
  }) {
    return ModerationPolicySnapshot(
      state: state ?? this.state,
      message: message ?? this.message,
      messageKey: messageKey ?? this.messageKey,
      reportCount: reportCount ?? this.reportCount,
      reporterCount: reporterCount ?? this.reporterCount,
      signedStatus: signedStatus ?? this.signedStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      appealSubmitted: appealSubmitted ?? this.appealSubmitted,
      warningAcknowledgedKey:
          warningAcknowledgedKey ?? this.warningAcknowledgedKey,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'state': state.name,
      'message': message,
      'messageKey': messageKey,
      'reportCount': reportCount,
      'reporterCount': reporterCount,
      if (signedStatus != null) 'signedStatus': signedStatus,
      'updatedAt': updatedAt.toIso8601String(),
      'appealSubmitted': appealSubmitted,
      'warningAcknowledgedKey': warningAcknowledgedKey,
    };
  }

  static ModerationPolicySnapshot clear() {
    return ModerationPolicySnapshot(
      state: ModerationPolicyState.clear,
      message: '',
      messageKey: '',
      reportCount: 0,
      reporterCount: 0,
      signedStatus: null,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      appealSubmitted: false,
      warningAcknowledgedKey: '',
    );
  }

  static ModerationPolicySnapshot fromJson(Map<String, dynamic> json) {
    final signedStatus = json['signedStatus'];
    return ModerationPolicySnapshot(
      state: ModerationPolicyState.fromString(json['state']?.toString()),
      message: json['message']?.toString().trim() ?? '',
      messageKey: json['messageKey']?.toString().trim() ?? '',
      reportCount: _readInt(json['reportCount']),
      reporterCount: _readInt(json['reporterCount']),
      signedStatus: signedStatus is Map
          ? signedStatus.map((key, value) => MapEntry(key.toString(), value))
          : null,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appealSubmitted: json['appealSubmitted'] == true,
      warningAcknowledgedKey: json['warningAcknowledgedKey']?.toString() ?? '',
    );
  }

  static int _readInt(Object? raw) {
    if (raw is int) {
      return raw < 0 ? 0 : raw;
    }
    final parsed = int.tryParse(raw?.toString().trim() ?? '');
    if (parsed == null || parsed < 0) {
      return 0;
    }
    return parsed;
  }
}

class ModerationPolicyService {
  static const storageKey = 'peerlink.moderation.policy.v1';
  static const _trustedSigningPublicKeyDefine = String.fromEnvironment(
    'MODERATION_STATUS_SIGNING_PUBLIC_KEY',
  );
  static const _signedStatusSchema = 'peerlink_moderation_status_v1';

  final SecureStorageBox settingsBox;
  final String trustedSigningPublicKey;
  final Ed25519 _ed25519;

  ModerationPolicyService({
    required this.settingsBox,
    String trustedSigningPublicKey = _trustedSigningPublicKeyDefine,
    Ed25519? ed25519,
  }) : trustedSigningPublicKey = trustedSigningPublicKey.trim(),
       _ed25519 = ed25519 ?? Ed25519();

  factory ModerationPolicyService.forStorage(StorageService storage) {
    return ModerationPolicyService(settingsBox: storage.getSettings());
  }

  ModerationPolicySnapshot load() {
    final raw = settingsBox.get(storageKey);
    if (raw is Map) {
      return ModerationPolicySnapshot.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return ModerationPolicySnapshot.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      } catch (_) {}
    }
    return ModerationPolicySnapshot.clear();
  }

  bool get isBanned => load().isBanned;

  Future<ModerationPolicySnapshot> markAppealSubmitted() async {
    final snapshot = load().copyWith(
      appealSubmitted: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await settingsBox.put(storageKey, snapshot.toJson());
    return snapshot;
  }

  Future<ModerationPolicySnapshot> markWarningAcknowledged() async {
    final current = load();
    final snapshot = current.copyWith(
      warningAcknowledgedKey: current.warningNoticeKey,
      updatedAt: DateTime.now().toUtc(),
    );
    await settingsBox.put(storageKey, snapshot.toJson());
    return snapshot;
  }

  Future<ModerationPolicySnapshot?> applyPushPayload(
    Map<String, dynamic> payload, {
    String? expectedPeerId,
  }) async {
    final type = _readString(payload, 'type')?.toLowerCase();
    if (type != 'moderation_policy') {
      return null;
    }
    final state = ModerationPolicyState.fromString(
      _readString(payload, 'policyState') ?? _readString(payload, 'action'),
    );
    final signedStatus = _decodeMap(payload['signedStatus']);
    final current = load();
    final reportCount = ModerationPolicySnapshot._readInt(
      payload['reportCount'],
    );
    final reporterCount = ModerationPolicySnapshot._readInt(
      payload['reporterCount'],
    );
    if (!await _isTrustedSignedStatus(
      signedStatus,
      expectedPeerId: expectedPeerId ?? _readString(payload, 'peerId'),
      state: state,
      reportCount: reportCount,
    )) {
      return null;
    }
    final noticeKey = ModerationPolicySnapshot.noticeKeyFor(
      state: state,
      reportCount: reportCount,
      reporterCount: reporterCount,
    );
    final snapshot = ModerationPolicySnapshot(
      state: state,
      message: _readString(payload, 'message') ?? '',
      messageKey: _readString(payload, 'messageKey') ?? '',
      reportCount: reportCount,
      reporterCount: reporterCount,
      signedStatus: signedStatus,
      updatedAt: DateTime.now().toUtc(),
      appealSubmitted:
          state == ModerationPolicyState.banned &&
          current.isBanned &&
          current.appealSubmitted &&
          current.warningNoticeKey == noticeKey,
      warningAcknowledgedKey: state == ModerationPolicyState.warning
          ? current.warningAcknowledgedKey
          : '',
    );
    await settingsBox.put(storageKey, snapshot.toJson());
    return snapshot;
  }

  Future<bool> _isTrustedSignedStatus(
    Map<String, dynamic>? signedStatus, {
    required String? expectedPeerId,
    required ModerationPolicyState state,
    required int reportCount,
  }) async {
    if (trustedSigningPublicKey.isEmpty && signedStatus == null) {
      return true;
    }
    if (signedStatus == null) {
      return false;
    }
    final schema = _readString(signedStatus, 'schema');
    final peerId = _readString(signedStatus, 'peerId') ?? '';
    final policyState = _readString(signedStatus, 'policyState') ?? 'clear';
    final signingPub = _readString(signedStatus, 'signingPub');
    final sig = _readString(signedStatus, 'sig');
    if (schema != _signedStatusSchema ||
        signingPub == null ||
        sig == null ||
        policyState != state.name ||
        ModerationPolicySnapshot._readInt(signedStatus['reportCount']) !=
            reportCount) {
      return false;
    }
    final normalizedExpectedPeerId = expectedPeerId?.trim();
    if (normalizedExpectedPeerId != null &&
        normalizedExpectedPeerId.isNotEmpty &&
        peerId != normalizedExpectedPeerId) {
      return false;
    }
    if (trustedSigningPublicKey.isNotEmpty &&
        signingPub != trustedSigningPublicKey) {
      return false;
    }
    try {
      final payload = <String>[
        _signedStatusSchema,
        peerId,
        policyState,
        ModerationPolicySnapshot._readInt(
          signedStatus['reportCount'],
        ).toString(),
        _readString(signedStatus, 'warningIssuedAt') ?? '',
        _readString(signedStatus, 'bannedAt') ?? '',
        _readString(signedStatus, 'issuedAt') ?? '',
      ].join('|');
      final publicKey = SimplePublicKey(
        base64Decode(signingPub),
        type: KeyPairType.ed25519,
      );
      return _ed25519.verify(
        Uint8List.fromList(utf8.encode(payload)),
        signature: Signature(base64Decode(sig), publicKey: publicKey),
      );
    } catch (_) {
      return false;
    }
  }

  static String? _readString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static Map<String, dynamic>? _decodeMap(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    return null;
  }
}
