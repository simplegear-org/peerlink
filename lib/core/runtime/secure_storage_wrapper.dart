import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage_platform_options.dart';

class SecureStorageWrapper {
  static FlutterSecureStorage? _secureStorage;
  static Directory? _fileStorageDirectory;
  static bool _initialized = false;
  static bool _useFileStorage = false;

  /// Инициализирует хранилище.
  ///
  /// Основной путь: `flutter_secure_storage`.
  /// Fallback: JSON-файлы в стабильной директории приложения.
  static Future<void> initialize({required Directory fallbackDirectory}) async {
    if (_initialized) {
      debugPrint('[SecureStorageWrapper] Already initialized');
      return;
    }

    debugPrint('[SecureStorageWrapper] Initializing...');

    try {
      _fileStorageDirectory = fallbackDirectory;
      await _fileStorageDirectory!.create(recursive: true);
      debugPrint(
        '[SecureStorageWrapper] File storage directory ready: ${_fileStorageDirectory!.path}',
      );

      if (kIsWeb) {
        _useFileStorage = true;
      } else {
        await _tryEnableSecureStorage();
      }

      _initialized = true;
      debugPrint(
        '[SecureStorageWrapper] Initialized (useFileStorage: $_useFileStorage)',
      );
    } catch (e, stack) {
      debugPrint('[SecureStorageWrapper] Failed to initialize: $e\n$stack');
      _useFileStorage = true;
      _initialized = true;
    }
  }

  static Future<void> _tryEnableSecureStorage() async {
    try {
      debugPrint(
        '[SecureStorageWrapper] Attempting to initialize secure storage...',
      );
      const storage = peerLinkSecureStorage;
      const probeKey = '__peerlink_storage_probe__';
      await storage.write(key: probeKey, value: 'ok');
      await storage.delete(key: probeKey);
      _secureStorage = storage;
      _useFileStorage = false;
      debugPrint('[SecureStorageWrapper] Using secure storage');
    } catch (e, stack) {
      debugPrint(
        '[SecureStorageWrapper] Secure storage unavailable, using file storage: $e\n$stack',
      );
      _useFileStorage = true;
      _secureStorage = null;
    }
  }

  /// Проверяет, доступно ли хранилище
  static bool get isAvailable => _initialized;

  /// Читает значение из хранилища
  static Future<String?> read(String key) async {
    if (!_initialized) {
      throw StateError(
        'SecureStorageWrapper.initialize() must be called first',
      );
    }

    debugPrint('[SecureStorageWrapper] Reading key: $key');

    if (_useFileStorage || _secureStorage == null) {
      final result = await _readFromFile(key);
      debugPrint(
        '[SecureStorageWrapper] Read from file: ${result != null ? "${result.length} bytes" : "null"}',
      );
      return result;
    }

    try {
      final result = await _secureStorage!.read(key: key);
      if (result != null && result.isNotEmpty) {
        await _writeToFile(key, result);
      }
      debugPrint(
        '[SecureStorageWrapper] Read from secure storage: ${result != null ? "${result.length} bytes" : "null"}',
      );
      if (result != null) {
        return result;
      }
      return _readFromFile(key);
    } catch (e) {
      debugPrint('[SecureStorageWrapper] Read failed, fallback to file: $e');
      _useFileStorage = true;
      return _readFromFile(key);
    }
  }

  /// Записывает значение в хранилище
  static Future<void> write(String key, String value) async {
    if (!_initialized) {
      throw StateError(
        'SecureStorageWrapper.initialize() must be called first',
      );
    }

    debugPrint(
      '[SecureStorageWrapper] Writing key: $key (${value.length} bytes), useFileStorage: $_useFileStorage',
    );

    if (_useFileStorage || _secureStorage == null) {
      await _writeToFile(key, value);
      return;
    }

    try {
      await _secureStorage!.write(key: key, value: value);
      await _writeToFile(key, value);
      debugPrint('[SecureStorageWrapper] Written to secure storage');
    } catch (e) {
      debugPrint('[SecureStorageWrapper] Write failed, fallback to file: $e');
      _useFileStorage = true;
      await _writeToFile(key, value);
    }
  }

  /// Удаляет значение из хранилища
  static Future<void> delete(String key) async {
    if (!_initialized) {
      throw StateError(
        'SecureStorageWrapper.initialize() must be called first',
      );
    }

    if (_useFileStorage || _secureStorage == null) {
      await _deleteFromFile(key);
      return;
    }

    try {
      await _secureStorage!.delete(key: key);
      await _deleteFromFile(key);
    } catch (e) {
      debugPrint('[SecureStorageWrapper] Delete failed, fallback to file: $e');
      _useFileStorage = true;
      await _deleteFromFile(key);
    }
  }

  /// Читает из файла
  static Future<String?> _readFromFile(String key) async {
    if (_fileStorageDirectory == null) {
      return null;
    }

    try {
      final file = File('${_fileStorageDirectory!.path}/$key.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return content;
      }
      return null;
    } catch (e) {
      debugPrint('[SecureStorageWrapper] File read failed: $e');
      return null;
    }
  }

  /// Записывает в файл
  static Future<void> _writeToFile(String key, String value) async {
    if (_fileStorageDirectory == null) {
      return;
    }

    try {
      final file = File('${_fileStorageDirectory!.path}/$key.json');
      await file.writeAsString(value);
      debugPrint('[SecureStorageWrapper] Written to file: $key.json');
    } catch (e) {
      debugPrint('[SecureStorageWrapper] File write failed: $e');
    }
  }

  /// Удаляет файл
  static Future<void> _deleteFromFile(String key) async {
    if (_fileStorageDirectory == null) {
      return;
    }

    try {
      final file = File('${_fileStorageDirectory!.path}/$key.json');
      if (await file.exists()) {
        await file.delete();
        debugPrint('[SecureStorageWrapper] Deleted file: $key.json');
      }
    } catch (e) {
      debugPrint('[SecureStorageWrapper] File delete failed: $e');
    }
  }

  /// Очищает всё хранилище (для тестов)
  static Future<void> clear() async {
    if (_secureStorage != null && !_useFileStorage) {
      debugPrint(
        '[SecureStorageWrapper] Clear not supported for secure storage',
      );
    }

    if (_fileStorageDirectory != null) {
      try {
        final files = _fileStorageDirectory!.listSync();
        for (final entity in files) {
          if (entity is File) {
            await entity.delete();
          }
        }
        debugPrint('[SecureStorageWrapper] Cleared file storage');
      } catch (e) {
        debugPrint('[SecureStorageWrapper] File clear failed: $e');
      }
    }
  }
}
