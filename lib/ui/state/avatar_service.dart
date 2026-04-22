import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/messaging/reliable_messaging_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/runtime/storage_service.dart';

class AvatarService {
  static const String _settingsKey = 'peer_avatars_v1';
  static const String _localAvatarPathKey = 'local_avatar_path_v1';
  static const String _localAvatarUpdatedAtKey = 'local_avatar_updated_at_ms_v1';
  static const String _localAvatarBytesB64Key = 'local_avatar_bytes_b64_v1';
  static const String _localAvatarMimeTypeKey = 'local_avatar_mime_type_v1';
  static const int _maxAvatarBytes = 1024 * 1024;

  final NodeFacade facade;
  final StorageService storage;
  final StreamController<String> _updatesController =
      StreamController<String>.broadcast();
  final Map<String, _AvatarRecord> _peerAvatars = <String, _AvatarRecord>{};

  AvatarService({
    required this.facade,
    required this.storage,
  }) {
    _loadFromStorage();
    unawaited(_bootstrapSync());
  }

  Stream<String> get updatesStream => _updatesController.stream;

  String? avatarPathForPeer(String peerId) => _peerAvatars[peerId]?.path;

  List<String> activeManagedAvatarPaths() {
    return _peerAvatars.values
        .map((entry) => entry.path.trim())
        .where((path) => path.isNotEmpty && storage.isManagedMediaPath(path))
        .toList(growable: false);
  }

  Future<void> clearAllAvatarMedia() async {
    final settings = storage.getSettings();
    final entries = List<MapEntry<String, _AvatarRecord>>.from(_peerAvatars.entries);
    for (final entry in entries) {
      if (storage.isManagedMediaPath(entry.value.path)) {
        await storage.deleteMediaFile(entry.value.path);
      }
    }
    _peerAvatars.clear();
    await settings.delete(_localAvatarPathKey);
    await settings.delete(_localAvatarUpdatedAtKey);
    await settings.delete(_localAvatarBytesB64Key);
    await settings.delete(_localAvatarMimeTypeKey);
    await settings.delete(_settingsKey);
    _updatesController.add(facade.peerId);
  }

  String? get localAvatarPath => avatarPathForPeer(facade.peerId);

  Future<void> setLocalAvatar(Uint8List bytes, {String mimeType = 'image/png'}) async {
    if (bytes.isEmpty) {
      return;
    }
    if (bytes.length > _maxAvatarBytes) {
      throw StateError('Avatar image is too large (${bytes.length} bytes)');
    }

    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final path = await storage.saveMediaBytes(
      peerId: '_avatars',
      messageId: '${facade.peerId}_$updatedAtMs',
      fileName: 'avatar_${_safeMimeExt(mimeType)}',
      bytes: bytes,
    );
    if (path.isEmpty) {
      throw StateError('Failed to save avatar image');
    }

    final previous = _peerAvatars[facade.peerId];
    if (previous != null &&
        previous.path.isNotEmpty &&
        previous.path != path) {
      await storage.deleteMediaFile(previous.path);
    }

    _peerAvatars[facade.peerId] = _AvatarRecord(
      path: path,
      updatedAtMs: updatedAtMs,
    );
    final settings = storage.getSettings();
    await settings.put(_localAvatarBytesB64Key, base64Encode(bytes));
    await settings.put(_localAvatarMimeTypeKey, mimeType);
    await _persist();
    _updatesController.add(facade.peerId);

    await broadcastLocalAvatarToKnownPeers(
      mimeType: mimeType,
      bytes: bytes,
      updatedAtMs: updatedAtMs,
    );
  }

  Future<void> clearLocalAvatar() async {
    final current = _peerAvatars[facade.peerId];
    if (current == null) {
      return;
    }
    if (current.path.isNotEmpty) {
      await storage.deleteMediaFile(current.path);
    }
    _peerAvatars.remove(facade.peerId);
    final settings = storage.getSettings();
    await settings.delete(_localAvatarBytesB64Key);
    await settings.delete(_localAvatarMimeTypeKey);
    await _persist();
    _updatesController.add(facade.peerId);
    await _broadcastLocalAvatarRemoval();
  }

  Future<void> broadcastLocalAvatarToKnownPeers({
    required String mimeType,
    required Uint8List bytes,
    required int updatedAtMs,
  }) async {
    final recipients = await _knownPeerIds();
    await _announceLocalAvatarToRecipients(
      recipients: recipients,
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: updatedAtMs,
    );
  }

