import 'dart:async';
import 'dart:io' show Platform;

import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/firebase/firebase_service.dart';
import 'core/firebase/firebase_messaging_service.dart';
import 'core/messaging/chat_service.dart';
import 'core/node/node_facade.dart';
import 'core/notification/notification_service.dart';
import 'core/runtime/app_bootstrap_coordinator.dart';
import 'core/runtime/app_file_logger.dart';
import 'core/runtime/network_dependencies.dart';
import 'core/runtime/storage_service.dart';
import 'ui/localization/app_language.dart';
import 'ui/localization/app_strings.dart';
import 'ui/state/app_appearance_controller.dart';
import 'ui/state/app_locale_controller.dart';
import 'ui/theme/app_appearance.dart';
import 'ui/theme/app_theme.dart';
import 'ui/ui_app.dart';

NodeFacade? _globalNodeFacade;
const _enableIosFcm = bool.fromEnvironment(
  'ENABLE_IOS_FCM',
  defaultValue: false,
);

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
  AppFileLogger.log(
    '[background_fetch] task=$taskId',
    name: 'background_fetch',
  );

  try {
    await _pollRelayAndNotify();
  } catch (e) {
    AppFileLogger.log(
      '[background_fetch] pollRelay error=$e',
      name: 'background_fetch',
    );
  }

  BackgroundFetch.finish(taskId);
}

Future<void> main() async {
  runZonedGuarded(
    () async {
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
      PlatformDispatcher.instance.onError =
          (Object error, StackTrace stackTrace) {
            AppFileLogger.log(
              '[platform_error] $error',
              name: 'platform_error',
              error: error,
              stackTrace: stackTrace,
            );
            return true;
          };
      runApp(const _BootstrapApp());
    },
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
  AppAppearanceController? _appearanceController;
  AppLocaleController? _localeController;
  FirebaseMessagingService? _firebaseMessagingService;
  StreamSubscription<String>? _fcmTokenSubscription;
  Object? _bootstrapError;
  String _bootstrapStage = const AppStrings(AppLanguage.ru).launchPreparing;

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
          _bootstrapStage = const AppStrings(AppLanguage.ru).launchStorage;
        });
      }
      AppFileLogger.log('[main] creating StorageService');
      final storage = StorageService();
      AppFileLogger.log('[main] initializing StorageService');
      await storage.init();
      AppFileLogger.log('[main] StorageService initialized');
      _storage = storage;
      final appearanceController = AppAppearanceController(storage: storage);
      await appearanceController.initialize();
      _appearanceController = appearanceController;
      final localeController = AppLocaleController(storage: storage);
      await localeController.initialize();
      _localeController = localeController;

      if (mounted) {
        setState(() {
          _bootstrapStage = AppStrings(localeController.current).launchFirebase;
        });
      }
      AppFileLogger.log('[main] initializing Firebase');
      final firebaseService = FirebaseService();
      final firebaseReady = await firebaseService.initialize();
      AppFileLogger.log('[main] Firebase ready: $firebaseReady');

      if (firebaseReady && _shouldInitializeFcm()) {
        if (mounted) {
          setState(() {
            _bootstrapStage = AppStrings(localeController.current).launchFcm;
          });
        }
        try {
          final firebaseMessagingService = FirebaseMessagingService(
            storage: storage,
          );
          _firebaseMessagingService = firebaseMessagingService;
          await firebaseMessagingService.initialize();
          _fcmTokenSubscription?.cancel();
          _fcmTokenSubscription = firebaseMessagingService.tokenStream.listen((
            token,
          ) {
            final facade = _deps?.nodeFacade ?? _globalNodeFacade;
            if (facade == null) {
              return;
            }
            unawaited(facade.updateFcmToken(token));
          });
        } catch (fcmError, fcmStack) {
          AppFileLogger.log(
            '[main] FCM initialization skipped error=$fcmError',
            stackTrace: fcmStack,
          );
        }
      }

      if (mounted) {
        setState(() {
          _bootstrapStage = AppStrings(
            localeController.current,
          ).launchNotifications;
        });
      }
      AppFileLogger.log('[main] initializing notifications');
      final notificationPermission = await NotificationService.instance.init();
      AppFileLogger.log(
        '[main] notificationPermission=$notificationPermission',
      );

      if (mounted) {
        setState(() {
          _bootstrapStage = AppStrings(localeController.current).launchNetwork;
        });
      }
      AppFileLogger.log('[main] creating NetworkDependencies');
      final deps = await NetworkDependencies.create().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            'NetworkDependencies.create timed out after 30s',
          );
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
        _bootstrapStage = AppStrings(localeController.current).launchUi;
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
    _appearanceController?.dispose();
    _localeController?.dispose();
    super.dispose();
  }

  Future<void> _postBootstrap(
    StorageService storage,
    NetworkDependencies deps,
  ) async {
    try {
      AppFileLogger.log('[main] postBootstrap:start');
      final coordinator = AppBootstrapCoordinator(storage: storage, deps: deps);
      await coordinator.postBootstrap(
        configureBackgroundFetch: _configureBackgroundFetch,
      );
      AppFileLogger.log('[main] postBootstrap:done');
      if (!mounted) {
        return;
      }
      setState(() {
        _bootstrapStage = AppStrings(
          _localeController?.current ?? AppLanguage.ru,
        ).launchDone;
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
    final appearanceController = _appearanceController;
    final localeController = _localeController;
    AppFileLogger.log(
      '[main] build depsReady=${deps != null} storageReady=${storage != null} stage=$_bootstrapStage',
    );
    if (appearanceController == null || localeController == null) {
      return MaterialApp(
        title: 'PeerLink',
        debugShowCheckedModeBanner: false,
        locale: AppLanguage.ru.locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAppearance.icon1),
        home: Builder(
          builder: (context) => _buildHome(
            deps,
            storage,
            appearanceController,
            localeController,
            AppStrings.of(context),
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: Listenable.merge([appearanceController, localeController]),
      builder: (context, child) {
        return MaterialApp(
          title: 'PeerLink',
          debugShowCheckedModeBanner: false,
          locale: localeController.current.locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(appearanceController.current),
          home: Builder(
            builder: (context) => _buildHome(
              deps,
              storage,
              appearanceController,
              localeController,
              AppStrings.of(context),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHome(
    NetworkDependencies? deps,
    StorageService? storage,
    AppAppearanceController? appearanceController,
    AppLocaleController? localeController,
    AppStrings strings,
  ) {
    if (deps != null &&
        storage != null &&
        appearanceController != null &&
        localeController != null) {
      return UiApp(
        facade: deps.nodeFacade,
        storage: storage,
        appearanceController: appearanceController,
        localeController: localeController,
      );
    }
    return Scaffold(
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
                  Text(strings.launchingPeerLink),
                  const SizedBox(height: 8),
                  Text(_bootstrapStage, textAlign: TextAlign.center),
                ] else ...[
                  const Icon(Icons.error_outline, size: 44),
                  const SizedBox(height: 16),
                  Text(
                    strings.launchError(_bootstrapError!),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      unawaited(_retryBootstrap());
                    },
                    child: Text(strings.retry),
                  ),
                ],
              ],
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
