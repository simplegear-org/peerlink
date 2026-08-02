import 'dart:convert';

import 'contact_name_resolver.dart';
import 'secure_storage_wrapper.dart';

class StorageServiceMigrations {
  const StorageServiceMigrations({
    required this.boxes,
    required this.contactsBoxName,
    required this.settingsBoxName,
    required this.groupMetaBoxName,
    required this.groupKeysBoxName,
    required this.legacyChatsStorageKey,
    required this.chatPageSize,
    required this.legacyGroupMetaSettingsKey,
    required this.legacyGroupKeysSettingsKey,
    required this.legacyGroupKeyVersionsSettingsKey,
    required this.groupKeyStoragePrefix,
    required this.groupKeyVersionStoragePrefix,
    required this.groupMetaStateKey,
    required this.boxKeyFor,
    required this.persistBox,
    required this.getChatSummary,
    required this.loadAllChatSummaries,
    required this.saveChatSummaryMap,
    required this.loadConversationHeads,
    required this.readChatMessages,
    required this.writeChatMessages,
  });

  final Map<String, Map<String, dynamic>> boxes;
  final String contactsBoxName;
  final String settingsBoxName;
  final String groupMetaBoxName;
  final String groupKeysBoxName;
  final String legacyChatsStorageKey;
  final int chatPageSize;
  final String legacyGroupMetaSettingsKey;
  final String legacyGroupKeysSettingsKey;
  final String legacyGroupKeyVersionsSettingsKey;
  final String groupKeyStoragePrefix;
  final String groupKeyVersionStoragePrefix;
  final String groupMetaStateKey;
  final String Function(String boxName) boxKeyFor;
  final Future<void> Function(String boxName) persistBox;
  final Future<Map<String, dynamic>?> Function(String peerId) getChatSummary;
  final Future<List<Map<String, dynamic>>> Function() loadAllChatSummaries;
  final Future<void> Function(String peerId, Map<String, dynamic> json)
  saveChatSummaryMap;
  final Future<List<Map<String, dynamic>>> Function() loadConversationHeads;
  final Future<List<Map<String, dynamic>>> Function(String peerId)
  readChatMessages;
  final Future<void> Function(
    String peerId,
    List<Map<String, dynamic>> messages,
  )
  writeChatMessages;

  Future<void> loadFromSecureStorage() async {
    final boxNames = List<String>.from(boxes.keys);
    for (final boxName in boxNames) {
      try {
        final raw = await SecureStorageWrapper.read(boxKeyFor(boxName));
        if (raw == null || raw.isEmpty) {
          continue;
        }

        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          boxes[boxName] = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Diagnostics disabled.
      }
    }
  }

  Future<void> migrateLegacyChatsToSqlite() async {
    try {
      final raw = await SecureStorageWrapper.read(legacyChatsStorageKey);
      if (raw == null || raw.isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await SecureStorageWrapper.delete(legacyChatsStorageKey);
        return;
      }

      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) {
          continue;
        }

        final legacyChat = Map<String, dynamic>.from(value);
        final peerId = legacyChat['peerId'] as String? ?? entry.key;
        await _migrateLegacyChatMessages(peerId, legacyChat);
        final existing = await getChatSummary(peerId);
        if (_shouldSkipLegacyChatMigration(existing, legacyChat)) {
          continue;
        }

        await saveChatSummaryMap(peerId, legacyChat);
      }

