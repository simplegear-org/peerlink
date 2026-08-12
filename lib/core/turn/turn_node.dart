import 'turn_credentials.dart';

class TurnNode {
  final TurnCredentials credentials;
  final int priority;

  int _score = 100;
  bool _healthy = true;

  TurnNode({
    required this.credentials,
    required this.priority,
  });

  int get score => _score + priority;

  bool get isHealthy => _healthy;

  void markHealthy() {
    _healthy = true;
    _score = (_score + 5).clamp(0, 300);
  }

  void markUnhealthy() {
    _healthy = false;
    _score = (_score - 25).clamp(0, 300);
  }
}