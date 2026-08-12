import 'dart:convert';

/// Helper for encoding QR payloads and building deep links.
class QrPayloadEncoder {
  /// Encode JSON string to base64url without padding.
  static String encodeToBase64Url(String json) {
    final bytes = utf8.encode(json);
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Build a simple deep link with payload query parameter.
  static String buildDeepLink({required String scheme, required String host, required String payload}) {
    return Uri(
      scheme: scheme,
      host: host,
      queryParameters: <String, String>{'payload': payload},
    ).toString();
  }
}
