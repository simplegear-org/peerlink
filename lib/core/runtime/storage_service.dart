import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_storage_stats.dart';
import 'chat_database.dart';
import 'contact_name_resolver.dart';
import 'secure_storage_wrapper.dart';

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

  Future<void> init() async {
    if (_initialized) {
      debugPrint('[StorageService] Already initialized');
      return;
    }

    final currentInitialization = _initializationFuture;
    if (currentInitialization != null) {
      debugPrint('[StorageService] Awaiting in-flight initialization');
      await currentInitialization;
      return;
    }

    debugPrint('[StorageService] Initializing...');
    _initializationFuture = () async {
      try {
        final root = await _resolveRootDirectory();
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
        await SecureStorageWrapper.initialize(fallbackDirectory: secureDirectory);

        await _migrateLegacyChatsToSqlite();
        await _loadFromSecureStorage();
        await _migrateLegacyGroupStorageFromSettings();
        await _repairChatSummariesFromMessages();
        await _pruneLargeEmbeddedMedia();

        _initialized = true;
        debugPrint('[StorageService] Initialized successfully');
      } catch (e, stack) {
        debugPrint('[StorageService] Failed to initialize: $e\n$stack');
        rethrow;
      } finally {
        _initializationFuture = null;
      }
    }();

    await _initializationFuture;
  }

  Future<Directory> _resolveRootDirectory() async {
    final home = Platform.environment['HOME'];
    final tmpDir = Platform.environment['TMPDIR'];
    if ((Platform.isIOS || Platform.isMacOS) && home != null && home.isNotEmpty) {
      final root = Directory('$home/Library/Application Support/peerlink');
      await root.create(recursive: true);
      debugPrint('[StorageService] Root directory ios/macos(home): ${root.path}');
      return root;
    }

    try {
      if (home != null && home.isNotEmpty) {
        final root = Directory('$home/.peerlink');
        await root.create(recursive: true);
        debugPrint('[StorageService] Root directory fallback(home): ${root.path}');
        return root;
      }
    } catch (e, stack) {
      debugPrint('[StorageService] HOME fallback failed: $e\n$stack');
    }

    try {
      if (tmpDir != null && tmpDir.isNotEmpty) {
        final root = Directory('$tmpDir/peerlink');
        await root.create(recursive: true);
        debugPrint('[StorageService] Root directory fallback(tmpdir): ${root.path}');
        return root;
      }
    } catch (e, stack) {
      debugPrint('[StorageService] TMPDIR fallback failed: $e\n$stack');
    }

    try {
      final currentPath = Directory.current.path;
      final safeCurrentPath = currentPath == '/' ? Directory.systemTemp.path : currentPath;
      final root = Directory('$safeCurrentPath/.peerlink');
      await root.create(recursive: true);
      debugPrint('[StorageService] Root directory fallback(cwd): ${root.path}');
      return root;
    } catch (e, stack) {
      debugPrint('[StorageService] CWD fallback failed: $e\n$stack');
    }

    final root = Directory('${Directory.systemTemp.path}/peerlink');
    await root.create(recursive: true);
    debugPrint('[StorageService] Root directory fallback(temp): ${root.path}');
    return root;
  }

  Future<void> _loadFromSecureStorage() async {
    final boxNames = List<String>.from(_boxes.keys);
    for (final boxName in boxNames) {
      try {
        final raw = await SecureStorageWrapper.read(_boxKey(boxName));
        if (raw == null || raw.isEmpty) {
          continue;
        }

        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _boxes[boxName] = Map<String, dynamic>.from(decoded);
        }
      } catch (e, stack) {
        debugPrint('[StorageService] Load failed for $boxName: $e\n$stack');
      }
    }
  }

  Future<void> _migrateLegacyChatsToSqlite() async {
    try {
      final raw = await SecureStorageWrapper.read(_legacyChatsStorageKey);
      if (raw == null || raw.isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await SecureStorageWrapper.delete(_legacyChatsStorageKey);
        return;
      }

      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) {
          continue;
        }

        final peerId = value['peerId'] as String? ?? entry.key;
        final existing = await getChatSummary(peerId);
        if (existing != null) {
          final rawLast = value['lastMessage'];
          final legacyTime = rawLast is Map<String, dynamic>
              ? DateTime.tryParse(rawLast['timestamp'] as String? ?? '')
              : null;
          final existingLast = existing['lastMessage'];
          final existingTime = existingLast is Map<String, dynamic>
              ? DateTime.tryParse(existingLast['timestamp'] as String? ?? '')
              : null;
          final shouldSkip = existingTime != null &&
              (legacyTime == null || !legacyTime.isAfter(existingTime));
          if (shouldSkip) {
            continue;
          }
        }

        await saveChatSummaryMap(peerId, Map<String, dynamic>.from(value));
      }

      await SecureStorageWrapper.delete(_legacyChatsStorageKey);
      debugPrint('[StorageService] Removed legacy chats storage key');
    } catch (e, stack) {
      debugPrint('[StorageService] Legacy chats migration failed: $e\n$stack');
    }
  }

  Future<void> _repairChatSummariesFromMessages() async {
    try {
      final heads = await ChatDatabaseService.instance.getConversationHeadsAsJson();
      for (final head in heads) {
        final peerId = head['peerId'] as String?;
        if (peerId == null || peerId.isEmpty) {
          continue;
        }

        final existing = await getChatSummary(peerId);
        final existingName = existing?['name'] as String?;
        final needsRepair = existing == null ||
            existing['lastMessage'] == null ||
            existingName == null ||
            existingName.trim().isEmpty;
        if (!needsRepair) {
          continue;
        }

        final messages = await readChatMessages(peerId);
        final unreadCount = messages.where((message) {
          final incoming = message['incoming'] as bool? ?? false;
          final isRead = message['isRead'] as bool? ?? true;
          return incoming && !isRead;
        }).length;

        final fallbackName = _contactNameFor(peerId);
        await saveChatSummaryMap(peerId, <String, dynamic>{
          'peerId': peerId,
          'name': fallbackName,
          'unreadCount': unreadCount,
          'messagesLoaded': false,
          'hasMoreMessages': messages.length > _chatPageSize,
          'lastMessage': head,
        });
      }
    } catch (e, stack) {
      debugPrint('[StorageService] Summary repair failed: $e\n$stack');
    }
  }

  SecureStorageBox getContacts() => SecureStorageBox._(this, contactsBox);
  SecureStorageBox getSettings() => SecureStorageBox._(this, settingsBox);
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
    } catch (e, stack) {
      debugPrint('[StorageService] Persist failed for $boxName: $e\n$stack');
    }
  }

  String _contactNameFor(String peerId) {
    return ContactNameResolver.resolveFromMap(
      _boxes[contactsBox],
      peerId: peerId,
    );
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

  Future<void> saveChatSummaryMap(String peerId, Map<String, dynamic> json) async {
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
        .map((message) => _normalizeMessageForStorage(peerId, Map<String, dynamic>.from(message)))
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
        .map((message) => _normalizeMessageForStorage(peerId, Map<String, dynamic>.from(message)))
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

  Future<List<Map<String, dynamic>>> loadLatestMessages(String peerId, int limit) async {
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
    debugPrint(
      '[StorageService] loadMessagesPage peer=$peerId offset=$offset limit=$limit fetched=${page.length}',
    );
    return page;
  }

  Future<Map<String, dynamic>> loadMessagesIndex(String peerId) async {
    final count = await ChatDatabaseService.runWithRecovery(
      (database) => database.countMessages(peerId),
      operation: 'loadMessagesIndex($peerId)',
    );
    debugPrint('[StorageService] loadMessagesIndex peer=$peerId total=$count');
    return <String, dynamic>{
      'totalMessages': count,
      'totalGroups': count == 0 ? 0 : ((count - 1) ~/ _chatPageSize) + 1,
    };
  }

  Future<int?> getMessageOffsetFromNewest(String peerId, String messageId) async {
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

  Future<void> deleteChatMessagesByIds(String peerId, List<String> messageIds) async {
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
    try {
      final mediaDirectory = _mediaDirectory;
      if (mediaDirectory == null) {
        return '';
      }

      final peerDir = Directory('${mediaDirectory.path}/$peerId');
      await peerDir.create(recursive: true);

      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final file = File('${peerDir.path}/$messageId-$safeName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e, stack) {
      debugPrint('[StorageService] saveMediaBytes failed: $e\n$stack');
      return '';
    }
  }

  Future<String> saveMediaFile({
    required String peerId,
    required String messageId,
    required String fileName,
    required String sourcePath,
  }) async {
    try {
      final mediaDirectory = _mediaDirectory;
      if (mediaDirectory == null) {
        return '';
      }

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return '';
      }

      final peerDir = Directory('${mediaDirectory.path}/$peerId');
      await peerDir.create(recursive: true);

      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final destination = File('${peerDir.path}/$messageId-$safeName');

      if (await destination.exists()) {
        return destination.path;
      }

      await sourceFile.copy(destination.path);
      return destination.path;
    } catch (e, stack) {
      debugPrint('[StorageService] saveMediaFile failed: $e\n$stack');
      return '';
    }
  }

  Future<void> deleteMediaFile(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, stack) {
      debugPrint('[StorageService] deleteMediaFile failed: $e\n$stack');
    }
  }

  Future<void> deletePeerMediaDirectory(String peerId) async {
    try {
      final mediaDirectory = _mediaDirectory;
      if (mediaDirectory == null) {
        return;
      }
      final directory = Directory('${mediaDirectory.path}/$peerId');
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e, stack) {
      debugPrint('[StorageService] deletePeerMediaDirectory failed: $e\n$stack');
    }
  }

  bool isManagedMediaPath(String? path) {
    if (path == null || path.isEmpty) {
      return false;
    }
    final mediaDirectory = _mediaDirectory;
    if (mediaDirectory == null) {
      return false;
    }
    return path.startsWith('${mediaDirectory.path}/');
  }

  Future<AppStorageBreakdown> computeAppStorageBreakdown() async {
    await init();
    final rootDirectory = _rootDirectory;
    final databaseDirectory = _databaseDirectory;
    final secureDirectory = _secureDirectory;
    final mediaDirectory = _mediaDirectory;
    final logsDirectory = rootDirectory == null ? null : Directory('${rootDirectory.path}/logs');

    return AppStorageBreakdown(
      mediaFilesBytes: await _directorySize(mediaDirectory),
      messagesDatabaseBytes: await _directorySize(databaseDirectory),
      logsBytes: await _directorySize(logsDirectory),
      settingsAndServiceDataBytes: await _directorySize(secureDirectory),
    );
  }

  Future<void> clearManagedMediaStorage() async {
    await init();
    final summaries = await loadAllChatSummaries();
    for (final summary in summaries) {
      final peerId = (summary['peerId'] as String? ?? '').trim();
      if (peerId.isEmpty) {
        continue;
      }

      final messages = await readChatMessages(peerId);
      var changedMessages = false;
      for (final message in messages) {
        if ((message['localFilePath'] as String?)?.isNotEmpty == true) {
          message['localFilePath'] = null;
          changedMessages = true;
        }
      }
      if (changedMessages) {
        await writeChatMessages(peerId, messages);
      }

      if ((summary['avatarPath'] as String?)?.isNotEmpty == true) {
        final updated = Map<String, dynamic>.from(summary)..['avatarPath'] = null;
        await saveChatSummaryMap(peerId, updated);
      }
    }

    final mediaDirectory = _mediaDirectory;
    if (mediaDirectory != null && await mediaDirectory.exists()) {
      await mediaDirectory.delete(recursive: true);
      await mediaDirectory.create(recursive: true);
    }
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

  Future<int> _directorySize(Directory? directory) async {
    if (directory == null || !await directory.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      try {
        total += await entity.length();
      } catch (_) {
        // Best effort size calculation.
      }
    }
    return total;
  }

  Future<String?> recoverMediaFromLegacy({
    required String peerId,
    required String messageId,
    required String fileName,
    String? previousPath,
  }) async {
    final mediaDirectory = _mediaDirectory;
    if (mediaDirectory == null) {
      return null;
    }

    final candidateDirs = <String>{};
    final prev = previousPath?.trim();
    if (prev != null && prev.isNotEmpty) {
      final prevParent = File(prev).parent.path;
      if (prevParent.isNotEmpty) {
        candidateDirs.add(prevParent);
      }
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidateDirs.add('$home/.peerlink/media/$peerId');
    }

    final tmpDir = Platform.environment['TMPDIR'];
    if (tmpDir != null && tmpDir.isNotEmpty) {
      candidateDirs.add('$tmpDir/peerlink/media/$peerId');
      candidateDirs.add('$tmpDir/.peerlink/media/$peerId');
    }

    final cwd = Directory.current.path;
    candidateDirs.add('$cwd/.peerlink/media/$peerId');
    candidateDirs.add('${Directory.systemTemp.path}/peerlink/media/$peerId');
    candidateDirs.add('${Directory.systemTemp.path}/.peerlink/media/$peerId');

    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final exactCandidates = <String>{
      '$messageId-$safeName',
      if (prev != null && prev.isNotEmpty) File(prev).uri.pathSegments.last,
    };
    final prefix = '$messageId-';

    File? source;
    for (final path in candidateDirs) {
      final dir = Directory(path);
      if (!await dir.exists()) {
        continue;
      }

      for (final name in exactCandidates) {
        if (name.isEmpty) continue;
        final file = File('${dir.path}/$name');
        if (await file.exists()) {
          source = file;
          break;
        }
      }
      if (source != null) {
        break;
      }

      try {
        final entries = await dir.list().where((entity) {
          if (entity is! File) return false;
          final name = entity.uri.pathSegments.isEmpty
              ? ''
              : entity.uri.pathSegments.last;
          return name.startsWith(prefix);
        }).toList();
        if (entries.isNotEmpty) {
          source = entries.first as File;
          break;
        }
      } catch (_) {
        // best effort
      }
    }

    if (source == null) {
      return null;
    }

    final copiedPath = await saveMediaFile(
      peerId: peerId,
      messageId: messageId,
      fileName: fileName,
      sourcePath: source.path,
    );
    if (copiedPath.isEmpty) {
      return null;
    }
    return copiedPath;
  }

  Future<void> _pruneLargeEmbeddedMedia() async {
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

  Future<void> _migrateLegacyGroupStorageFromSettings() async {
    final settings = _boxes[settingsBox];
    final groupMeta = _boxes[groupMetaBox];
    final groupKeys = _boxes[groupKeysBox];
    if (settings == null || groupMeta == null || groupKeys == null) {
      return;
    }

    var settingsChanged = false;
    var groupMetaChanged = false;
    var groupKeysChanged = false;

    final legacyMeta = settings[_legacyGroupMetaSettingsKey];
    if (legacyMeta is Map && groupMeta[_groupMetaStateKey] == null) {
      groupMeta[_groupMetaStateKey] = Map<String, dynamic>.from(legacyMeta);
      groupMetaChanged = true;
    }
    if (settings.remove(_legacyGroupMetaSettingsKey) != null) {
      settingsChanged = true;
    }

    final legacyGroupKeys = settings[_legacyGroupKeysSettingsKey];
    if (legacyGroupKeys is Map && groupKeys[_legacyGroupKeysSettingsKey] == null) {
      groupKeys[_legacyGroupKeysSettingsKey] =
          Map<String, dynamic>.from(legacyGroupKeys);
      groupKeysChanged = true;
    }
    if (settings.remove(_legacyGroupKeysSettingsKey) != null) {
      settingsChanged = true;
    }

    final legacyGroupVersions = settings[_legacyGroupKeyVersionsSettingsKey];
    if (legacyGroupVersions is Map &&
        groupKeys[_legacyGroupKeyVersionsSettingsKey] == null) {
      groupKeys[_legacyGroupKeyVersionsSettingsKey] =
          Map<String, dynamic>.from(legacyGroupVersions);
      groupKeysChanged = true;
    }
    if (settings.remove(_legacyGroupKeyVersionsSettingsKey) != null) {
      settingsChanged = true;
    }

    final keysToMove = settings.keys
        .where(
          (key) =>
              key.startsWith(_groupKeyStoragePrefix) ||
              key.startsWith(_groupKeyVersionStoragePrefix),
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
      await _persist(groupMetaBox);
    }
    if (groupKeysChanged) {
      await _persist(groupKeysBox);
    }
    if (settingsChanged) {
      await _persist(settingsBox);
    }
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
}
