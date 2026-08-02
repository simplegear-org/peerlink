import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

class FirebasePushLogFormatter {
  const FirebasePushLogFormatter();

  String incomingPush(RemoteMessage message, {required String source}) {
    final payload = <String, dynamic>{
      'source': source,
      'messageId': message.messageId,
      'from': message.from,
      'sentTime': message.sentTime?.toIso8601String(),
      'notification': <String, dynamic>{
        'title': message.notification?.title,
        'body': message.notification?.body,
      },
      'data': sanitizeIncomingPushData(message.data),
    };
    return truncate(jsonEncode(payload));
  }

  Map<String, dynamic> sanitizeIncomingPushData(Map<String, dynamic> data) {
    final safeData = <String, dynamic>{};
    data.forEach((key, value) {
      final lower = key.toLowerCase();
      if (lower.contains('sig') ||
          lower.contains('signingpub') ||
          lower.contains('token') ||
          lower.contains('authorization')) {
        safeData[key] = '<redacted>';
        return;
      }
      safeData[key] = value;
    });
    return safeData;
  }

  String truncate(String encoded, {int maxLength = 4000}) {
    return encoded.length > maxLength
        ? '${encoded.substring(0, maxLength)}...(truncated)'
        : encoded;
  }
}
