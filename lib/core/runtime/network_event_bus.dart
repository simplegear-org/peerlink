import 'dart:async';
import 'network_event.dart';

class NetworkEventBus {
  final _controller = StreamController<NetworkEvent>.broadcast();

  void emit(NetworkEvent event) {
    _controller.add(event);
  }

  Stream<T> on<T extends NetworkEvent>() {
    return _controller.stream.where((e) => e is T).cast<T>();
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}