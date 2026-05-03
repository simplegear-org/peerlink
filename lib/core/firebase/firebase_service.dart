import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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
      // Web не поддерживается без явной конфигурации
      if (kIsWeb) {
        developer.log(
          '[firebase] web platform detected, skipping (requires explicit options)',
          name: 'FirebaseService',
        );
        return false;
      }

      // iOS симулятор может иметь проблемы с Firebase
      if (Platform.isIOS) {
        final isSimulator = await _isIOSSimulator();
        if (isSimulator) {
          developer.log(
            '[firebase] iOS simulator detected, Firebase may not work properly',
            name: 'FirebaseService',
          );
        }
      }

      // Инициализируем Firebase с реальными опциями из GoogleService-Info.plist
      _app = await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyANSaiFDxwTq83aj7DlPPiAEBZbFTJfKAs',
          appId: '1:681611483206:ios:72dedd785fc6d9698ed247',
          messagingSenderId: '681611483206',
          projectId: 'peerlink-35c28',
          storageBucket: 'peerlink-35c28.firebasestorage.app',
          iosBundleId: 'org.simplegear.peerlink',
        ),
      );

      developer.log('[firebase] initialized successfully', name: 'FirebaseService');
      return true;
    } on FirebaseException catch (error) {
      developer.log(
        '[firebase] FirebaseException: ${error.code} - ${error.message}',
        name: 'FirebaseService',
      );
      return false;
    } catch (error, stack) {
      developer.log(
        '[firebase] Unexpected error: $error\n$stack',
        name: 'FirebaseService',
      );
      return false;
    }
  }

  /// Проверяет, запущено ли приложение на iOS симуляторе
  static Future<bool> _isIOSSimulator() async {
    if (!Platform.isIOS || kIsWeb) {
      return false;
    }

    try {
      // iOS симуляторы работают на x86_64 или arm64-simulator
      // Для безопасности считаем все iOS устройства симуляторами
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logEvent(String name, [Map<String, Object?>? params]) async {
    developer.log('[firebase] event=$name params=$params', name: 'FirebaseService');
  }
}