      await SecureStorageWrapper.delete(legacyChatsStorageKey);
    } catch (_) {
      // Diagnostics disabled.
    }
  }

  Future<void> repairChatSummariesFromMessages() async {
    try {
      final heads = await loadConversationHeads();
      for (final head in heads) {
        final peerId = head['peerId'] as String?;
        if (peerId == null || peerId.isEmpty) {
          continue;
        }

        final existing = await getChatSummary(peerId);
        if (!_needsSummaryRepair(existing)) {
          continue;
        }

        final messages = await readChatMessages(peerId);
        final unreadCount = messages.where((message) {
          final incoming = message['incoming'] as bool? ?? false;
          final isRead = message['isRead'] as bool? ?? true;
          return incoming && !isRead;
        }).length;

        await saveChatSummaryMap(peerId, <String, dynamic>{
          'peerId': peerId,
          'name': _contactNameFor(peerId),
          'unreadCount': unreadCount,
          'messagesLoaded': false,
          'hasMoreMessages': messages.length > chatPageSize,
          'lastMessage': head,
        });
      }
    } catch (_) {
      // Diagnostics disabled.
    }
  }

  Future<void> pruneLargeEmbeddedMedia() async {
    final summaries = await loadAllChatSummaries();
    for (final summary in summaries) {
      final peerId = summary['peerId'] as String?;
      if (peerId == null || peerId.isEmpty) {
        continue;
      }

      final messages = await readChatMessages(peerId);
      var changed = false;
      for (final message in messages) {
        final embedded = message['fileDataBase64'] as String?;
        if (embedded != null && embedded.isNotEmpty) {
          message['fileDataBase64'] = null;
          changed = true;
        }
      }

      if (changed) {
        await writeChatMessages(peerId, messages);
      }
    }
  }

  Future<void> migrateLegacyGroupStorageFromSettings() async {
    final settings = boxes[settingsBoxName];
    final groupMeta = boxes[groupMetaBoxName];
    final groupKeys = boxes[groupKeysBoxName];
    if (settings == null || groupMeta == null || groupKeys == null) {
      return;
    }

    var settingsChanged = false;
    var groupMetaChanged = false;
    var groupKeysChanged = false;

    final legacyMeta = settings[legacyGroupMetaSettingsKey];
    if (legacyMeta is Map && groupMeta[groupMetaStateKey] == null) {
      groupMeta[groupMetaStateKey] = Map<String, dynamic>.from(legacyMeta);
      groupMetaChanged = true;
    }
    if (settings.remove(legacyGroupMetaSettingsKey) != null) {
      settingsChanged = true;
    }

    final legacyGroupKeys = settings[legacyGroupKeysSettingsKey];
    if (legacyGroupKeys is Map &&
        groupKeys[legacyGroupKeysSettingsKey] == null) {
      groupKeys[legacyGroupKeysSettingsKey] = Map<String, dynamic>.from(
        legacyGroupKeys,
      );
      groupKeysChanged = true;
    }
    if (settings.remove(legacyGroupKeysSettingsKey) != null) {
      settingsChanged = true;
    }

    final legacyGroupVersions = settings[legacyGroupKeyVersionsSettingsKey];
    if (legacyGroupVersions is Map &&
        groupKeys[legacyGroupKeyVersionsSettingsKey] == null) {
      groupKeys[legacyGroupKeyVersionsSettingsKey] = Map<String, dynamic>.from(
        legacyGroupVersions,
      );
      groupKeysChanged = true;
    }
    if (settings.remove(legacyGroupKeyVersionsSettingsKey) != null) {
      settingsChanged = true;
    }

    final keysToMove = settings.keys
        .where(
          (key) =>
              key.startsWith(groupKeyStoragePrefix) ||
              key.startsWith(groupKeyVersionStoragePrefix),
        )
        .toList(growable: false);

    for (final key in keysToMove) {
      final value = settings[key];
      if (groupKeys[key] == null && value != null) {
        groupKeys[key] = value;
        groupKeysChanged = true;
      }
      settings.remove(key);
      settingsChanged = true;
    }

    if (groupMetaChanged) {
      await persistBox(groupMetaBoxName);
    }
    if (groupKeysChanged) {
      await persistBox(groupKeysBoxName);
    }
    if (settingsChanged) {
      await persistBox(settingsBoxName);
    }
  }

  Future<void> _migrateLegacyChatMessages(
    String peerId,
    Map<String, dynamic> legacyChat,
  ) async {
    final rawMessages = legacyChat['messages'];
    if (rawMessages is! List || rawMessages.isEmpty) {
      return;
    }

    final legacyMessages = <Map<String, dynamic>>[];
    for (final rawMessage in rawMessages) {
      if (rawMessage is Map<String, dynamic>) {
        legacyMessages.add(
          _normalizeLegacyChatMessage(
            peerId,
            Map<String, dynamic>.from(rawMessage),
          ),
        );
      }
    }
    if (legacyMessages.isEmpty) {
      return;
    }

    final existingMessages = await readChatMessages(peerId);
    if (_shouldSkipLegacyMessagesMigration(existingMessages, legacyMessages)) {
      return;
    }

    await writeChatMessages(peerId, legacyMessages);
  }

  bool _shouldSkipLegacyMessagesMigration(
    List<Map<String, dynamic>> existingMessages,
    List<Map<String, dynamic>> legacyMessages,
  ) {
    if (existingMessages.isEmpty) {
      return false;
    }

    final existingLast = existingMessages.isEmpty
        ? null
        : existingMessages.last;
    final legacyLast = legacyMessages.isEmpty ? null : legacyMessages.last;
    final existingLastId = existingLast?['id'] as String?;
    final legacyLastId = legacyLast?['id'] as String?;
    final existingLastTime = DateTime.tryParse(
      existingLast?['timestamp'] as String? ?? '',
    );
    final legacyLastTime = DateTime.tryParse(
      legacyLast?['timestamp'] as String? ?? '',
    );

    if (existingMessages.length >= legacyMessages.length &&
        existingLastId != null &&
        existingLastId == legacyLastId) {
      return true;
    }

    if (existingLastTime != null &&
        legacyLastTime != null &&
        existingLastTime.isAfter(legacyLastTime)) {
      return true;
    }

    return false;
  }

  Map<String, dynamic> _normalizeLegacyChatMessage(
    String peerId,
    Map<String, dynamic> message,
  ) {
    message['peerId'] =
        (message['peerId'] as String?)?.trim().isNotEmpty == true
        ? message['peerId']
        : peerId;
    return message;
  }

  bool _shouldSkipLegacyChatMigration(
    Map<String, dynamic>? existing,
    Map<String, dynamic> legacyChat,
  ) {
    if (existing == null) {
      return false;
    }

    final rawLast = legacyChat['lastMessage'];
    final legacyTime = rawLast is Map<String, dynamic>
        ? DateTime.tryParse(rawLast['timestamp'] as String? ?? '')
        : null;
    final existingLast = existing['lastMessage'];
    final existingTime = existingLast is Map<String, dynamic>
        ? DateTime.tryParse(existingLast['timestamp'] as String? ?? '')
        : null;
    return existingTime != null &&
        (legacyTime == null || !legacyTime.isAfter(existingTime));
  }

  bool _needsSummaryRepair(Map<String, dynamic>? existing) {
    final existingName = existing?['name'] as String?;
    return existing == null ||
        existing['lastMessage'] == null ||
        existingName == null ||
        existingName.trim().isEmpty;
  }

  String _contactNameFor(String peerId) {
    return ContactNameResolver.resolveFromMap(
      boxes[contactsBoxName],
      peerId: peerId,
    );
  }
}
