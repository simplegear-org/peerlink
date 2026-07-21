import 'dart:async';
import 'dart:io';

import 'storage_service.dart';

enum AppLogLevel { errorsOnly, verbose }

class AppFileLogger {
  AppFileLogger._();

  static const String logLevelSettingsKey = 'app_log_level';
  static const int _maxLogFileBytes = 1024 * 1024;
  static const int _maxArchivedLogFiles = 5;
  static const Duration _flushInterval = Duration(milliseconds: 700);
  static AppLogLevel _logLevel = AppLogLevel.errorsOnly;
  static final RegExp _warningOrErrorPattern = RegExp(
    r'(warn|warning|error|fail|failed|exception|timeout|invalid|denied|fatal)',
    caseSensitive: false,
  );

  static final AppFileLogger instance = AppFileLogger._();

  Directory? _logsDirectory;
  File? _logFile;
  IOSink? _sink;
  bool _initialized = false;
  Future<void>? _initializationFuture;
  Future<void> _writeQueue = Future<void>.value();
  Timer? _flushTimer;

  static AppLogLevel get currentLevel => _logLevel;

  static AppLogLevel parseStoredLevel(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    return switch (value) {
      'errors' || 'errors_only' || 'errorsonly' => AppLogLevel.errorsOnly,
      'verbose' => AppLogLevel.verbose,
      _ => AppLogLevel.verbose,
    };
  }

  static String storageValueFor(AppLogLevel level) {
    return switch (level) {
      AppLogLevel.errorsOnly => 'errors_only',
      AppLogLevel.verbose => 'verbose',
    };
  }

  static Future<void> configureFromStorage(StorageService storage) async {
    final settings = storage.getSettings();
    _logLevel = parseStoredLevel(settings.get(logLevelSettingsKey));
  }

  static Future<void> setLogLevel(
    AppLogLevel level, {
    StorageService? storage,
    bool persist = true,
  }) async {
    _logLevel = level;
    if (!persist || storage == null) {
      return;
    }
    await storage.getSettings().put(
      logLevelSettingsKey,
      storageValueFor(level),
    );
  }

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
    }();
    await _initializationFuture;
    _initializationFuture = null;
  }

  static bool shouldLog(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    int? level,
  }) {
    if (_logLevel == AppLogLevel.verbose) {
      return true;
    }
    if (error != null || stackTrace != null) {
      return true;
    }
    if (level != null && level >= 900) {
      return true;
    }
    return _warningOrErrorPattern.hasMatch(message);
  }

  static void log(
    String message, {
    String name = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!shouldLog(message, error: error, stackTrace: stackTrace)) {
      return;
    }
    unawaited(
      instance._appendStructured(
        name: name,
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  static void raw(String message, {String name = 'raw'}) {}

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
    _writeQueue = _writeQueue.then((_) async {
      await initialize();
      _flushTimer?.cancel();
      _flushTimer = null;
      await _sink?.flush();
      await _sink?.close();
      final file = _logFile;
      if (file != null) {
        await file.writeAsString('');
        _sink = file.openWrite(mode: FileMode.append);
      }
    });
    await _writeQueue;
  }

  Future<void> clearAll() async {
    _writeQueue = _writeQueue.then((_) async {
      await initialize();
      final logsDirectory = _logsDirectory;
      if (logsDirectory == null) {
        return;
      }

      _flushTimer?.cancel();
      _flushTimer = null;
      await _sink?.flush();
      await _sink?.close();
      _sink = null;

      if (await logsDirectory.exists()) {
        await for (final entity in logsDirectory.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      } else {
        await logsDirectory.create(recursive: true);
      }

      _logFile = File('${logsDirectory.path}/app.log');
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
      _sink = _logFile!.openWrite(mode: FileMode.append);
    });
    await _writeQueue;
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
        _scheduleFlush();
      } catch (_) {}
    });
    await _writeQueue;
  }

  void _scheduleFlush() {
    if (_flushTimer?.isActive ?? false) {
      return;
    }
    _flushTimer = Timer(_flushInterval, () {
      _flushTimer = null;
      unawaited(_flushSink());
    });
  }

  Future<void> _flushSink() async {
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _sink?.flush();
      } catch (_) {}
    });
    await _writeQueue;
  }

  Future<void> _rotateIfNeeded() async {
    final file = _logFile;
    final logsDirectory = _logsDirectory;
    if (file == null || logsDirectory == null) {
      return;
    }

    if (!await file.exists()) {
      await file.create(recursive: true);
    }

    final currentSize = await file.length();
    if (currentSize >= _maxLogFileBytes) {
      _flushTimer?.cancel();
      _flushTimer = null;
      await _sink?.flush();
      await _sink?.close();
      _sink = null;

      final rotatedName = 'app_${DateTime.now().millisecondsSinceEpoch}.log';
      final rotatedFile = File('${logsDirectory.path}/$rotatedName');
      await file.rename(rotatedFile.path);
      _logFile = File('${logsDirectory.path}/app.log');
      await _logFile!.create(recursive: true);
      _sink = _logFile!.openWrite(mode: FileMode.append);
    }

    final archived =
        logsDirectory
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
      } catch (_) {}
    }
  }

  Future<Directory> _resolveRootDirectory() async {
    final home = Platform.environment['HOME'];
    final tmpDir = Platform.environment['TMPDIR'];
    if ((Platform.isIOS || Platform.isMacOS) &&
        home != null &&
        home.isNotEmpty) {
      return Directory('$home/Library/Application Support/peerlink');
    }
    if (home != null && home.isNotEmpty) {
      return Directory('$home/.peerlink');
    }
    if (tmpDir != null && tmpDir.isNotEmpty) {
      return Directory('$tmpDir/peerlink');
    }
    final currentPath = Directory.current.path;
    final safeCurrentPath = currentPath == '/'
        ? Directory.systemTemp.path
        : currentPath;
    return Directory('$safeCurrentPath/.peerlink');
  }
}