  Future<void> handleIncomingAvatarAnnouncement(
    String senderPeerId,
    String payloadRaw,
  ) async {
    final sender = senderPeerId.trim();
    if (sender.isEmpty) {
      return;
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(payloadRaw);
      if (decoded is! Map) {
        return;
      }
      payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final blobId = (payload['blobId'] as String? ?? '').trim();
    final mimeType = (payload['mimeType'] as String? ?? 'image/png').trim();
    final updatedAtMs = payload['updatedAtMs'] is int
        ? payload['updatedAtMs'] as int
        : int.tryParse('${payload['updatedAtMs']}') ?? 0;
    if (blobId.isEmpty || updatedAtMs <= 0) {
      return;
    }

    final current = _peerAvatars[sender];
    if (current != null && current.updatedAtMs >= updatedAtMs) {
      return;
    }

    try {
      final blob = await facade.downloadBlob(blobId);
      if (blob.payload.isEmpty || blob.payload.length > _maxAvatarBytes) {
        return;
      }
      final filePath = await storage.saveMediaBytes(
        peerId: '_avatars',
        messageId: '${sender}_$updatedAtMs',
        fileName: 'avatar_$sender.${_safeMimeExt(mimeType)}',
        bytes: blob.payload,
      );
      if (filePath.isEmpty) {
        return;
      }

      if (current != null &&
          current.path.isNotEmpty &&
          current.path != filePath) {
        await storage.deleteMediaFile(current.path);
      }

      _peerAvatars[sender] = _AvatarRecord(
        path: filePath,
        updatedAtMs: updatedAtMs,
        mimeType: mimeType,
        embeddedBytesBase64: base64Encode(blob.payload),
      );
      await _persist();
      _updatesController.add(sender);
    } catch (_) {
      // Ignore transient network/download errors.
    }
  }

  Future<void> handleIncomingAvatarRemoval(
    String senderPeerId,
    String payloadRaw,
  ) async {
    final sender = senderPeerId.trim();
    if (sender.isEmpty) {
      return;
    }
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(payloadRaw);
      if (decoded is! Map) {
        return;
      }
      payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final updatedAtMs = payload['updatedAtMs'] is int
        ? payload['updatedAtMs'] as int
        : int.tryParse('${payload['updatedAtMs']}') ?? 0;
    if (updatedAtMs <= 0) {
      return;
    }
    final current = _peerAvatars[sender];
    if (current == null) {
      return;
    }
    if (current.updatedAtMs > updatedAtMs) {
      return;
    }
    if (current.path.isNotEmpty) {
      await storage.deleteMediaFile(current.path);
    }
    _peerAvatars.remove(sender);
    await _persist();
    _updatesController.add(sender);
  }

  Future<void> handleIncomingAvatarQuery(
    String senderPeerId,
    String payloadRaw,
  ) async {
    final sender = senderPeerId.trim();
    if (sender.isEmpty || sender == facade.peerId) {
      return;
    }
    try {
      final decoded = jsonDecode(payloadRaw);
      if (decoded is! Map) {
        return;
      }
    } catch (_) {
      return;
    }

    final local = _peerAvatars[facade.peerId];
    if (local == null) {
      return;
    }
    final settings = storage.getSettings();
    final encoded = settings.get(_localAvatarBytesB64Key) as String?;
    if (encoded == null || encoded.isEmpty) {
      return;
    }
    Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      return;
    }
    if (bytes.isEmpty || bytes.length > _maxAvatarBytes) {
      return;
    }
    final mimeType = (settings.get(_localAvatarMimeTypeKey) as String?) ?? 'image/png';
    await _announceLocalAvatarToRecipients(
      recipients: <String>[sender],
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: local.updatedAtMs,
    );
  }

  Future<void> dispose() async {
    await _updatesController.close();
  }

  Future<List<String>> _knownPeerIds() async {
    final peers = <String>{};
    final contactKeys = List<Object?>.from(storage.getContacts().keys);

    for (final key in contactKeys) {
      final normalized = '$key'.trim();
      if (normalized.isNotEmpty) {
        peers.add(normalized);
      }
    }

    final summaries = await storage.loadAllChatSummaries();
    for (final raw in summaries) {
      final peerId = (raw['peerId'] as String? ?? '').trim();
      final isGroup = raw['isGroup'] == true || peerId.startsWith('group:');
      if (peerId.isNotEmpty && !isGroup && peerId != facade.peerId) {
        peers.add(peerId);
      }
      final rawMembers = raw['memberPeerIds'];
      if (rawMembers is List) {
        for (final item in rawMembers) {
          if (item is String && item.trim().isNotEmpty && item.trim() != facade.peerId) {
            peers.add(item.trim());
          }
        }
      }
    }

    peers.remove(facade.peerId);
    return peers.toList(growable: false);
  }

