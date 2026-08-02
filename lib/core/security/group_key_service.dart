import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../runtime/storage_service.dart';

abstract class GroupKeyStore {
  Iterable<String> get keys;
  dynamic get(String key);
  Future<void> put(String key, dynamic value);
  Future<void> delete(String key);
}

class SecureStorageGroupKeyStore implements GroupKeyStore {
  final SecureStorageBox _box;

  SecureStorageGroupKeyStore(this._box);

  @override
  Iterable<String> get keys => _box.keys;

  @override
  dynamic get(String key) => _box.get(key);

  @override
  Future<void> put(String key, dynamic value) => _box.put(key, value);

  @override
  Future<void> delete(String key) => _box.delete(key);
}

class GroupKeyRotationResult {
  final String keyBase64;
  final int version;

  const GroupKeyRotationResult({
    required this.keyBase64,
    required this.version,
  });
}

class GroupKeyGcReport {
  final int removedKeys;
  final int removedVersions;

  const GroupKeyGcReport({
    required this.removedKeys,
    required this.removedVersions,
  });
}

class GroupKeyService {
  static const String legacyGroupKeysStorageKey = 'peerlink.group_keys.v1';
  static const String legacyGroupKeyVersionsStorageKey =
      'peerlink.group_key_versions.v1';

  static const String _groupKeyStoragePrefix = 'peerlink.group_key.v2.';
  static const String _groupKeyVersionStoragePrefix =
      'peerlink.group_key_version.v2.';

  final GroupKeyStore _store;
  final Map<String, String> _groupKeyByGroupId = <String, String>{};
  final Map<String, int> _groupKeyVersionByGroupId = <String, int>{};

  GroupKeyService(GroupKeyStore store) : _store = store;

  factory GroupKeyService.forSecureStorageBox(SecureStorageBox settingsBox) {
    return GroupKeyService(SecureStorageGroupKeyStore(settingsBox));
  }

  Future<void> initialize() async {
    _loadFromPerGroupStorage();
    await _migrateLegacyStorageIfNeeded();
  }

  String? keyForGroup(String groupId) {
    return _groupKeyByGroupId[groupId];
  }

  int keyVersionForGroup(String groupId) {
    return _groupKeyVersionByGroupId[groupId] ?? 0;
  }

