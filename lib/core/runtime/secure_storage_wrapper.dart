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
      return;
    }

    try {
      _fileStorageDirectory = fallbackDirectory;
      await _fileStorageDirectory!.create(recursive: true);

      if (kIsWeb) {
        _useFileStorage = true;
      } else {
        await _tryEnableSecureStorage();
      }

      _initialized = true;
    } catch (_) {
      _useFileStorage = true;
      _initialized = true;
    }
  }

  static Future<void> _tryEnableSecureStorage() async {
    try {
      const storage = peerLinkSecureStorage;
      const probeKey = '__peerlink_storage_probe__';
      await storage.write(key: probeKey, value: 'ok');
      await storage.delete(key: probeKey);
      _secureStorage = storage;
      _useFileStorage = false;
    } catch (_) {
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
    if (_useFileStorage || _secureStorage == null) {
      return _readFromFile(key);
    }

    try {
      final result = await _secureStorage!.read(key: key);
      if (result != null && result.isNotEmpty) {
        await _writeToFile(key, result);
      }
      if (result != null) {
        return result;
      }
      return _readFromFile(key);
    } catch (e) {
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
    if (_useFileStorage || _secureStorage == null) {
      await _writeToFile(key, value);
      return;
    }

    try {
      await _secureStorage!.write(key: key, value: value);
      await _writeToFile(key, value);
    } catch (e) {
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
    } catch (_) {
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
      }
    } catch (_) {
    }
  }

  /// Очищает всё хранилище (для тестов)
  static Future<void> clear() async {
    if (_secureStorage != null && !_useFileStorage) {
    }

    if (_fileStorageDirectory != null) {
      try {
        final files = _fileStorageDirectory!.listSync();
        for (final entity in files) {
          if (entity is File) {
            await entity.delete();
          }
        }
      } catch (_) {
      }
    }
  }
}