  Future<void> _broadcastLocalAvatarRemoval() async {
    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode(<String, dynamic>{
      'type': 'avatar_remove',
      'v': 1,
      'updatedAtMs': updatedAtMs,
    });
    final recipients = await _knownPeerIds();
    for (final peerId in recipients) {
      try {
        await facade.sendControlMessage(
          peerId,
          kind: 'profileAvatarRemove',
          text: payload,
        );
      } catch (_) {
        // best effort
      }
    }
  }

  Future<void> _bootstrapSync() async {
    await _recoverLocalAvatarFromEmbedded();
    await _recoverPeerAvatarsFromEmbedded();
    await _requestMissingPeerAvatars();
  }

  Future<void> _recoverLocalAvatarFromEmbedded() async {
    final local = _peerAvatars[facade.peerId];
    if (local != null && local.path.isNotEmpty && File(local.path).existsSync()) {
      return;
    }

    final settings = storage.getSettings();
    final encoded = settings.get(_localAvatarBytesB64Key) as String?;
    if (encoded == null || encoded.isEmpty) {
      return;
    }
    Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      return;
    }
    if (bytes.isEmpty || bytes.length > _maxAvatarBytes) {
      return;
    }
    final mimeType = (settings.get(_localAvatarMimeTypeKey) as String?) ?? 'image/png';
    final updatedRaw = settings.get(_localAvatarUpdatedAtKey);
    final updatedAtMs = updatedRaw is int
        ? updatedRaw
        : int.tryParse('${updatedRaw ?? 0}') ?? DateTime.now().millisecondsSinceEpoch;
    final path = await storage.saveMediaBytes(
      peerId: '_avatars',
      messageId: '${facade.peerId}_$updatedAtMs',
      fileName: 'avatar_${_safeMimeExt(mimeType)}',
      bytes: bytes,
    );
    if (path.isEmpty) {
      return;
    }
    _peerAvatars[facade.peerId] = _AvatarRecord(
      path: path,
      updatedAtMs: updatedAtMs,
    );
    await _persist();
    _updatesController.add(facade.peerId);
  }

  Future<void> _recoverPeerAvatarsFromEmbedded() async {
    final peerIds = List<String>.from(_peerAvatars.keys);
    for (final peerId in peerIds) {
      if (peerId == facade.peerId) {
        continue;
      }
      final record = _peerAvatars[peerId];
      if (record == null) {
        continue;
      }
      if (record.path.isNotEmpty && File(record.path).existsSync()) {
        continue;
      }
      final encoded = record.embeddedBytesBase64;
      if (encoded == null || encoded.isEmpty) {
        continue;
      }
      Uint8List bytes;
      try {
        bytes = base64Decode(encoded);
      } catch (_) {
        continue;
      }
      if (bytes.isEmpty || bytes.length > _maxAvatarBytes) {
        continue;
      }
      final mimeType = (record.mimeType == null || record.mimeType!.isEmpty)
          ? 'image/png'
          : record.mimeType!;
      final restoredPath = await storage.saveMediaBytes(
        peerId: '_avatars',
        messageId: '${peerId}_${record.updatedAtMs}',
        fileName: 'avatar_$peerId.${_safeMimeExt(mimeType)}',
        bytes: bytes,
      );
      if (restoredPath.isEmpty) {
        continue;
      }
      _peerAvatars[peerId] = record.copyWith(path: restoredPath);
      _updatesController.add(peerId);
    }
    await _persist();
  }

  Future<void> _requestMissingPeerAvatars() async {
    final payload = jsonEncode(<String, dynamic>{
      'type': 'avatar_query',
      'v': 1,
      'requestedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    final peers = await _knownPeerIds();
    for (final peerId in peers) {
      final record = _peerAvatars[peerId];
      if (record != null &&
          record.path.isNotEmpty &&
          File(record.path).existsSync()) {
        continue;
      }
      try {
        await facade.sendControlMessage(
          peerId,
          kind: 'profileAvatarQuery',
          text: payload,
        );
      } catch (_) {
        // Best effort.
      }
    }
  }

  Future<void> _announceLocalAvatarToRecipients({
    required List<String> recipients,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  }) async {
    if (recipients.isEmpty) {
      return;
    }
    final blobId = await facade.uploadBlob(
      scopeKind: RelayBlobScopeKind.group,
      targetId: 'profile:${facade.peerId}',
      fileName: 'avatar_${facade.peerId}_$updatedAtMs.${_safeMimeExt(mimeType)}',
      mimeType: mimeType,
      bytes: bytes,
      blobId: 'avatar:${facade.peerId}:$updatedAtMs',
    );

    final payload = jsonEncode(<String, dynamic>{
      'type': 'avatar_announce',
      'v': 1,
      'blobId': blobId,
      'mimeType': mimeType,
      'updatedAtMs': updatedAtMs,
      'sizeBytes': bytes.length,
    });

    for (final peerId in recipients) {
      try {
        await facade.sendControlMessage(
          peerId,
          kind: 'profileAvatar',
          text: payload,
        );
      } catch (_) {
        // Best effort; relay will deliver when peer is online.
      }
    }
  }

  void _loadFromStorage() {
    final settings = storage.getSettings();
    final localPath = settings.get(_localAvatarPathKey) as String?;
    final localUpdated = settings.get(_localAvatarUpdatedAtKey);
    final localUpdatedAtMs = localUpdated is int
        ? localUpdated
        : int.tryParse('${localUpdated ?? 0}') ?? 0;
    if (localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync()) {
      _peerAvatars[facade.peerId] = _AvatarRecord(
        path: localPath,
        updatedAtMs: localUpdatedAtMs,
      );
    }

    final raw = settings.get(_settingsKey);
    if (raw is! Map) {
      return;
    }
    for (final entry in raw.entries) {
      final peerId = '${entry.key}'.trim();
      if (peerId.isEmpty) {
        continue;
      }
      final value = entry.value;
      if (value is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(value);
      final path = (map['path'] as String? ?? '').trim();
      final updatedRaw = map['updatedAtMs'];
      final updatedAtMs = updatedRaw is int
          ? updatedRaw
          : int.tryParse('${updatedRaw ?? 0}') ?? 0;
      final mimeType = (map['mimeType'] as String?)?.trim();
      final embeddedBytesBase64 = (map['embeddedBytesBase64'] as String?)?.trim();
      final hasFile = path.isNotEmpty && File(path).existsSync();
      final hasEmbedded = embeddedBytesBase64 != null && embeddedBytesBase64.isNotEmpty;
      if (!hasFile && !hasEmbedded) {
        continue;
      }
      _peerAvatars[peerId] = _AvatarRecord(
        path: hasFile ? path : '',
        updatedAtMs: updatedAtMs,
        mimeType: mimeType,
        embeddedBytesBase64: embeddedBytesBase64,
      );
    }
  }

  Future<void> _persist() async {
    final settings = storage.getSettings();
    final local = _peerAvatars[facade.peerId];
    if (local == null) {
      await settings.delete(_localAvatarPathKey);
      await settings.delete(_localAvatarUpdatedAtKey);
    } else {
      await settings.put(_localAvatarPathKey, local.path);
      await settings.put(_localAvatarUpdatedAtKey, local.updatedAtMs);
    }

    final map = <String, dynamic>{};
    final entries =
        List<MapEntry<String, _AvatarRecord>>.from(_peerAvatars.entries);
    for (final entry in entries) {
      if (entry.key == facade.peerId) {
        continue;
      }
      map[entry.key] = <String, dynamic>{
        'path': entry.value.path,
        'updatedAtMs': entry.value.updatedAtMs,
        'mimeType': entry.value.mimeType,
        'embeddedBytesBase64': entry.value.embeddedBytesBase64,
      };
    }
    await settings.put(_settingsKey, map);
  }

  String _safeMimeExt(String mimeType) {
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('png')) {
      return 'png';
    }
    if (normalized.contains('jpeg') || normalized.contains('jpg')) {
      return 'jpg';
    }
    if (normalized.contains('webp')) {
      return 'webp';
    }
    return 'img';
  }
}

class _AvatarRecord {
  final String path;
  final int updatedAtMs;
  final String? mimeType;
  final String? embeddedBytesBase64;

  const _AvatarRecord({
    required this.path,
    required this.updatedAtMs,
    this.mimeType,
    this.embeddedBytesBase64,
  });

  _AvatarRecord copyWith({
    String? path,
    int? updatedAtMs,
    String? mimeType,
    String? embeddedBytesBase64,
  }) {
    return _AvatarRecord(
      path: path ?? this.path,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      mimeType: mimeType ?? this.mimeType,
      embeddedBytesBase64: embeddedBytesBase64 ?? this.embeddedBytesBase64,
    );
  }
}
