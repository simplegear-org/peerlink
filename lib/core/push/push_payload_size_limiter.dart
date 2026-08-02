import 'dart:convert';

class PushPayloadSizeLimiter {
  static const defaultMaxTransportPayloadBytes = 3072;

  const PushPayloadSizeLimiter({
    this.maxTransportPayloadBytes = defaultMaxTransportPayloadBytes,
  });

  final int maxTransportPayloadBytes;

  Map<String, dynamic> compact(Map<String, dynamic> payload) {
    final result = _deepCopyMap(payload);
    if (_transportSizeBytes(result) <= maxTransportPayloadBytes) {
      return result;
    }

    const trimOrder = <_ServerListPath>[
      _ServerListPath('servers', 'turn'),
      _ServerListPath('servers', 'relay'),
      _ServerListPath('servers', 'push'),
      _ServerListPath('servers', 'bootstrap'),
    ];

    var changed = true;
    while (changed && _transportSizeBytes(result) > maxTransportPayloadBytes) {
      changed = false;
      for (final path in trimOrder) {
        if (_removeLastServerEntry(result, path)) {
          changed = true;
          if (_transportSizeBytes(result) <= maxTransportPayloadBytes) {
            return result;
          }
        }
      }
    }
    return result;
  }

  int transportSizeBytes(Map<String, dynamic> payload) =>
      _transportSizeBytes(payload);

  int _transportSizeBytes(Map<String, dynamic> payload) {
    return utf8.encode(jsonEncode(_encodeForTransport(payload))).length;
  }

  Map<String, dynamic> _encodeForTransport(Map<String, dynamic> payload) {
    final encoded = <String, dynamic>{};
    payload.forEach((key, value) {
      final transportValue = _encodeValueForTransport(value);
      if (transportValue != null) {
        encoded[key] = transportValue;
      }
    });
    return encoded;
  }

  Object? _encodeValueForTransport(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    if (value is Map || value is List) {
      return jsonEncode(_sortJsonValue(value));
    }
    return value.toString();
  }

  bool _removeLastServerEntry(
    Map<String, dynamic> payload,
    _ServerListPath path,
  ) {
    final section = payload[path.section];
    if (section is! Map) {
      return false;
    }
    final sectionMap = Map<String, dynamic>.from(section);
    final list = sectionMap[path.key];
    if (list is! List || list.isEmpty) {
      return false;
    }
    final nextList = List<dynamic>.from(list)..removeLast();
    if (nextList.isEmpty) {
      sectionMap.remove(path.key);
    } else {
      sectionMap[path.key] = nextList;
    }
    if (sectionMap.isEmpty) {
      payload.remove(path.section);
    } else {
      payload[path.section] = sectionMap;
    }
    return true;
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> input) {
    return input.map((key, value) => MapEntry(key, _deepCopyValue(value)));
  }

  Object? _deepCopyValue(Object? value) {
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _deepCopyValue(item)),
      );
    }
    if (value is List) {
      return value.map(_deepCopyValue).toList(growable: true);
    }
    return value;
  }

  Object? _sortJsonValue(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((item) => item.toString()).toList()..sort();
      final sorted = <String, dynamic>{};
      for (final key in keys) {
        sorted[key] = _sortJsonValue(value[key]);
      }
      return sorted;
    }
    if (value is List) {
      return value.map(_sortJsonValue).toList(growable: false);
    }
    return value;
  }
}

class _ServerListPath {
  final String section;
  final String key;

  const _ServerListPath(this.section, this.key);
}
