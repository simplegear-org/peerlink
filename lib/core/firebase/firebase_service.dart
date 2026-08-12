import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../runtime/app_file_logger.dart';

class FirebaseService {
  FirebaseApp? _app;
  bool _initializationAttempted = false;

  bool get isInitialized => _app != null;

  Future<FirebaseApp> get app async {
    if (_app != null) {
      return _app!;
    }

    throw StateError('Firebase not initialized');
  }

  /// Инициализирует Firebase
  /// Возвращает true если успешно, false если Firebase не доступен (нет конфигурации)
  Future<bool> initialize() async {
    if (_initializationAttempted) {
      return _app != null;
    }

    _initializationAttempted = true;

    try {
      _log('initialize start platform=${Platform.operatingSystem}');

      if (Firebase.apps.isNotEmpty) {
        _app = Firebase.app();
        _log('reuse existing default app name=${_app!.name}');
        return true;
      }

      // Web не поддерживается без явной конфигурации
      if (kIsWeb) {
        _log('web platform detected, skipping (requires explicit options)');
        return false;
      }

      // Используем нативный платформенный конфиг (GoogleService-Info.plist/google-services.json).
      _app = await Firebase.initializeApp();

      _log('initialized successfully');
      return true;
    } on FirebaseException catch (error) {
      _log(
        'FirebaseException code=${error.code} message=${error.message}',
        error: error,
      );
      return false;
    } catch (error, stack) {
      _log('Unexpected error: $error', error: error, stackTrace: stack);
      return false;
    }
  }

  Future<void> logEvent(String name, [Map<String, Object?>? params]) async {
    _log('event=$name params=$params');
  }

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    AppFileLogger.log(
      '[firebase] $message',
      name: 'FirebaseService',
      error: error,
      stackTrace: stackTrace,
    );
    developer.log(
      '[firebase] $message',
      name: 'FirebaseService',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
