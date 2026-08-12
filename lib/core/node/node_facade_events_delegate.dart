import '../runtime/network_event.dart';
import '../runtime/network_event_bus.dart';

class NodeFacadeEventsDelegate {
  NodeFacadeEventsDelegate(this._events);

  final NetworkEventBus _events;

  Stream<NetworkEvent> get messageEvents => _events.on<NetworkEvent>().where(
    (event) => event.type == NetworkEventType.messageReceived,
  );

  NetworkEventHandlerRegistration addMessageEventHandler(
    NetworkEventHandler handler,
  ) {
    return _events.addAwaitableHandler((event) {
      if (event.type != NetworkEventType.messageReceived) {
        return Future<void>.value();
      }
      return handler(event);
    });
  }

  Stream<String> get peerConnectedStream => _events
      .on<NetworkEvent>()
      .where((event) => event.type == NetworkEventType.peerConnected)
      .map((event) => event.payload as String);

  Stream<String> get peerDisconnectedStream => _events
      .on<NetworkEvent>()
      .where((event) => event.type == NetworkEventType.peerDisconnected)
      .map((event) => event.payload as String);
}
