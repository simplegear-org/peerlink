import 'dart:async';
import 'dart:collection';
import 'dart:io';

class MessageFileAvailabilityCache {
  MessageFileAvailabilityCache._();

  static const int _maxConcurrentChecks = 4;
  static const int _maxCachedPaths = 512;
  static final LinkedHashMap<String, bool> _cache = LinkedHashMap();
  static final Map<String, Future<bool>> _inFlight = <String, Future<bool>>{};
  static final List<_QueuedFileCheck> _queue = <_QueuedFileCheck>[];
  static int _activeChecks = 0;

  static bool? cached(String? path) {
    final normalized = _normalize(path);
    if (normalized == null) {
      return null;
    }
    return _cache[normalized];
  }

  static Future<bool> exists(String? path) async {
    final normalized = _normalize(path);
    if (normalized == null) {
      return false;
    }
    final cachedValue = _cache[normalized];
    if (cachedValue != null) {
      _cache
        ..remove(normalized)
        ..[normalized] = cachedValue;
      return cachedValue;
    }
    final active = _inFlight[normalized];
    if (active != null) {
      return active;
    }
    final completer = Completer<bool>();
    _inFlight[normalized] = completer.future;
    _queue.add(_QueuedFileCheck(normalized, completer));
    _pumpQueue();
    return completer.future;
  }

  static void update(String? path, bool exists) {
    final normalized = _normalize(path);
    if (normalized == null) {
      return;
    }
    _remember(normalized, exists);
  }

  static void _pumpQueue() {
    while (_activeChecks < _maxConcurrentChecks && _queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      _activeChecks += 1;
      unawaited(_runCheck(item));
    }
  }

  static Future<void> _runCheck(_QueuedFileCheck item) async {
    var exists = false;
    try {
      exists = await File(item.path).exists();
    } catch (_) {
      exists = false;
    }
    _remember(item.path, exists);
    _inFlight.remove(item.path);
    if (!item.completer.isCompleted) {
      item.completer.complete(exists);
    }
    _activeChecks -= 1;
    _pumpQueue();
  }

  static String? _normalize(String? path) {
    final value = path?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static void _remember(String path, bool exists) {
    _cache
      ..remove(path)
      ..[path] = exists;
    while (_cache.length > _maxCachedPaths) {
      _cache.remove(_cache.keys.first);
    }
  }
}

class _QueuedFileCheck {
  final String path;
  final Completer<bool> completer;

  const _QueuedFileCheck(this.path, this.completer);
}
