import 'package:flutter/services.dart';

class AndroidCallNotificationService {
  const AndroidCallNotificationService();

  static const MethodChannel _channel = MethodChannel(
    'peerlink/android_call_notifications/methods',
  );

  Future<void> cancelAllCallNotifications() async {
    try {
      await _channel.invokeMethod<void>('cancelAllCallNotifications');
    } on MissingPluginException {
      // Non-Android platforms do not expose this bridge.
    }
  }
}
