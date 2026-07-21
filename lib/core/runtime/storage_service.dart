import 'dart:convert';
import 'dart:io';

import 'app_storage_stats.dart';
import 'chat_database.dart';
import 'secure_storage_wrapper.dart';
import 'storage_service_media.dart';
import 'storage_service_migrations.dart';
import 'storage_service_paths.dart';

/// Архитектура хранения:
/// - Secure Storage: settings, contacts
/// - SQLite/Drift: chat summaries, messages
/// - File Storage: media files
class StorageService {
  static const contactsBox = 'contacts';
  static const settingsBox = 'settings';
  static const callsBox = 'calls';
  static const groupMetaBox = 'group_meta';
  static const groupKeysBox = 'group_keys';
  static const _legacyChatsStorageKey = 'peerlink.chats';
  static const _chatPageSize = 30;
  static const _legacyGroupMetaSettingsKey = 'peerlink.group_meta.v1';
  static const _legacyGroupKeysSettingsKey = 'peerlink.group_keys.v1';
  static const _legacyGroupKeyVersionsSettingsKey =
      'peerlink.group_key_versions.v1';
  static const _groupKeyStoragePrefix = 'peerlink.group_key.v2.';
  static const _groupKeyVersionStoragePrefix = 'peerlink.group_key_version.v2.';
  static const _groupMetaStateKey = 'state.v1';

  static bool _initialized = false;
  static Future<void>? _initializationFuture;
  static final Map<String, Map<String, dynamic>> _boxes = {
    contactsBox: <String, dynamic>{},
    settingsBox: <String, dynamic>{},
    callsBox: <String, dynamic>{},
    groupMetaBox: <String, dynamic>{},
    groupKeysBox: <String, dynamic>{},
  };

  static Directory? _mediaDirectory;
  static Directory? _rootDirectory;
  static Directory? _databaseDirectory;
  static Directory? _secureDirectory;

  StorageServiceMigrations get _migrations => StorageServiceMigrations(
    boxes: _boxes,
    contactsBoxName: contactsBox,
    settingsBoxName: settingsBox,
    groupMetaBoxName: groupMetaBox,
    groupKeysBoxName: groupKeysBox,
    legacyChatsStorageKey: _legacyChatsStorageKey,
    chatPageSize: _chatPageSize,
    legacyGroupMetaSettingsKey: _legacyGroupMetaSettingsKey,
    legacyGroupKeysSettingsKey: _legacyGroupKeysSettingsKey,
    legacyGroupKeyVersionsSettingsKey: _legacyGroupKeyVersionsSettingsKey,
    groupKeyStoragePrefix: _groupKeyStoragePrefix,
    groupKeyVersionStoragePrefix: _groupKeyVersionStoragePrefix,
    groupMetaStateKey: _groupMetaStateKey,
    boxKeyFor: _boxKey,
    persistBox: _persist,
    getChatSummary: getChatSummary,
    loadAllChatSummaries: loadAllChatSummaries,
    saveChatSummaryMap: saveChatSummaryMap,
    loadConversationHeads: () async =>
        ChatDatabaseService.instance.getConversationHeadsAsJson(),
    readChatMessages: readChatMessages,
    writeChatMessages: writeChatMessages,
  );

  StorageServiceMedia get _mediaStore => StorageServiceMedia(
    mediaDirectory: _mediaDirectory,
    loadAllChatSummaries: loadAllChatSummaries,
    readChatMessages: readChatMessages,
    writeChatMessages: writeChatMessages,
    saveChatSummaryMap: saveChatSummaryMap,
  );

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    final currentInitialization = _initializationFuture;
    if (currentInitialization != null) {
      await currentInitialization;
      return;
    }

    _initializationFuture = () async {
      try {
        final root = await StorageServicePaths.resolveRootDirectory();
        final databaseDirectory = Directory('${root.path}/sqlite');
        final secureDirectory = Directory('${root.path}/secure_storage');
        _mediaDirectory = Directory('${root.path}/media');
        _rootDirectory = root;
        _databaseDirectory = databaseDirectory;
        _secureDirectory = secureDirectory;

        await databaseDirectory.create(recursive: true);
        await secureDirectory.create(recursive: true);
        await _mediaDirectory!.create(recursive: true);

        await ChatDatabaseService.initialize(directory: databaseDirectory.path);
        await SecureStorageWrapper.initialize(
          fallbackDirectory: secureDirectory,
        );

        await _migrations.migrateLegacyChatsToSqlite();
        await _migrations.loadFromSecureStorage();
        await _migrations.migrateLegacyGroupStorageFromSettings();
        await _migrations.repairChatSummariesFromMessages();
        await _migrations.pruneLargeEmbeddedMedia();

        _initialized = true;
      } catch (_) {
        rethrow;
      } finally {
        _initializationFuture = null;
      }
    }();

