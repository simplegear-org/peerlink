import '../turn/turn_server_config.dart';

class PushServerUpdate {
  final List<String> bootstrap;
  final List<String> relay;
  final List<String> push;
  final List<TurnServerConfig> turn;
  final List<String> priorityBootstrap;
  final List<TurnServerConfig> priorityTurn;

  const PushServerUpdate({
    required this.bootstrap,
    required this.relay,
    required this.push,
    required this.turn,
    this.priorityBootstrap = const <String>[],
    this.priorityTurn = const <TurnServerConfig>[],
  });

  bool get isEmpty =>
      bootstrap.isEmpty &&
      relay.isEmpty &&
      push.isEmpty &&
      turn.isEmpty &&
      priorityBootstrap.isEmpty &&
      priorityTurn.isEmpty;
}
