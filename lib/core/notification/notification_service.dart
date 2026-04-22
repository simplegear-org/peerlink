import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionGranted = false;
  int _badgeCount = 0;

  Future<bool> init() async {
    if (_initialized) return _permissionGranted;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    _initialized = true;
    _permissionGranted = await _requestPermission();

    debugPrint('NotificationService init: permissionGranted=$_permissionGranted');
    return _permissionGranted;
  }

  Future<bool> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) return false;
      final granted = await androidPlugin.requestPermission();
      return granted ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin == null) return false;
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final macPlugin = _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (macPlugin == null) return false;
      final granted = await macPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return false;
  }

  Future<void> _updateAppBadge() async {
    try {
      if (_badgeCount > 0) {
        FlutterAppBadger.updateBadgeCount(_badgeCount);
      } else {
        FlutterAppBadger.removeBadge();
      }
    } catch (e) {
      debugPrint('NotificationService: badge update failed $e');
    }
  }

  void setBadgeCount(int count) {
    _badgeCount = count < 0 ? 0 : count;
    _updateAppBadge();
  }

  void incrementBadgeCount() {
    _badgeCount += 1;
    _updateAppBadge();
  }

  void clearBadgeCount() {
    _badgeCount = 0;
    _updateAppBadge();
  }

  Future<void> showMessageNotification({
    required String fromPeerId,
    required String message,
    int? badgeCount,
  }) async {
    try {
      if (!_initialized) {
        await init();
      }

      if (!_initialized || !_permissionGranted) {
        debugPrint('NotificationService: cannot show notification, permission denied');
        return;
      }

      if (badgeCount != null) {
        setBadgeCount(badgeCount);
      }

      final androidDetails = AndroidNotificationDetails(
        'peerlink_messages',
        'PeerLink Messages',
        channelDescription: 'Notifications when a new message is received',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        ticker: 'New message',
        number: badgeCount ?? _badgeCount,
      );

      final iosDetails = DarwinNotificationDetails(
        badgeNumber: badgeCount ?? _badgeCount,
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'New message from $fromPeerId',
        message,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
    } catch (e, stack) {
      debugPrint('NotificationService: showMessageNotification failed $e\n$stack');
    }
  }
}
