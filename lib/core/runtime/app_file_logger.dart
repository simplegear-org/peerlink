import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

class AppFileLogger {
  AppFileLogger._();

  static const int _maxLogFileBytes = 1024 * 1024;
  static const int _maxArchivedLogFiles = 5;

  static final AppFileLogger instance = AppFileLogger._();

  Directory? _logsDirectory;
  File? _logFile;
  IOSink? _sink;
  bool _initialized = false;
  Future<void>? _initializationFuture;
  Future<void> _writeQueue = Future<void>.value();

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final current = _initializationFuture;
    if (current != null) {
      await current;
      return;
    }
    _initializationFuture = () async {
      final root = await _resolveRootDirectory();
      final logsDirectory = Directory('${root.path}/logs');
      await logsDirectory.create(recursive: true);
      _logsDirectory = logsDirectory;
      _logFile = File('${logsDirectory.path}/app.log');
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
      await _rotateIfNeeded();
      _sink = _logFile!.openWrite(mode: FileMode.append);
      _initialized = true;
      _sink?.writeln(
        '[${DateTime.now().toIso8601String()}][logger] initialized path=${_logFile!.path}',
      );
      await _sink?.flush();
    }();
    await _initializationFuture;
    _initializationFuture = null;
  }

  static void log(
    String message, {
    String name = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(message, name: name, error: error, stackTrace: stackTrace);
    unawaited(
      instance._appendStructured(
        name: name,
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  static void raw(
    String message, {
    String name = 'raw',
  }) {
    unawaited(instance._appendRaw('[${DateTime.now().toIso8601String()}][$name] $message'));
  }

  Future<String?> getLogFilePath() async {
    await initialize();
    return _logFile?.path;
  }

  Future<String> readLog() async {
    await initialize();
    final file = _logFile;
    if (file == null || !await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<void> clear() async {
    await initialize();
    await _sink?.flush();
    await _sink?.close();
    final file = _logFile;
    if (file != null) {
      await file.writeAsString('');
      _sink = file.openWrite(mode: FileMode.append);
      await _appendRaw('[${DateTime.now().toIso8601String()}][logger] log cleared');
    }
  }

  Future<void> clearAll() async {
    await initialize();
    final logsDirectory = _logsDirectory;
    if (logsDirectory == null) {
      return;
    }

    await _sink?.flush();
    await _sink?.close();
    _sink = null;

    try {
      if (await logsDirectory.exists()) {
        await for (final entity in logsDirectory.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {
            // Best effort log cleanup.
          }
        }
      } else {
        await logsDirectory.create(recursive: true);
      }
    } finally {
      _logFile = File('${logsDirectory.path}/app.log');
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
      _sink = _logFile!.openWrite(mode: FileMode.append);
      _sink?.writeln(
        '[${DateTime.now().toIso8601String()}][logger] logs cleared',
      );
      await _sink?.flush();
    }
  }

  Future<void> _appendStructured({
    required String name,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final buffer = StringBuffer()
      ..write('[')
      ..write(DateTime.now().toIso8601String())
      ..write('][')
      ..write(name)
      ..write('] ')
      ..write(message);
    if (error != null) {
      buffer
        ..write(' error=')
        ..write(error);
    }
    if (stackTrace != null) {
      buffer
        ..write('\n')
        ..write(stackTrace);
    }
    await _appendRaw(buffer.toString());
  }

  Future<void> _appendRaw(String line) async {
    _writeQueue = _writeQueue.then((_) async {
      try {
        await initialize();
        await _rotateIfNeeded();
        _sink?.writeln(line);
        await _sink?.flush();
      } catch (error) {
        if (kDebugMode) {
          developer.log('[logger] append failed: $error', name: 'AppFileLogger');
        }
      }
    });
    await _writeQueue;
  }

  Future<void> _rotateIfNeeded({bool forceCleanupOnly = false}) async {
    final file = _logFile;
    final logsDirectory = _logsDirectory;
    if (file == null || logsDirectory == null) {
      return;
    }

    if (!await file.exists()) {
      await file.create(recursive: true);
    }

    if (!forceCleanupOnly) {
      final currentSize = await file.length();
      if (currentSize >= _maxLogFileBytes) {
        await _sink?.flush();
        await _sink?.close();
        _sink = null;

        final rotatedName = 'app_${DateTime.now().millisecondsSinceEpoch}.log';
        final rotatedFile = File('${logsDirectory.path}/$rotatedName');
        await file.rename(rotatedFile.path);
        _logFile = File('${logsDirectory.path}/app.log');
        await _logFile!.create(recursive: true);
        _sink = _logFile!.openWrite(mode: FileMode.append);
        _sink?.writeln(
          '[${DateTime.now().toIso8601String()}][logger] rotated previous=${rotatedFile.path}',
        );
        await _sink?.flush();
      }
    }

    final archived = logsDirectory
        .listSync()
        .whereType<File>()
        .where((entry) {
          final name = entry.uri.pathSegments.isEmpty
              ? entry.path
              : entry.uri.pathSegments.last;
          return name.startsWith('app_') && name.endsWith('.log');
        })
        .toList(growable: false)
      ..sort((a, b) => b.path.compareTo(a.path));

    if (archived.length <= _maxArchivedLogFiles) {
      return;
    }

    for (final file in archived.skip(_maxArchivedLogFiles)) {
      try {
        await file.delete();
      } catch (_) {
        // Keep logger resilient: stale archives are non-critical.
      }
    }
  }

  Future<Directory> _resolveRootDirectory() async {
    final home = Platform.environment['HOME'];
    final tmpDir = Platform.environment['TMPDIR'];
    if ((Platform.isIOS || Platform.isMacOS) && home != null && home.isNotEmpty) {
      return Directory('$home/Library/Application Support/peerlink');
    }
    if (home != null && home.isNotEmpty) {
      return Directory('$home/.peerlink');
    }
    if (tmpDir != null && tmpDir.isNotEmpty) {
      return Directory('$tmpDir/peerlink');
    }
    final currentPath = Directory.current.path;
    final safeCurrentPath = currentPath == '/' ? Directory.systemTemp.path : currentPath;
    return Directory('$safeCurrentPath/.peerlink');
  }
}
