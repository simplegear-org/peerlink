import 'dart:async';
import 'dart:io' show Platform;

import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/firebase/firebase_service.dart';
import 'core/firebase/firebase_messaging_service.dart';
import 'core/messaging/chat_service.dart';
import 'core/node/node_facade.dart';
import 'core/notification/notification_service.dart';
import 'core/runtime/app_bootstrap_coordinator.dart';
import 'core/runtime/app_file_logger.dart';
import 'core/runtime/network_dependencies.dart';
import 'core/runtime/storage_service.dart';
import 'ui/theme/app_theme.dart';
import 'ui/ui_app.dart';

NodeFacade? _globalNodeFacade;
const _enableIosFcm = bool.fromEnvironment('ENABLE_IOS_FCM', defaultValue: false);

Future<NodeFacade> _ensureGlobalNodeFacade() async {
  if (_globalNodeFacade != null) {
    return _globalNodeFacade!;
  }

  final storage = StorageService();
  await storage.init();

  final deps = await NetworkDependencies.create();
  _globalNodeFacade = deps.nodeFacade;
  return _globalNodeFacade!;
}

Future<void> _pollRelayAndNotify() async {
  final nodeFacade = await _ensureGlobalNodeFacade();

  StreamSubscription? messageSub;
  messageSub = nodeFacade.messageEvents.listen((event) async {
    final payload = event.payload;
    if (payload is ChatMessage) {
      await NotificationService.instance.showMessageNotification(
        fromPeerId: payload.peerId,
        message: payload.text,
      );
    }
  });

  try {
    await nodeFacade.pollRelay();
  } catch (e) {
    AppFileLogger.log('[main] pollRelayAndNotify error=$e', name: 'main');
  } finally {
    await messageSub.cancel();
  }
}