  Future<String> ensureGroupKey(String groupId) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      throw ArgumentError('groupId must not be empty');
    }
    final existing = _groupKeyByGroupId[normalizedGroupId];
    if (existing != null && existing.isNotEmpty) {
      if ((_groupKeyVersionByGroupId[normalizedGroupId] ?? 0) <= 0) {
        _groupKeyVersionByGroupId[normalizedGroupId] = 1;
        await _writeGroupVersion(normalizedGroupId, 1);
      }
      return existing;
    }

    final keyBase64 = _generateGroupKeyBase64();
    _groupKeyByGroupId[normalizedGroupId] = keyBase64;
    _groupKeyVersionByGroupId[normalizedGroupId] = 1;
    await _writeGroupKey(normalizedGroupId, keyBase64);
    await _writeGroupVersion(normalizedGroupId, 1);
    return keyBase64;
  }

  Future<GroupKeyRotationResult> rotateGroupKey(String groupId) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      throw ArgumentError('groupId must not be empty');
    }
    final nextVersion = (_groupKeyVersionByGroupId[normalizedGroupId] ?? 0) + 1;
    final nextKey = _generateGroupKeyBase64();
    _groupKeyByGroupId[normalizedGroupId] = nextKey;
    _groupKeyVersionByGroupId[normalizedGroupId] = nextVersion;
    await _writeGroupKey(normalizedGroupId, nextKey);
    await _writeGroupVersion(normalizedGroupId, nextVersion);
    return GroupKeyRotationResult(keyBase64: nextKey, version: nextVersion);
  }

  Future<bool> applyIncomingGroupKey({
    required String groupId,
    required String groupKeyBase64,
    required int keyVersion,
  }) async {
    final normalizedGroupId = groupId.trim();
    final normalizedKey = groupKeyBase64.trim();
    if (normalizedGroupId.isEmpty || !_isValidGroupKeyBase64(normalizedKey)) {
      return false;
    }

    final incomingVersion = keyVersion <= 0 ? 1 : keyVersion;
    final currentVersion = _groupKeyVersionByGroupId[normalizedGroupId] ?? 0;
    final currentKey = _groupKeyByGroupId[normalizedGroupId];
    if (incomingVersion < currentVersion) {
      return false;
    }
    if (incomingVersion == currentVersion && currentKey == normalizedKey) {
      return false;
    }

    _groupKeyByGroupId[normalizedGroupId] = normalizedKey;
    _groupKeyVersionByGroupId[normalizedGroupId] = incomingVersion;
    await _writeGroupKey(normalizedGroupId, normalizedKey);
    await _writeGroupVersion(normalizedGroupId, incomingVersion);
    return true;
  }

  Future<void> deleteGroupKeys(String groupId) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) {
      return;
    }
    _groupKeyByGroupId.remove(normalizedGroupId);
    _groupKeyVersionByGroupId.remove(normalizedGroupId);
    await _store.delete(_groupKeyStorageKey(normalizedGroupId));
    await _store.delete(_groupVersionStorageKey(normalizedGroupId));
  }

  Future<GroupKeyGcReport> runGc({required Set<String> activeGroupIds}) async {
    final normalizedActive = activeGroupIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();

    var removedKeys = 0;
    var removedVersions = 0;

    final storedGroupIds = <String>{
      ..._groupKeyByGroupId.keys,
      ..._groupKeyVersionByGroupId.keys,
    };

    for (final groupId in storedGroupIds) {
      if (normalizedActive.contains(groupId)) {
        continue;
      }

      if (_groupKeyByGroupId.remove(groupId) != null) {
        removedKeys += 1;
        await _store.delete(_groupKeyStorageKey(groupId));
      }
      if (_groupKeyVersionByGroupId.remove(groupId) != null) {
        removedVersions += 1;
        await _store.delete(_groupVersionStorageKey(groupId));
      }
    }

    return GroupKeyGcReport(
      removedKeys: removedKeys,
      removedVersions: removedVersions,
    );
  }

  void _loadFromPerGroupStorage() {
    _groupKeyByGroupId.clear();
    _groupKeyVersionByGroupId.clear();

    for (final rawKey in _store.keys) {
      final storageKey = rawKey.trim();
      if (storageKey.isEmpty) {
        continue;
      }

      if (storageKey.startsWith(_groupKeyStoragePrefix)) {
        final groupId = storageKey.substring(_groupKeyStoragePrefix.length);
        if (groupId.isEmpty) {
          continue;
        }
        final rawValue = _store.get(storageKey);
        if (rawValue is String && _isValidGroupKeyBase64(rawValue)) {
          _groupKeyByGroupId[groupId] = rawValue;
        }
        continue;
      }

      if (storageKey.startsWith(_groupKeyVersionStoragePrefix)) {
        final groupId = storageKey.substring(_groupKeyVersionStoragePrefix.length);
        if (groupId.isEmpty) {
          continue;
        }
        final rawValue = _store.get(storageKey);
        final parsed = _parsePositiveInt(rawValue);
        if (parsed != null) {
          _groupKeyVersionByGroupId[groupId] = parsed;
        }
      }
    }
  }

  Future<void> _migrateLegacyStorageIfNeeded() async {
    final legacyKeysRaw = _store.get(legacyGroupKeysStorageKey);
    final legacyVersionsRaw = _store.get(legacyGroupKeyVersionsStorageKey);

    var migratedSomething = false;

    if (legacyKeysRaw is Map) {
      for (final entry in legacyKeysRaw.entries) {
        if (entry.key is! String || entry.value is! String) {
          continue;
        }
        final groupId = (entry.key as String).trim();
        final keyBase64 = (entry.value as String).trim();
        if (groupId.isEmpty || !_isValidGroupKeyBase64(keyBase64)) {
          continue;
        }
        if (_groupKeyByGroupId.containsKey(groupId)) {
          continue;
        }
        _groupKeyByGroupId[groupId] = keyBase64;
        await _writeGroupKey(groupId, keyBase64);
        migratedSomething = true;
      }
    }

    if (legacyVersionsRaw is Map) {
      for (final entry in legacyVersionsRaw.entries) {
        if (entry.key is! String) {
          continue;
        }
        final groupId = (entry.key as String).trim();
        if (groupId.isEmpty) {
          continue;
        }
        final parsed = _parsePositiveInt(entry.value);
        if (parsed == null) {
          continue;
        }
        if ((_groupKeyVersionByGroupId[groupId] ?? 0) >= parsed) {
          continue;
        }
        _groupKeyVersionByGroupId[groupId] = parsed;
        await _writeGroupVersion(groupId, parsed);
        migratedSomething = true;
      }
    }

    // Ensure default version for migrated keys without explicit version.
    for (final groupId in _groupKeyByGroupId.keys) {
      if ((_groupKeyVersionByGroupId[groupId] ?? 0) > 0) {
        continue;
      }
      _groupKeyVersionByGroupId[groupId] = 1;
      await _writeGroupVersion(groupId, 1);
      migratedSomething = true;
    }

    if (migratedSomething || legacyKeysRaw != null || legacyVersionsRaw != null) {
      await _store.delete(legacyGroupKeysStorageKey);
      await _store.delete(legacyGroupKeyVersionsStorageKey);
    }
  }

  Future<void> _writeGroupKey(String groupId, String keyBase64) async {
    await _store.put(_groupKeyStorageKey(groupId), keyBase64);
  }

  Future<void> _writeGroupVersion(String groupId, int version) async {
    await _store.put(_groupVersionStorageKey(groupId), version);
  }

  static String _groupKeyStorageKey(String groupId) {
    return '$_groupKeyStoragePrefix$groupId';
  }

  static String _groupVersionStorageKey(String groupId) {
    return '$_groupKeyVersionStoragePrefix$groupId';
  }

  static int? _parsePositiveInt(dynamic value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  static bool _isValidGroupKeyBase64(String value) {
    try {
      final decoded = base64Decode(value);
      return decoded.length == 32;
    } catch (_) {
      return false;
    }
  }

  static String _generateGroupKeyBase64() {
    final random = Random.secure();
    final key = Uint8List(32);
    for (var i = 0; i < key.length; i++) {
      key[i] = random.nextInt(256);
    }
    return base64Encode(key);
  }
}
