import 'dart:async';
import 'network_event.dart';

typedef NetworkEventHandler = FutureOr<void> Function(NetworkEvent event);

class NetworkEventHandlerRegistration {
  final FutureOr<void> Function() _onCancel;
  bool _cancelled = false;

  NetworkEventHandlerRegistration(this._onCancel);

  Future<void> cancel() async {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    await _onCancel();
  }
}

class NetworkEventBus {
  final _controller = StreamController<NetworkEvent>.broadcast();
  final Set<NetworkEventHandler> _awaitableHandlers = <NetworkEventHandler>{};

  void emit(NetworkEvent event) {
    _controller.add(event);
  }

  NetworkEventHandlerRegistration addAwaitableHandler(
    NetworkEventHandler handler,
  ) {
    _awaitableHandlers.add(handler);
    return NetworkEventHandlerRegistration(() {
      _awaitableHandlers.remove(handler);
    });
  }

  Future<bool> emitAndWait(NetworkEvent event) async {
    _controller.add(event);

    final handlers = List<NetworkEventHandler>.from(_awaitableHandlers);
    if (handlers.isEmpty) {
      return false;
    }

    for (final handler in handlers) {
      await handler(event);
    }
    return true;
  }

  Stream<T> on<T extends NetworkEvent>() {
    return _controller.stream.where((e) => e is T).cast<T>();
  }

  Future<void> dispose() async {
    _awaitableHandlers.clear();
    await _controller.close();
  }
}
