import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

import '../runtime/storage_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  // Temporary switch: keep only remote push notifications.
  static const bool _localNotificationsEnabled = false;
  static const String _badgeCountStorageKey = 'peerlink.app.badge_count';

  bool _initialized = false;
  bool _permissionGranted = false;
  int _badgeCount = 0;
  bool? _isBadgeSupported;

  Future<bool> init() async {
    if (_initialized) return _permissionGranted;
    if (!_localNotificationsEnabled) {
      _initialized = true;
      _permissionGranted = false;
      return _permissionGranted;
    }
    _initialized = true;
    _permissionGranted = false;
    return _permissionGranted;
  }

  Future<void> _updateAppBadge() async {
    try {
      final supported =
          _isBadgeSupported ??= await FlutterAppBadger.isAppBadgeSupported();
      if (!supported) {
        return;
      }
      if (_badgeCount > 0) {
        await FlutterAppBadger.updateBadgeCount(_badgeCount);
      } else {
        await FlutterAppBadger.removeBadge();
      }
    } catch (_) {
      // Diagnostics disabled.
    }
  }

  void setBadgeCount(int count) {
    _badgeCount = count < 0 ? 0 : count;
    unawaited(_syncBadgeState());
  }

  void incrementBadgeCount() {
    _badgeCount += 1;
    unawaited(_syncBadgeState());
  }

  void clearBadgeCount() {
    _badgeCount = 0;
    unawaited(_syncBadgeState());
  }

  Future<void> syncStoredBadgeCount(int count) async {
    _badgeCount = count < 0 ? 0 : count;
    await _syncBadgeState();
  }

  Future<int> incrementStoredBadgeCount({int delta = 1}) async {
    final current = await readStoredBadgeCount();
    final next = current + delta;
    await syncStoredBadgeCount(next);
    return _badgeCount;
  }

  Future<int> readStoredBadgeCount() async {
    try {
      final storage = StorageService();
      await storage.init();
      final raw = storage.getSettings().get(_badgeCountStorageKey);
      if (raw is int) {
        return raw < 0 ? 0 : raw;
      }
      if (raw is num) {
        final value = raw.toInt();
        return value < 0 ? 0 : value;
      }
      final parsed = int.tryParse(raw?.toString() ?? '');
      if (parsed == null || parsed < 0) {
        return 0;
      }
      return parsed;
    } catch (_) {
      return _badgeCount < 0 ? 0 : _badgeCount;
    }
  }

  Future<void> _syncBadgeState() async {
    await _persistBadgeCount();
    await _updateAppBadge();
  }

  Future<void> _persistBadgeCount() async {
    try {
      final storage = StorageService();
      await storage.init();
      await storage.getSettings().put(_badgeCountStorageKey, _badgeCount);
    } catch (_) {
      // Diagnostics disabled.
    }
  }

  Future<void> showMessageNotification({
    required String fromPeerId,
    required String message,
    int? badgeCount,
  }) async {
    if (badgeCount != null) {
      _badgeCount = badgeCount < 0 ? 0 : badgeCount;
      await _syncBadgeState();
    }
    if (!_localNotificationsEnabled) {
      return;
    }
    try {
      if (_shouldSuppressForegroundNotification()) {
        return;
      }
      if (!_initialized) {
        await init();
      }

      if (!_initialized || !_permissionGranted) {
        return;
      }
    } catch (_) {
      // Diagnostics disabled.
    }
  }

  Future<void> showIncomingCallNotification({
    required String fromPeerId,
    required bool isVideo,
  }) async {
    if (!_localNotificationsEnabled) {
      return;
    }
    try {
      if (_shouldSuppressForegroundNotification()) {
        return;
      }
      if (!_initialized) {
        await init();
      }
      if (!_initialized || !_permissionGranted) {
        return;
      }
    } catch (_) {
      // Diagnostics disabled.
    }
  }

  bool _shouldSuppressForegroundNotification() {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    return lifecycleState == AppLifecycleState.resumed;
  }
}
