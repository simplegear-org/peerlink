import '../../core/messaging/chat_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/notification/notification_service.dart';
import '../../core/runtime/network_event_bus.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_inbound_service.dart';

class ChatInboundSubscriptionCoordinator {
  final NodeFacade facade;
  final ChatInboundService inboundService;
  final bool Function(String text) isGroupDeletePayload;
  final Future<void> Function(
    ChatMessage msg, {
    IncomingGroupInvitePayload? payload,
  })
  handleIncomingGroupInvite;
  final Future<void> Function(
    ChatMessage msg, {
    IncomingGroupKeyPayload? payload,
  })
  handleIncomingGroupKey;
  final Future<void> Function(
    ChatMessage msg, {
    IncomingGroupDeletePayload? payload,
  })
  handleIncomingGroupDelete;
  final Future<void> Function(
    ChatMessage msg, {
    IncomingGroupChatDeletePayload? payload,
  })
  handleIncomingGroupChatDelete;
  final Future<void> Function(
    ChatMessage msg, {
    IncomingGroupMembersPayload? payload,
  })
  handleIncomingGroupMembersUpdate;
  final Future<void> Function(
    ChatMessage msg, {
    IncomingGroupMessagePayload? payload,
  })
  handleIncomingGroupMessage;
  final Future<void> Function(
    ChatMessage msg, {
    IncomingGroupSecurePayload? payload,
  })
  handleIncomingGroupSecureMessage;
  final Future<void> Function(ChatMessage msg, IncomingBlobRefPayload blobRef)
  handleIncomingDirectBlobRef;
  final Future<bool> Function(String peerId, String messageId)
  removeMessageWithMediaCleanup;
  final Future<bool> Function(
    String peerId,
    String messageId,
    String authorPeerId,
  )
  removeMessageByAuthorWithMediaCleanup;
  final void Function(
    String peerId,
    ChatConnectionStatus status, {
    String? error,
  })
  setStatus;
  final Future<void> Function(String peerId, Message message) appendMessage;
  final int Function() unreadMessagesCount;
  final void Function(String peerId) notifyMessageUpdated;
  final void Function(ChatMessage msg) notifyNewMessage;

  NetworkEventHandlerRegistration? _registration;

  ChatInboundSubscriptionCoordinator({
    required this.facade,
    required this.inboundService,
    required this.isGroupDeletePayload,
    required this.handleIncomingGroupInvite,
    required this.handleIncomingGroupKey,
    required this.handleIncomingGroupDelete,
    required this.handleIncomingGroupChatDelete,
    required this.handleIncomingGroupMembersUpdate,
    required this.handleIncomingGroupMessage,
    required this.handleIncomingGroupSecureMessage,
    required this.handleIncomingDirectBlobRef,
    required this.removeMessageWithMediaCleanup,
    required this.removeMessageByAuthorWithMediaCleanup,
    required this.setStatus,
    required this.appendMessage,
    required this.unreadMessagesCount,
    required this.notifyMessageUpdated,
    required this.notifyNewMessage,
  });

  void start() {
    _registration ??= facade.addMessageEventHandler((event) async {
      final msg = event.payload;
      await inboundService.handleIncomingMessage(
        msg,
        handleIncomingGroupInvite: (msg, payload) =>
            handleIncomingGroupInvite(msg, payload: payload),
        handleIncomingGroupKey: (msg, payload) =>
            handleIncomingGroupKey(msg, payload: payload),
        handleIncomingGroupDelete: (msg, payload) =>
            handleIncomingGroupDelete(msg, payload: payload),
        handleIncomingGroupChatDelete: (msg, payload) =>
            handleIncomingGroupChatDelete(msg, payload: payload),
        handleIncomingGroupMembersUpdate: (msg, payload) =>
            handleIncomingGroupMembersUpdate(msg, payload: payload),
        handleIncomingGroupMessage: (msg, payload) =>
            handleIncomingGroupMessage(msg, payload: payload),
        handleIncomingGroupSecureMessage: (msg, payload) =>
            handleIncomingGroupSecureMessage(msg, payload: payload),
        handleIncomingDirectBlobRef: handleIncomingDirectBlobRef,
        removeMessageWithMediaCleanup: removeMessageWithMediaCleanup,
        removeMessageByAuthorWithMediaCleanup:
            removeMessageByAuthorWithMediaCleanup,
        isGroupDeletePayload: isGroupDeletePayload,
        setStatus: setStatus,
        appendMessage: appendMessage,
        unreadMessagesCount: unreadMessagesCount,
        notifyMessageUpdated: notifyMessageUpdated,
        notifyNewMessage: notifyNewMessage,
        showMessageNotification:
            ({required fromPeerId, required message, required badgeCount}) =>
                NotificationService.instance.showMessageNotification(
                  fromPeerId: fromPeerId,
                  message: message,
                  badgeCount: badgeCount,
                ),
      );
    });
  }

  Future<void> dispose() async {
    await _registration?.cancel();
    _registration = null;
  }
}