Future<void> backgroundFetchHeadlessTask(String taskId) async {
  AppFileLogger.log('[background_fetch] task=$taskId', name: 'background_fetch');

  try {
    await _pollRelayAndNotify();
  } catch (e) {
    AppFileLogger.log('[background_fetch] pollRelay error=$e', name: 'background_fetch');
  }

  BackgroundFetch.finish(taskId);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppFileLogger.instance.initialize();
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.isNotEmpty) {
      AppFileLogger.raw(message, name: 'debugPrint');
    }
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppFileLogger.log(
      '[flutter_error] ${details.exceptionAsString()}',
      name: 'flutter_error',
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    AppFileLogger.log(
      '[platform_error] $error',
      name: 'platform_error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  runZonedGuarded(
    () => runApp(const _BootstrapApp()),
    (Object error, StackTrace stackTrace) {
      AppFileLogger.log(
        '[zone_error] $error',
        name: 'zone_error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  NetworkDependencies? _deps;
  StorageService? _storage;
  FirebaseMessagingService? _firebaseMessagingService;
  StreamSubscription<String>? _fcmTokenSubscription;
  Object? _bootstrapError;
  String _bootstrapStage = 'Подготовка запуска...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    try {
      AppFileLogger.log('[main] bootstrap started');
      
      if (mounted) {
        setState(() {
          _bootstrapStage = 'Инициализация хранилища...';
        });
      }
      AppFileLogger.log('[main] creating StorageService');
      final storage = StorageService();
      AppFileLogger.log('[main] initializing StorageService');
      await storage.init();
      AppFileLogger.log('[main] StorageService initialized');
      _storage = storage;

      if (mounted) {
        setState(() {
          _bootstrapStage = 'Инициализация Firebase...';
        });
      }
      AppFileLogger.log('[main] initializing Firebase');
      final firebaseService = FirebaseService();
      final firebaseReady = await firebaseService.initialize();
      AppFileLogger.log('[main] Firebase ready: $firebaseReady');

      if (firebaseReady && _shouldInitializeFcm()) {
        if (mounted) {
          setState(() {
            _bootstrapStage = 'Инициализация FCM...';
          });
        }
        try {
          final firebaseMessagingService = FirebaseMessagingService(
            storage: storage,
          );
          _firebaseMessagingService = firebaseMessagingService;
          await firebaseMessagingService.initialize();
          _fcmTokenSubscription?.cancel();
          _fcmTokenSubscription = firebaseMessagingService.tokenStream.listen(
            (token) {
              final facade = _deps?.nodeFacade ?? _globalNodeFacade;
              if (facade == null) {
                return;
              }
              unawaited(facade.updateFcmToken(token));
            },
          );
        } catch (fcmError, fcmStack) {
          AppFileLogger.log(
            '[main] FCM initialization skipped error=$fcmError',
            stackTrace: fcmStack,
          );
        }
      }

      if (mounted) {
        setState(() {
          _bootstrapStage = 'Инициализация уведомлений...';
        });
      }
      AppFileLogger.log('[main] initializing notifications');
      final notificationPermission = await NotificationService.instance.init();
      AppFileLogger.log('[main] notificationPermission=$notificationPermission');

      if (mounted) {
        setState(() {
          _bootstrapStage = 'Инициализация сети...';
        });
      }
      AppFileLogger.log('[main] creating NetworkDependencies');
      final deps = await NetworkDependencies.create().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('NetworkDependencies.create timed out after 30s');
        },
      );
      AppFileLogger.log('[main] NetworkDependencies created');
      _globalNodeFacade = deps.nodeFacade;
      unawaited(
        deps.nodeFacade.updateFcmToken(_firebaseMessagingService?.cachedToken),
      );

      if (!mounted) {
        return;
      }
      AppFileLogger.log('[main] bootstrap ui ready');
      setState(() {
        _storage = storage;
        _deps = deps;
        _bootstrapStage = 'Запуск интерфейса...';
      });

      unawaited(_postBootstrap(storage, deps));
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[main] bootstrap failed error=$error',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _bootstrapError = error;
      });
    }
  }

  Future<void> _retryBootstrap() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _bootstrapError = null;
      _deps = null;
    });
    await _bootstrap();
  }

  @override
  void dispose() {
    final fcmSub = _fcmTokenSubscription;
    if (fcmSub != null) {
      unawaited(fcmSub.cancel());
    }
    final messaging = _firebaseMessagingService;
    if (messaging != null) {
      unawaited(messaging.dispose());
    }
    super.dispose();
  }

  Future<void> _postBootstrap(
    StorageService storage,
    NetworkDependencies deps,
  ) async {
    try {
      AppFileLogger.log('[main] postBootstrap:start');
      final coordinator = AppBootstrapCoordinator(
        storage: storage,
        deps: deps,
      );
      await coordinator.postBootstrap(
        configureBackgroundFetch: _configureBackgroundFetch,
      );
      AppFileLogger.log('[main] postBootstrap:done');
      if (!mounted) {
        return;
      }
      setState(() {
        _bootstrapStage = 'Готово';
      });
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[main] postBootstrap failed error=$error',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = _deps;
    final storage = _storage;
    AppFileLogger.log(
      '[main] build depsReady=${deps != null} storageReady=${storage != null} stage=$_bootstrapStage',
    );
    return MaterialApp(
      title: 'PeerLink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: deps != null && storage != null
          ? UiApp(
              facade: deps.nodeFacade,
              storage: storage,
            )
          : Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_bootstrapError == null) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text('Запуск PeerLink...'),
                          const SizedBox(height: 8),
                          Text(
                            _bootstrapStage,
                            textAlign: TextAlign.center,
                          ),
                        ] else ...[
                          const Icon(Icons.error_outline, size: 44),
                          const SizedBox(height: 16),
                          Text(
                            'Ошибка запуска: $_bootstrapError',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              unawaited(_retryBootstrap());
                            },
                            child: const Text('Повторить'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

bool _shouldInitializeFcm() {
  if (kIsWeb) {
    return true;
  }

  if (Platform.isIOS || Platform.isMacOS) {
    return _enableIosFcm;
  }

  return true;
}

Future<void> _configureBackgroundFetch() async {
  await AppBootstrapCoordinator.configureBackgroundFetch(
    onFetch: _pollRelayAndNotify,
    onHeadlessTask: backgroundFetchHeadlessTask,
  );
}
