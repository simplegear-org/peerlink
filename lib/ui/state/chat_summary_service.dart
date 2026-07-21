import '../../core/runtime/storage_service.dart';
import '../models/chat.dart';

class ChatSummaryService {
  static const String groupMetaStorageKey = 'state.v1';
  static const String legacyGroupMetaStorageKey = 'peerlink.group_meta.v1';

  final StorageService storage;
  final SecureStorageBox settingsBox;
  final SecureStorageBox groupMetaBox;
  final Map<String, Map<String, dynamic>> _groupMetaByGroupId =
      <String, Map<String, dynamic>>{};

  ChatSummaryService({
    required this.storage,
    required this.settingsBox,
    required this.groupMetaBox,
  });

  void loadGroupMetaFromSettings() {
    _groupMetaByGroupId.clear();
    final raw =
        groupMetaBox.get(groupMetaStorageKey) ??
        settingsBox.get(legacyGroupMetaStorageKey);
    if (raw is! Map) {
      return;
    }
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.trim().isEmpty) {
        continue;
      }
      if (value is Map<String, dynamic>) {
        _groupMetaByGroupId[key] = Map<String, dynamic>.from(value);
      } else if (value is Map) {
        _groupMetaByGroupId[key] = Map<String, dynamic>.from(value);
      }
    }
  }

  Future<void> persistGroupMetaToSettings() async {
    await groupMetaBox.put(
      groupMetaStorageKey,
      Map<String, dynamic>.from(_groupMetaByGroupId),
    );
  }

  bool isGroupDeleted(String groupId) {
    final rawDeletedAt = _groupMetaByGroupId[groupId]?['deletedAtMs'];
    if (rawDeletedAt is int) {
      return rawDeletedAt > 0;
    }
    if (rawDeletedAt is num) {
      return rawDeletedAt.toInt() > 0;
    }
    return false;
  }

  bool isKnownGroupChat(String peerId, {Chat? loadedChat}) {
    final meta = _groupMetaByGroupId[peerId];
    return loadedChat?.isGroup == true ||
        Chat.isGroupLikePeerId(peerId) ||
        meta?['isGroup'] == true;
  }

  Future<void> rememberDeletedGroup(
    String groupId, {
    required String deletedByPeerId,
    Chat? chat,
  }) async {
    final nextMeta = Map<String, dynamic>.from(
      _groupMetaByGroupId[groupId] ?? const <String, dynamic>{},
    );
    nextMeta['isGroup'] = true;
    nextMeta['deletedAtMs'] = DateTime.now().millisecondsSinceEpoch;
    nextMeta['deletedByPeerId'] = deletedByPeerId;
    if (chat != null) {
      nextMeta['name'] = chat.name;
      nextMeta['ownerPeerId'] = chat.ownerPeerId;
      nextMeta['memberPeerIds'] = chat.memberPeerIds;
      nextMeta['avatarPath'] = chat.avatarPath;
    }
    _groupMetaByGroupId[groupId] = nextMeta;
    await persistGroupMetaToSettings();
  }

  Future<void> restoreDeletedGroup(String groupId) async {
    final current = _groupMetaByGroupId[groupId];
    if (current == null) {
      return;
    }
    final nextMeta = Map<String, dynamic>.from(current);
    final removedDeletedAt = nextMeta.remove('deletedAtMs') != null;
    final removedDeletedBy = nextMeta.remove('deletedByPeerId') != null;
    if (!removedDeletedAt && !removedDeletedBy) {
      return;
    }
    _groupMetaByGroupId[groupId] = nextMeta;
    await persistGroupMetaToSettings();
  }

  void applyGroupMeta(Chat chat) {
    final meta = _groupMetaByGroupId[chat.peerId];
    if (meta == null) {
      return;
    }
    final rawMembers = meta['memberPeerIds'];
    if (rawMembers is List) {
      final members =
          rawMembers
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false)
            ..sort();
      if (members.isNotEmpty) {
        chat.memberPeerIds = members;
      }
    }
    final owner = (meta['ownerPeerId'] as String?)?.trim();
    if (owner != null && owner.isNotEmpty) {
      chat.ownerPeerId = owner;
    }
    final isGroup = meta['isGroup'] as bool?;
    if (isGroup == true) {
      chat.isGroup = true;
    }
    final groupName = (meta['name'] as String?)?.trim();
    if (groupName != null && groupName.isNotEmpty) {
      chat.name = groupName;
    }
    final avatarPath = (meta['avatarPath'] as String?)?.trim();
    if (avatarPath != null && avatarPath.isNotEmpty) {
      chat.avatarPath = avatarPath;
    }
  }

  Future<void> persistChatSummary(Chat chat) async {
    if ((chat.isGroup || Chat.isGroupLikePeerId(chat.peerId)) &&
        isGroupDeleted(chat.peerId)) {
      return;
    }
    final summaryJson = Map<String, dynamic>.from(chat.toJson())
      ..['messagesLoaded'] = false;
    await storage.saveChatSummaryMap(chat.peerId, summaryJson);
    var shouldPersistGroupMeta = false;
    if (chat.isGroup || Chat.isGroupLikePeerId(chat.peerId)) {
      final normalizedMembers = _normalizeMemberPeerIds(chat.memberPeerIds);
      if (!_sameMembers(chat.memberPeerIds, normalizedMembers)) {
        chat.memberPeerIds = normalizedMembers;
      }
      final nextMeta = <String, dynamic>{
        'isGroup': true,
        'name': chat.name,
        'ownerPeerId': chat.ownerPeerId,
        'memberPeerIds': normalizedMembers,
        'avatarPath': chat.avatarPath,
      };
      final currentMeta = _groupMetaByGroupId[chat.peerId];
      if (!_isSameGroupMeta(currentMeta, nextMeta)) {
        _groupMetaByGroupId[chat.peerId] = nextMeta;
        shouldPersistGroupMeta = true;
      }
    } else if (_groupMetaByGroupId.remove(chat.peerId) != null) {
      shouldPersistGroupMeta = true;
    }
    if (shouldPersistGroupMeta) {
      await persistGroupMetaToSettings();
    }
  }

  List<String> _normalizeMemberPeerIds(List<String> members) {
    final normalized = members
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    normalized.sort();
    return normalized;
  }

  bool _sameMembers(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  String? knownGroupOwnerPeerId(String groupId) {
    final metaOwner = (_groupMetaByGroupId[groupId]?['ownerPeerId'] as String?)
        ?.trim();
    if (metaOwner != null && metaOwner.isNotEmpty) {
      return metaOwner;
    }
    return null;
  }

  Future<void> removeGroupMeta(String peerId) async {
    if (_groupMetaByGroupId.remove(peerId) != null) {
      await persistGroupMetaToSettings();
    }
  }

  bool _isSameGroupMeta(
    Map<String, dynamic>? current,
    Map<String, dynamic> next,
  ) {
    if (current == null) {
      return false;
    }
    final currentIsGroup = current['isGroup'] == true;
    final nextIsGroup = next['isGroup'] == true;
    if (currentIsGroup != nextIsGroup) {
      return false;
    }
    final currentName = (current['name'] as String?) ?? '';
    final nextName = (next['name'] as String?) ?? '';
    if (currentName != nextName) {
      return false;
    }
    final currentOwner = (current['ownerPeerId'] as String?) ?? '';
    final nextOwner = (next['ownerPeerId'] as String?) ?? '';
    if (currentOwner != nextOwner) {
      return false;
    }
    final currentMembers = ((current['memberPeerIds'] as List?) ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final nextMembers = ((next['memberPeerIds'] as List?) ?? const [])
        .whereType<String>()
        .toList(growable: false);
    if (currentMembers.length != nextMembers.length) {
      return false;
    }
    for (var i = 0; i < currentMembers.length; i++) {
      if (currentMembers[i] != nextMembers[i]) {
        return false;
      }
    }
    final currentAvatarPath = (current['avatarPath'] as String?) ?? '';
    final nextAvatarPath = (next['avatarPath'] as String?) ?? '';
    if (currentAvatarPath != nextAvatarPath) {
      return false;
    }
    return true;
  }
}