    await _initializationFuture;
  }

  SecureStorageBox getContacts() => SecureStorageBox._(this, contactsBox);
  SecureStorageBox getSettings() => SecureStorageBox._(this, settingsBox);
  SecureStorageBox getCalls() => SecureStorageBox._(this, callsBox);
  SecureStorageBox getGroupMeta() => SecureStorageBox._(this, groupMetaBox);
  SecureStorageBox getGroupKeys() => SecureStorageBox._(this, groupKeysBox);

  Map<String, dynamic> _boxData(String boxName) {
    if (!_initialized) {
      throw StateError('StorageService.init() must be called before access');
    }
    return _boxes.putIfAbsent(boxName, () => <String, dynamic>{});
  }

  String _boxKey(String boxName) => 'peerlink.$boxName';

  Future<void> _persist(String boxName) async {
    try {
      final data = _boxes.putIfAbsent(boxName, () => <String, dynamic>{});
      await SecureStorageWrapper.write(_boxKey(boxName), jsonEncode(data));
    } catch (_) {
      // Diagnostics disabled.
    }
  }

  Future<List<Map<String, dynamic>>> loadAllChatSummaries() async {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getAllChatSummariesAsJson(),
      operation: 'loadAllChatSummaries',
    );
  }

  Future<Map<String, dynamic>?> getChatSummary(String peerId) async {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getChatSummaryAsJson(peerId),
      operation: 'getChatSummary($peerId)',
    );
  }

  Future<void> saveChatSummaryMap(
    String peerId,
    Map<String, dynamic> json,
  ) async {
    await ChatDatabaseService.runWithRecovery(
      (database) => database.upsertChatSummary(peerId, json),
      operation: 'saveChatSummaryMap($peerId)',
    );
  }

  Future<void> deleteChatSummaryMap(String peerId) async {
    await ChatDatabaseService.runWithRecovery(
      (database) => database.deleteChatSummary(peerId),
      operation: 'deleteChatSummaryMap($peerId)',
    );
  }

  Future<void> writeChatMessages(
    String peerId,
    List<Map<String, dynamic>> messages,
  ) async {
    final normalized = messages
        .map(
          (message) => _normalizeMessageForStorage(
            peerId,
            Map<String, dynamic>.from(message),
          ),
        )
        .toList(growable: false);
    await ChatDatabaseService.runWithRecovery(
      (database) => database.replaceMessages(peerId, normalized),
      operation: 'writeChatMessages($peerId)',
    );
  }

  Future<void> upsertChatMessages(
    String peerId,
    List<Map<String, dynamic>> messages,
  ) async {
    if (messages.isEmpty) {
      return;
    }
    final normalized = messages
        .map(
          (message) => _normalizeMessageForStorage(
            peerId,
            Map<String, dynamic>.from(message),
          ),
        )
        .toList(growable: false);
    await ChatDatabaseService.runWithRecovery(
      (database) => database.upsertMessages(normalized),
      operation: 'upsertChatMessages($peerId)',
    );
  }

  Future<List<Map<String, dynamic>>> readChatMessages(String peerId) async {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getMessagesAsJson(peerId),
      operation: 'readChatMessages($peerId)',
    );
  }

  Future<List<Map<String, dynamic>>> loadLatestMessages(
    String peerId,
    int limit,
  ) async {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getLatestMessagesAsJson(peerId, limit),
      operation: 'loadLatestMessages($peerId)',
    );
  }

  Future<List<Map<String, dynamic>>> loadMessagesPage(
    String peerId,
    int offset,
    int limit,
  ) async {
    final page = await ChatDatabaseService.runWithRecovery(
      (database) => database.getMessagesPageAsJson(peerId, offset, limit),
      operation: 'loadMessagesPage($peerId,$offset,$limit)',
    );
    return page;
  }

  Future<Map<String, dynamic>> loadMessagesIndex(String peerId) async {
    final count = await ChatDatabaseService.runWithRecovery(
      (database) => database.countMessages(peerId),
      operation: 'loadMessagesIndex($peerId)',
    );
    return <String, dynamic>{
      'totalMessages': count,
      'totalGroups': count == 0 ? 0 : ((count - 1) ~/ _chatPageSize) + 1,
    };
  }

  Future<int?> getMessageOffsetFromNewest(
    String peerId,
    String messageId,
  ) async {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getMessageOffsetFromNewest(peerId, messageId),
      operation: 'getMessageOffsetFromNewest($peerId,$messageId)',
    );
  }

  Future<void> deleteChatMessages(String peerId) async {
    await ChatDatabaseService.runWithRecovery(
      (database) => database.deleteMessages(peerId),
      operation: 'deleteChatMessages($peerId)',
    );
  }

  Future<void> deleteChatMessagesByIds(
    String peerId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) {
      return;
    }
    await ChatDatabaseService.runWithRecovery(
      (database) => database.deleteMessagesByIds(peerId, messageIds),
      operation: 'deleteChatMessagesByIds($peerId)',
    );
  }

  Map<String, dynamic> _normalizeMessageForStorage(
    String peerId,
    Map<String, dynamic> message,
  ) {
    final normalized = Map<String, dynamic>.from(message);
    normalized['peerId'] = normalized['peerId'] ?? peerId;
    normalized['fileDataBase64'] = null;

    return normalized;
  }

  Future<String> saveMediaBytes({
    required String peerId,
    required String messageId,
    required String fileName,
    required List<int> bytes,
  }) async {
    return _mediaStore.saveBytes(
      peerId: peerId,
      messageId: messageId,
      fileName: fileName,
      bytes: bytes,
    );
  }

  Future<String> saveMediaFile({
    required String peerId,
    required String messageId,
    required String fileName,
    required String sourcePath,
  }) async {
    return _mediaStore.saveFile(
      peerId: peerId,
      messageId: messageId,
      fileName: fileName,
      sourcePath: sourcePath,
    );
  }

  Future<void> deleteMediaFile(String? path) async {
    await _mediaStore.deleteFile(path);
  }

  Future<void> deletePeerMediaDirectory(String peerId) async {
    await _mediaStore.deletePeerDirectory(peerId);
  }

  bool isManagedMediaPath(String? path) {
    return _mediaStore.isManagedPath(path);
  }

  Future<AppStorageBreakdown> computeAppStorageBreakdown() async {
    await init();
    final rootDirectory = _rootDirectory;
    final databaseDirectory = _databaseDirectory;
    final secureDirectory = _secureDirectory;
    final mediaDirectory = _mediaDirectory;
    final logsDirectory = rootDirectory == null
        ? null
        : Directory('${rootDirectory.path}/logs');

    return AppStorageBreakdown(
      mediaFilesBytes: await _mediaStore.directorySize(mediaDirectory),
      messagesDatabaseBytes: await _mediaStore.directorySize(databaseDirectory),
      logsBytes: await _mediaStore.directorySize(logsDirectory),
      settingsAndServiceDataBytes: await _mediaStore.directorySize(
        secureDirectory,
      ),
    );
  }

  Future<void> clearManagedMediaStorage() async {
    await init();
    await _mediaStore.clearManagedStorage();
  }

  Future<void> clearMessagesDatabase() async {
    await init();
    await ChatDatabaseService.runWithRecovery(
      (database) => database.deleteAllData(),
      operation: 'clearMessagesDatabase',
    );
  }

  Future<void> clearSettingsAndServiceData() async {
    await init();
    final boxNames = List<String>.from(_boxes.keys);
    for (final boxName in boxNames) {
      _boxes[boxName] = <String, dynamic>{};
      await SecureStorageWrapper.delete(_boxKey(boxName));
    }
    await SecureStorageWrapper.delete(_legacyChatsStorageKey);
  }

  Future<String?> recoverMediaFromLegacy({
    required String peerId,
    required String messageId,
    required String fileName,
    String? previousPath,
  }) async {
    return _mediaStore.recoverLegacyMedia(
      peerId: peerId,
      messageId: messageId,
      fileName: fileName,
      previousPath: previousPath,
    );
  }

  Future<List<Map<String, dynamic>>> readCallLogs() async {
    final raw = _boxData(callsBox)['items'];
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> prependCallLog(Map<String, dynamic> callLog) async {
    final box = _boxData(callsBox);
    final existingRaw = box['items'];
    final items = existingRaw is List
        ? existingRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: true)
        : <Map<String, dynamic>>[];

    final id = callLog['id'] as String?;
    if (id != null && id.isNotEmpty) {
      items.removeWhere((item) => item['id'] == id);
    }

    items.insert(0, Map<String, dynamic>.from(callLog));
    if (items.length > 200) {
      items.removeRange(200, items.length);
    }

    box['items'] = items;
    await _persist(callsBox);
  }

  Future<void> deleteCallLog(String id) async {
    if (id.trim().isEmpty) {
      return;
    }

    final box = _boxData(callsBox);
    final existingRaw = box['items'];
    if (existingRaw is! List) {
      return;
    }

    final items = existingRaw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: true);
    items.removeWhere((item) => item['id'] == id);
    box['items'] = items;
    await _persist(callsBox);
  }
}

class SecureStorageBox {
  final StorageService _service;
  final String _boxName;

  SecureStorageBox._(this._service, this._boxName);

  Iterable<dynamic> get values => _service._boxData(_boxName).values;

  Iterable<String> get keys => _service._boxData(_boxName).keys;

  dynamic get(String key) => _service._boxData(_boxName)[key];

  Future<void> put(String key, dynamic value) async {
    _service._boxData(_boxName)[key] = value;
    await _service._persist(_boxName);
  }

  Future<void> delete(String key) async {
    _service._boxData(_boxName).remove(key);
    await _service._persist(_boxName);
  }

  Future<void> clear() async {
    _service._boxData(_boxName).clear();
    await _service._persist(_boxName);
  }
}
