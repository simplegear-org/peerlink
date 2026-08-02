import 'dart:async';
import 'dart:io';

class ServerRuntimeUtils {
  static List<String> uniqueNormalized(
    Iterable<String> values,
    String Function(String) normalize,
  ) {
    return values
        .map(normalize)
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static bool addUnique(List<String> target, String value) {
    if (value.isEmpty || target.contains(value)) {
      return false;
    }
    target.add(value);
    return true;
  }

  static bool putFirst(List<String> target, String value) {
    if (value.isEmpty) {
      return false;
    }
    target.remove(value);
    target.insert(0, value);
    return true;
  }

  static bool mergeUnique(
    List<String> target,
    Iterable<String> incoming,
    String Function(String) normalize,
  ) {
    var changed = false;
    for (final item in incoming) {
      final normalized = normalize(item);
      if (normalized.isEmpty || target.contains(normalized)) {
        continue;
      }
      target.add(normalized);
      changed = true;
    }
    return changed;
  }

  static String shortError(Object error, {int maxLength = 80}) {
    final text = error.toString().trim();
    if (text.length <= maxLength) {
      return text;
    }
    final cutoff = maxLength - 3;
    if (cutoff <= 0) {
      return text;
    }
    return '${text.substring(0, cutoff)}...';
  }

  static String normalizeHostOnly(
    String input, {
    String defaultScheme = 'peerlink',
  }) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return '';
    }
    final withScheme = raw.contains('://') ? raw : '$defaultScheme://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.trim().isEmpty) {
      return '';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return '';
    }
    if (uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.userInfo.isNotEmpty) {
      return '';
    }
    final host = uri.host.trim();
    return isSafeHost(host) ? host : '';
  }

  static bool isSafeHost(String host) {
    final value = host.trim();
    if (value.isEmpty || value.contains('%')) {
      return false;
    }
    try {
      if (InternetAddress.tryParse(value) != null) {
        return true;
      }
    } on FormatException {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(value);
  }

  static bool isIpAddressHost(String host) {
    final value = host.trim();
    if (value.isEmpty) {
      return false;
    }
    try {
      return InternetAddress.tryParse(value) != null;
    } on FormatException {
      return false;
    }
  }

  static void writeUriHost(StringBuffer buffer, String host) {
    if (host.contains(':') && !host.startsWith('[')) {
      buffer.write('[$host]');
      return;
    }
    buffer.write(host);
  }

  static void enableHostMatchingBadCertificateForHttps(
    HttpClient client,
    Uri uri,
  ) {
    if (uri.scheme == 'https') {
      client.badCertificateCallback = (cert, host, port) => host == uri.host;
    }
  }

  static Future<int?> requestStatusWithTimeout({
    required HttpClient client,
    required Uri uri,
    required String method,
    required Duration timeout,
    ContentType? contentType,
    List<int>? bodyBytes,
  }) {
    final completer = Completer<int?>();
    Timer? timeoutTimer;
    var timedOut = false;

    void completeAsTimeout() {
      timedOut = true;
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      client.close(force: true);
    }

    timeoutTimer = Timer(timeout, completeAsTimeout);

    void completeError(Object error, StackTrace stackTrace) {
      timeoutTimer?.cancel();
      if (timedOut || completer.isCompleted) {
        return;
      }
      completer.completeError(error, stackTrace);
    }

    try {
      client
          .openUrl(method, uri)
          .then((request) {
            if (contentType != null) {
              request.headers.contentType = contentType;
            }
            if (bodyBytes != null && bodyBytes.isNotEmpty) {
              request.add(bodyBytes);
            }
            return request.close();
          })
          .then((response) async {
            final statusCode = response.statusCode;
            try {
              await response.drain<void>();
            } catch (_) {}
            timeoutTimer?.cancel();
            if (timedOut || completer.isCompleted) {
              return;
            }
            completer.complete(statusCode);
          }, onError: completeError);
    } catch (error, stackTrace) {
      completeError(error, stackTrace);
    }

    return completer.future.whenComplete(() => timeoutTimer?.cancel());
  }
}
