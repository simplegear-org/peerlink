import '../turn/turn_server_config.dart';

class ServerConfigPayload {
  static const String type = 'peerlink_server_config';
  static const int version = 1;

  final List<String> bootstrap;
  final List<String> relay;
  final List<TurnServerConfig> turn;
  final List<String> push;

  const ServerConfigPayload({
    required this.bootstrap,
    required this.relay,
    required this.turn,
    required this.push,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'version': version,
      'bootstrap': bootstrap,
      'relay': relay,
      'turn': turn.map((server) => server.toJson()).toList(growable: false),
      'push': push,
    };
  }

  factory ServerConfigPayload.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw const FormatException('Это не QR конфигурации серверов Peerlink');
    }
    if (json['version'] != version) {
      throw const FormatException('Неподдерживаемая версия конфигурации');
    }

    return ServerConfigPayload(
      bootstrap: (json['bootstrap'] as List? ?? const <dynamic>[])
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      relay: (json['relay'] as List? ?? const <dynamic>[])
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      turn: (json['turn'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => TurnServerConfig.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.url.trim().isNotEmpty)
          .toList(growable: false),
      push: (json['push'] as List? ?? const <dynamic>[])
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}
