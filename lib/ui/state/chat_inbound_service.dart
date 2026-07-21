import 'dart:typed_data';
import 'dart:convert';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/messaging/chat_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/relay/relay_models.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/account_pairing_payload.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/storage_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../../core/runtime/avatar_service.dart';
import 'chat_controller_models.dart';
import 'chat_inbound_classifier.dart';

class ChatInboundService {
  final NodeFacade facade;
  final SecureStorageBox settingsBox;
  final AvatarService avatarService;
  final ChatInboundClassifier inboundClassifier;

  ChatInboundService({
    required this.facade,
    required this.settingsBox,
    required this.avatarService,
    required this.inboundClassifier,
  });

  String _sourcePeerId(ChatMessage msg) {
    final senderPeerId = msg.senderPeerId?.trim();
    if (senderPeerId != null && senderPeerId.isNotEmpty) {
      return senderPeerId;
    }
    return msg.peerId.trim();
  }

  void _logGroupFlow(String message) {
    developer.log(message, name: 'chat');
    AppFileLogger.log('[chat_group] $message');
  }

  Future<void> handleIncomingMessage(
    ChatMessage msg, {
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupInvitePayload? payload,
    )
    handleIncomingGroupInvite,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupKeyPayload? payload,
    )
    handleIncomingGroupKey,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupDeletePayload? payload,
    )
    handleIncomingGroupDelete,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupChatDeletePayload? payload,
    )
    handleIncomingGroupChatDelete,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupMembersPayload? payload,
    )
    handleIncomingGroupMembersUpdate,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupMessagePayload? payload,
    )
    handleIncomingGroupMessage,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupSecurePayload? payload,
    )
    handleIncomingGroupSecureMessage,
    required Future<void> Function(
      ChatMessage msg,
      IncomingBlobRefPayload blobRef,
    )
    handleIncomingDirectBlobRef,
    required Future<bool> Function(String peerId, String messageId)
    removeMessageWithMediaCleanup,
    required Future<bool> Function(
      String peerId,
      String messageId,
      String authorPeerId,
    )
    removeMessageByAuthorWithMediaCleanup,
    required bool Function(String text) isGroupDeletePayload,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required int Function() unreadMessagesCount,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(ChatMessage msg) notifyNewMessage,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    final dispatch = inboundClassifier.classifyIncomingMessage(msg);
    switch (dispatch) {
      case IncomingDeleteDispatch():
        if (msg.text.isNotEmpty) {
          if (isGroupDeletePayload(msg.text)) {
            await handleIncomingGroupDelete(msg, null);
            return;
          }
          final removed = await removeMessageByAuthorWithMediaCleanup(
            msg.peerId,
            msg.text,
            _sourcePeerId(msg),
          );
          if (!removed) {
            developer.log(
              '[chat] delete out-of-sync peer=${msg.peerId} messageId=${msg.text}',
              name: 'chat',
            );
          }
          notifyMessageUpdated(msg.peerId);
        }
        return;
      case IncomingProfileAvatarDispatch():
        await avatarService.handleIncomingAvatarAnnouncement(
          msg.peerId,
          msg.text,
        );
        return;
      case IncomingProfileAvatarRemoveDispatch():
        await avatarService.handleIncomingAvatarRemoval(msg.peerId, msg.text);
        return;
      case IncomingProfileAvatarQueryDispatch():
        await avatarService.handleIncomingAvatarQuery(msg.peerId, msg.text);
        return;
      case IncomingGroupInviteDispatch(payload: final payload):
        await handleIncomingGroupInvite(msg, payload);
        return;
      case IncomingGroupKeyDispatch(payload: final payload):
        await handleIncomingGroupKey(msg, payload);
        return;
      case IncomingGroupDeleteDispatch(payload: final payload):
        await handleIncomingGroupDelete(msg, payload);
        return;
      case IncomingGroupChatDeleteDispatch(payload: final payload):
        await handleIncomingGroupChatDelete(msg, payload);
        return;
      case IncomingGroupMembersDispatch(payload: final payload):
        await handleIncomingGroupMembersUpdate(msg, payload);
        return;
      case IncomingGroupMessageDispatch(payload: final payload):
        await handleIncomingGroupMessage(msg, payload);
        return;
      case IncomingGroupSecureDispatch(payload: final payload):
        await handleIncomingGroupSecureMessage(msg, payload);
        return;
      case IncomingDirectBlobRefDispatch(blobRef: final blobRef):
        await handleIncomingDirectBlobRef(msg, blobRef);
        return;
      case IncomingAccountPairRequestDispatch(payload: final payload):
        await _handleIncomingAccountPairRequest(msg, payload);
        return;
      case IncomingAccountPairApprovalDispatch(payload: final payload):
        await _handleIncomingAccountPairApproval(msg, payload);
        return;
      case IncomingAccountPairRejectionDispatch(payload: final payload):
        await _handleIncomingAccountPairRejection(msg, payload);
        return;
      case IncomingAccountMembershipUpdateDispatch(payload: final payload):
        await _handleIncomingAccountMembershipUpdate(msg, payload);
        return;
      case IncomingDisplayableDispatch():
        setStatus(msg.peerId, ChatConnectionStatus.connected);
        final message = Message(
          id: msg.id,
          peerId: msg.peerId,
          text: msg.text,
          senderPeerId: msg.peerId,
          incoming: true,
          timestamp: DateTime.now(),
          kind: msg.kind == 'file' ? MessageKind.file : MessageKind.text,
          fileName: msg.fileName,
          mimeType: msg.mimeType,
          fileDataBase64: msg.fileDataBase64,
          replyToMessageId: msg.replyToMessageId,
          replyToSenderPeerId: msg.replyToSenderPeerId,
          replyToSenderLabel: msg.replyToSenderLabel,
          replyToTextPreview: msg.replyToTextPreview,
          replyToKind: msg.replyToKind,
          status: MessageStatus.sent,
          isRead: false,
        );
        await appendMessage(msg.peerId, message);
        notifyMessageUpdated(msg.peerId);
        notifyNewMessage(msg);
        await showMessageNotification(
          fromPeerId: msg.peerId,
          message: msg.text,
          badgeCount: unreadMessagesCount(),
        ).catchError((error) {
          developer.log('notification error: $error', name: 'chat');
        });
        return;
      case IncomingIgnoredDispatch():
        developer.log(
          '[chat] ignored non-display message kind=${msg.kind} from=${msg.peerId} id=${msg.id}',
          name: 'chat',
        );
        return;
    }
  }

  Future<void> _handleIncomingAccountPairRequest(
    ChatMessage msg,
    AccountPairingRequestPayload payload,
  ) async {
    final current = _readIncomingAccountPairingRequests();
    final entry = <String, dynamic>{
      'payload': payload.toJson(),
      'sourcePeerId': msg.peerId,
    };
    final updated =
        current
            .where(
              (item) =>
                  (item['payload'] is! Map) ||
                  Map<String, dynamic>.from(
                        item['payload'] as Map,
                      )['requestId'] !=
                      payload.requestId,
            )
            .toList(growable: true)
          ..add(entry);
    await settingsBox.put(
      accountPairingIncomingRequestsStorageKey,
      jsonEncode(updated),
    );
    AppFileLogger.log(
      'incoming account pairing request requestId=${payload.requestId} source=${msg.peerId}',
      name: 'chat_pairing',
    );
  }

  Future<void> _handleIncomingAccountPairApproval(
    ChatMessage msg,
    AccountPairingApprovalPayload payload,
  ) async {
    final outgoingRaw = settingsBox.get(
      accountPairingOutgoingRequestStorageKey,
    );
    if (outgoingRaw is! String || outgoingRaw.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(outgoingRaw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final outgoing = AccountPairingRequestPayload.fromJson(decoded);
      if (outgoing.requestId != payload.requestId) {
        return;
      }
      await settingsBox.put(
        accountPairingApprovedPayloadStorageKey,
        jsonEncode(payload.toJson()),
      );
      AppFileLogger.log(
        'incoming account pairing approval requestId=${payload.requestId} source=${msg.peerId}',
        name: 'chat_pairing',
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _handleIncomingAccountPairRejection(
    ChatMessage msg,
    AccountPairingRejectedPayload payload,
  ) async {
    final outgoingRaw = settingsBox.get(
      accountPairingOutgoingRequestStorageKey,
    );
    if (outgoingRaw is! String || outgoingRaw.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(outgoingRaw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final outgoing = AccountPairingRequestPayload.fromJson(decoded);
      if (outgoing.requestId != payload.requestId) {
        return;
      }
      await settingsBox.put(
        accountPairingRejectedPayloadStorageKey,
        jsonEncode(payload.toJson()),
      );
      AppFileLogger.log(
        'incoming account pairing rejection requestId=${payload.requestId} source=${msg.peerId}',
        name: 'chat_pairing',
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _handleIncomingAccountMembershipUpdate(
    ChatMessage msg,
    AccountMembershipUpdatePayload payload,
  ) async {
    try {
      await facade.applyAccountMembershipUpdate(
        incoming: payload.accountIdentity,
        actorDeviceId: payload.actorDeviceId,
        action: payload.action,
        affectedDeviceIds: payload.affectedDeviceIds,
        updatedAtMs: payload.updatedAtMs,
        signature: payload.signature,
      );
      AppFileLogger.log(
        'incoming account membership update applied updateId=${payload.updateId} source=${msg.peerId}',
        name: 'chat_pairing',
      );
      return;
    } catch (error, stackTrace) {
      AppFileLogger.log(
        'incoming account membership update deferred updateId=${payload.updateId} error=$error',
        name: 'chat_pairing',
        stackTrace: stackTrace,
      );
    }
    final current = _readIncomingAccountMembershipUpdates();
    final updated =
        current
            .where((item) => item['updateId']?.toString() != payload.updateId)
            .toList(growable: true)
          ..add(payload.toJson());
    await settingsBox.put(
      accountMembershipUpdatesStorageKey,
      jsonEncode(updated),
    );
    AppFileLogger.log(
      'incoming account membership update updateId=${payload.updateId} source=${msg.peerId}',
      name: 'chat_pairing',
    );
  }

  List<Map<String, dynamic>> _readIncomingAccountPairingRequests() {
    final raw = settingsBox.get(accountPairingIncomingRequestsStorageKey);
    if (raw is! String || raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> _readIncomingAccountMembershipUpdates() {
    final raw = settingsBox.get(accountMembershipUpdatesStorageKey);
    if (raw is! String || raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> handleIncomingGroupInvite(
    ChatMessage msg, {
    required IncomingGroupInvitePayload? payload,
    required IncomingGroupInvitePayload? Function(String text) normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function(String groupId) restoreDeletedGroup,
    required Map<String, Chat> chats,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required void Function(String peerId) notifyMessageUpdated,
    required String localPeerId,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeerId = _sourcePeerId(msg);
    _logGroupFlow(
      'invite start source=$sourcePeerId target=${msg.peerId} id=${msg.id}',
    );
    if (resolvedPayload == null) {
      _logGroupFlow(
        'group invite drop: invalid payload from=$sourcePeerId id=${msg.id}',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupName = resolvedPayload.groupName;
    if (groupId.isEmpty || groupName.isEmpty) {
      _logGroupFlow(
        'group invite drop: missing group fields from=$sourcePeerId id=${msg.id}',
      );
      return;
    }
    final memberPeerIds = <String>{...resolvedPayload.memberPeerIds};
    memberPeerIds.add(sourcePeerId);
    memberPeerIds.add(localPeerId);
    final ownerPeerId = resolvedPayload.ownerPeerId;
    final resolvedOwner = (ownerPeerId != null && ownerPeerId.isNotEmpty)
        ? ownerPeerId
        : sourcePeerId;
    if (isGroupDeleted(groupId)) {
      if (resolvedOwner != localPeerId) {
        _logGroupFlow(
          'group invite drop: group is deleted group=$groupId from=$sourcePeerId',
        );
        return;
      }
      await restoreDeletedGroup(groupId);
    }

    final chat =
        chats[groupId] ??
        Chat(
          peerId: groupId,
          name: groupName,
          isGroup: true,
          memberPeerIds: memberPeerIds.toList(growable: false),
          ownerPeerId: resolvedOwner,
          messagesLoaded: true,
          hasMoreMessages: false,
        );

    chat.name = groupName;
    chat.isGroup = true;
    chat.memberPeerIds = memberPeerIds.toList(growable: false);
    chat.ownerPeerId = resolvedOwner;
    chats[groupId] = chat;
    _logGroupFlow(
      'group invite applied group=$groupId from=$sourcePeerId members=${chat.memberPeerIds.length}',
    );

    final invitationMessage = Message(
      id: msg.id,
      peerId: groupId,
      text: 'Вас пригласили в чат "$groupName"',
      senderPeerId: sourcePeerId,
      incoming: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
      isRead: false,
    );
    await appendMessage(groupId, invitationMessage);
    notifyMessageUpdated(groupId);
  }

  Future<void> handleIncomingGroupKey(
    ChatMessage msg, {
    required IncomingGroupKeyPayload? payload,
    required IncomingGroupKeyPayload? Function(String text) normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function({
      required String groupId,
      required String groupKeyBase64,
      required int keyVersion,
    })
    applyIncomingGroupKey,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    if (resolvedPayload == null) {
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupKey = resolvedPayload.groupKey;
    if (groupId.isEmpty || groupKey.isEmpty || isGroupDeleted(groupId)) {
      return;
    }
    await applyIncomingGroupKey(
      groupId: groupId,
      groupKeyBase64: groupKey,
      keyVersion: resolvedPayload.keyVersion,
    );
  }

  Future<void> handleIncomingGroupDelete(
    ChatMessage msg, {
    required IncomingGroupDeletePayload? payload,
    required IncomingGroupDeletePayload? Function(String text) normalizePayload,
    required Future<bool> Function(
      String peerId,
      String messageId,
      String authorPeerId,
    )
    removeMessageByAuthorWithMediaCleanup,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    if (resolvedPayload == null) {
      developer.log(
        'group delete drop: invalid payload from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupMessageId = resolvedPayload.groupMessageId;
    if (groupId.isEmpty || groupMessageId.isEmpty) {
      developer.log(
        'group delete drop: missing fields from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    final removed = await removeMessageByAuthorWithMediaCleanup(
      groupId,
      groupMessageId,
      _sourcePeerId(msg),
    );
    if (!removed) {
      developer.log(
        '[chat] group delete out-of-sync group=$groupId messageId=$groupMessageId',
        name: 'chat',
      );
    }
    notifyMessageUpdated(groupId);
  }

  Future<void> handleIncomingGroupChatDelete(
    ChatMessage msg, {
    required IncomingGroupChatDeletePayload? payload,
    required IncomingGroupChatDeletePayload? Function(String text)
    normalizePayload,
    required String? Function(String groupId) knownGroupOwnerPeerId,
    required Future<void> Function(
      String peerId, {
      bool rememberDeletedGroup,
      String? deletedByPeerId,
    })
    deleteChatLocal,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeerId = _sourcePeerId(msg);
    if (resolvedPayload == null) {
      developer.log(
        'group chat delete drop: invalid payload from=$sourcePeerId id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    if (groupId.isEmpty) {
      developer.log(
        'group chat delete drop: missing groupId from=$sourcePeerId id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    if (!_isTrustedGroupChatDeleteOwner(
      sourcePeerId,
      resolvedPayload,
      knownGroupOwnerPeerId: knownGroupOwnerPeerId,
    )) {
      developer.log(
        'group chat delete drop: sender is not owner group=$groupId sender=$sourcePeerId',
        name: 'chat',
      );
      return;
    }
    await deleteChatLocal(
      groupId,
      rememberDeletedGroup: true,
      deletedByPeerId: sourcePeerId,
    );
    developer.log(
      'group chat delete applied group=$groupId from=$sourcePeerId',
      name: 'chat',
    );
  }

  bool _isTrustedGroupChatDeleteOwner(
    String senderPeerId,
    IncomingGroupChatDeletePayload payload, {
    required String? Function(String groupId) knownGroupOwnerPeerId,
  }) {
    final sender = senderPeerId.trim();
    if (sender.isEmpty) {
      return false;
    }
    final declaredSender = payload.senderPeerId?.trim();
    if (declaredSender != null &&
        declaredSender.isNotEmpty &&
        declaredSender != sender) {
      return false;
    }
    final knownOwner = knownGroupOwnerPeerId(payload.groupId);
    if (knownOwner == null || knownOwner != sender) {
      return false;
    }
    final payloadOwner = payload.ownerPeerId?.trim();
    if (payloadOwner != null &&
        payloadOwner.isNotEmpty &&
        payloadOwner != knownOwner) {
      return false;
    }
    return true;
  }

  Future<void> handleIncomingGroupSecureMessage(
    ChatMessage msg, {
    required IncomingGroupSecurePayload? payload,
    required IncomingGroupSecurePayload? Function(String text) normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required Future<String?> Function(String text) decryptGroupText,
    required Map<String, Chat> chats,
    required String localPeerId,
    required IncomingBlobRefPayload? Function(String text)
    decodeIncomingBlobRefPayload,
    required Future<void> Function(
      ChatMessage msg, {
      required String groupId,
      required Chat groupChat,
      required Chat? existingGroupChat,
      required IncomingBlobRefPayload blobRef,
      required String notificationSenderLabel,
    })
    handleIncomingGroupBlobRef,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(ChatMessage msg) notifyNewMessage,
    required int Function() unreadMessagesCount,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeerId = _sourcePeerId(msg);
    _logGroupFlow(
      'secure start source=$sourcePeerId target=${msg.peerId} id=${msg.id}',
    );
    if (resolvedPayload == null) {
      _logGroupFlow(
        'group secure drop: classifier returned null source=$sourcePeerId id=${msg.id}',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    if (groupId.isEmpty) {
      _logGroupFlow('group secure drop: empty groupId source=$sourcePeerId');
      return;
    }
    if (isGroupDeleted(groupId)) {
      _logGroupFlow(
        'group secure message drop: group is deleted group=$groupId from=$sourcePeerId',
      );
      return;
    }
    final clearText = await decryptGroupText(msg.text);
    if (clearText == null || clearText.isEmpty) {
      _logGroupFlow(
        'group secure message drop: decrypt failed group=$groupId from=$sourcePeerId',
      );
      return;
    }
    _logGroupFlow(
      'group secure decrypted group=$groupId source=$sourcePeerId textLen=${clearText.length}',
    );

    final existingChat = chats[groupId];
    final chat =
        existingChat ??
        Chat(
          peerId: groupId,
          name: groupId,
          isGroup: true,
          memberPeerIds: <String>[localPeerId, sourcePeerId],
          ownerPeerId: sourcePeerId,
          messagesLoaded: true,
          hasMoreMessages: false,
        );
    chat.isGroup = true;
    chats[groupId] = chat;

    if (existingChat != null) {
      if (!chat.memberPeerIds.contains(localPeerId)) {
        _logGroupFlow(
          'group secure message drop: self is not a member group=$groupId',
        );
        return;
      }
      if (!chat.memberPeerIds.contains(sourcePeerId)) {
        _logGroupFlow(
          'group secure message drop: sender is not a member group=$groupId sender=$sourcePeerId',
        );
        return;
      }
    }
    final groupName = chat.name;
    final blobRef = decodeIncomingBlobRefPayload(clearText);
    if (blobRef != null && blobRef.isGroup) {
      _logGroupFlow(
        'group secure blob-ref group=$groupId source=$sourcePeerId blob=${blobRef.blobId}',
      );
      await handleIncomingGroupBlobRef(
        msg,
        groupId: groupId,
        groupChat: chat,
        existingGroupChat: existingChat,
        blobRef: blobRef,
        notificationSenderLabel: groupName,
      );
      return;
    }

    final incoming = Message(
      id: msg.id,
      peerId: groupId,
      text: clearText,
      senderPeerId: sourcePeerId,
      incoming: true,
      timestamp: DateTime.now(),
      replyToMessageId: msg.replyToMessageId,
      replyToSenderPeerId: msg.replyToSenderPeerId,
      replyToSenderLabel: msg.replyToSenderLabel,
      replyToTextPreview: msg.replyToTextPreview,
      replyToKind: msg.replyToKind,
      status: MessageStatus.sent,
      isRead: false,
    );
    await appendMessage(groupId, incoming);
    _logGroupFlow(
      'group secure appended group=$groupId source=$sourcePeerId messageId=${incoming.id}',
    );
    notifyMessageUpdated(groupId);
    notifyNewMessage(ChatMessage(id: msg.id, peerId: groupId, text: clearText));
    await showMessageNotification(
      fromPeerId: groupName,
      message: clearText,
      badgeCount: unreadMessagesCount(),
    ).catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
  }

  Future<void> handleIncomingGroupMessage(
    ChatMessage msg, {
    required IncomingGroupMessagePayload? payload,
    required IncomingGroupMessagePayload? Function(String text)
    normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function(String groupId) restoreDeletedGroup,
    required Map<String, Chat> chats,
    required String localPeerId,
    required IncomingBlobRefPayload? Function(String text)
    decodeIncomingBlobRefPayload,
    required Future<void> Function(
      ChatMessage msg, {
      required String groupId,
      required Chat groupChat,
      required Chat? existingGroupChat,
      required IncomingBlobRefPayload blobRef,
      required String notificationSenderLabel,
    })
    handleIncomingGroupBlobRef,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(ChatMessage msg) notifyNewMessage,
    required int Function() unreadMessagesCount,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeerId = _sourcePeerId(msg);
    _logGroupFlow(
      'message start source=$sourcePeerId target=${msg.peerId} id=${msg.id}',
    );
    if (resolvedPayload == null) {
      _logGroupFlow(
        'group message drop: invalid payload from=$sourcePeerId id=${msg.id}',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupMessageId = resolvedPayload.groupMessageId;
    final text = resolvedPayload.text;
    final groupName = resolvedPayload.groupName;
    if (groupId.isEmpty || groupMessageId.isEmpty || text.isEmpty) {
      _logGroupFlow(
        'group message drop: missing fields from=$sourcePeerId id=${msg.id}',
      );
      return;
    }
    final members = <String>{...resolvedPayload.memberPeerIds};
    members.add(sourcePeerId);
    members.add(localPeerId);
    final ownerPeerId = resolvedPayload.ownerPeerId;
    final resolvedOwner = (ownerPeerId != null && ownerPeerId.isNotEmpty)
        ? ownerPeerId
        : sourcePeerId;
    if (isGroupDeleted(groupId)) {
      if (resolvedOwner != localPeerId) {
        _logGroupFlow(
          'group message drop: group is deleted group=$groupId from=$sourcePeerId',
        );
        return;
      }
      await restoreDeletedGroup(groupId);
    }
    final existing = chats[groupId];
    final chat =
        existing ??
        Chat(
          peerId: groupId,
          name: groupName.isNotEmpty ? groupName : groupId,
          isGroup: true,
          memberPeerIds: members.toList(growable: false),
          ownerPeerId: resolvedOwner,
          messagesLoaded: true,
          hasMoreMessages: false,
        );
    chat.isGroup = true;
    if (groupName.isNotEmpty) {
      chat.name = groupName;
    }
    if (existing == null) {
      chat.memberPeerIds = members.toList(growable: false);
      chat.ownerPeerId = resolvedOwner;
    } else if ((chat.ownerPeerId == null || chat.ownerPeerId!.isEmpty) &&
        resolvedOwner.isNotEmpty) {
      chat.ownerPeerId = resolvedOwner;
    }
    chats[groupId] = chat;

    if (!chat.memberPeerIds.contains(localPeerId)) {
      _logGroupFlow('group message drop: self is not a member group=$groupId');
      return;
    }
    if (!chat.memberPeerIds.contains(sourcePeerId)) {
      _logGroupFlow(
        'group message drop: sender is not a member group=$groupId sender=$sourcePeerId',
      );
      return;
    }

    final blobRef = decodeIncomingBlobRefPayload(text);
    if (blobRef != null && blobRef.isGroup) {
      _logGroupFlow(
        'group message blob-ref group=$groupId source=$sourcePeerId blob=${blobRef.blobId} content=${blobRef.contentKind}',
      );
      await handleIncomingGroupBlobRef(
        msg,
        groupId: groupId,
        groupChat: chat,
        existingGroupChat: existing,
        blobRef: blobRef,
        notificationSenderLabel: groupName.isNotEmpty ? groupName : chat.name,
      );
      return;
    }

    final incoming = Message(
      id: groupMessageId,
      peerId: groupId,
      text: text,
      senderPeerId: sourcePeerId,
      incoming: true,
      timestamp: DateTime.now(),
      replyToMessageId: msg.replyToMessageId,
      replyToSenderPeerId: msg.replyToSenderPeerId,
      replyToSenderLabel: msg.replyToSenderLabel,
      replyToTextPreview: msg.replyToTextPreview,
      replyToKind: msg.replyToKind,
      status: MessageStatus.sent,
      isRead: false,
    );
    await appendMessage(groupId, incoming);
    _logGroupFlow(
      'group message appended group=$groupId source=$sourcePeerId messageId=${incoming.id}',
    );
    notifyMessageUpdated(groupId);
    notifyNewMessage(ChatMessage(id: msg.id, peerId: groupId, text: text));
    await showMessageNotification(
      fromPeerId: groupName.isNotEmpty ? groupName : groupId,
      message: text,
      badgeCount: unreadMessagesCount(),
    ).catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
  }

  Future<void> handleIncomingGroupMembersUpdate(
    ChatMessage msg, {
    required IncomingGroupMembersPayload? payload,
    required IncomingGroupMembersPayload? Function(String text)
    normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function(String groupId) restoreDeletedGroup,
    required Map<String, Chat> chats,
    required String localPeerId,
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<void> Function({
      required Chat groupChat,
      required Uint8List bytes,
      required String mimeType,
      required int updatedAtMs,
    })
    saveGroupAvatarBytes,
    required Future<RelayBlobDownload> Function(String blobId) downloadBlob,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List encryptedBytes,
    })
    decryptGroupBytes,
    required Future<void> Function(
      ChatMessage msg, {
      required IncomingGroupMembersPayload payload,
    })
    handleIncomingGroupLeave,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeerId = _sourcePeerId(msg);
    if (resolvedPayload == null) {
      developer.log(
        'group members drop: invalid payload from=$sourcePeerId id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupName = resolvedPayload.groupName;
    final ownerPeerId = resolvedPayload.ownerPeerId;
    final action = resolvedPayload.action;
    if (groupId.isEmpty) {
      return;
    }
    if (isGroupDeleted(groupId)) {
      if (ownerPeerId != localPeerId) {
        developer.log(
          'group members drop: group is deleted group=$groupId from=$sourcePeerId',
          name: 'chat',
        );
        return;
      }
      await restoreDeletedGroup(groupId);
    }
    if (action == 'leave') {
      await handleIncomingGroupLeave(msg, payload: resolvedPayload);
      return;
    }

    final members = <String>{...resolvedPayload.memberPeerIds};
    if (sourcePeerId.isNotEmpty) {
      members.add(sourcePeerId);
    }
    final changedPeerIds = <String>{...resolvedPayload.changedPeerIds};
    final selfRemoved =
        action == 'remove' && changedPeerIds.contains(localPeerId);
    if (!selfRemoved) {
      members.add(localPeerId);
    }
    final chat =
        chats[groupId] ??
        Chat(
          peerId: groupId,
          name: groupName.isNotEmpty ? groupName : groupId,
          isGroup: true,
          memberPeerIds: members.toList(growable: false),
          ownerPeerId: ownerPeerId.isNotEmpty ? ownerPeerId : sourcePeerId,
          messagesLoaded: true,
          hasMoreMessages: false,
        );
    chat.isGroup = true;
    if (groupName.isNotEmpty) {
      chat.name = groupName;
    }
    chat.memberPeerIds = members.toList(growable: false);
    if (ownerPeerId.isNotEmpty) {
      chat.ownerPeerId = ownerPeerId;
    }
    chats[groupId] = chat;
    await persistChatSummary(chat);

    if (action == 'avatar') {
      final avatarBlobId = (resolvedPayload.avatarBlobId ?? '').trim();
      if (avatarBlobId.isNotEmpty) {
        final knownOwner = (chat.ownerPeerId ?? '').trim();
        if (knownOwner.isNotEmpty && sourcePeerId != knownOwner) {
          developer.log(
            'group avatar drop: sender is not owner group=$groupId sender=$sourcePeerId',
            name: 'chat',
          );
          notifyMessageUpdated(groupId);
          return;
        }
        try {
          final blob = await downloadBlob(avatarBlobId);
          if (blob.isNotFound) {
            notifyMessageUpdated(groupId);
            return;
          }
          final decrypted = await decryptGroupBytes(
            groupId: groupId,
            encryptedBytes: blob.payload,
          );
          final avatarBytes = decrypted ?? blob.payload;
          final avatarMime = resolvedPayload.avatarMimeType?.trim();
          final updatedAtMs =
              resolvedPayload.avatarUpdatedAtMs ??
              DateTime.now().millisecondsSinceEpoch;
          await saveGroupAvatarBytes(
            groupChat: chat,
            bytes: avatarBytes,
            mimeType: avatarMime?.isNotEmpty == true
                ? avatarMime!
                : 'image/png',
            updatedAtMs: updatedAtMs,
          );
        } catch (_) {}
      }
    }
    notifyMessageUpdated(groupId);
  }

  Future<void> handleIncomingGroupLeave(
    ChatMessage msg, {
    required IncomingGroupMembersPayload payload,
    required Map<String, Chat> chats,
    required String localPeerId,
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<void> Function(Chat chat) syncGroupMembershipWithRelay,
    required Future<void> Function(
      Chat chat, {
      required List<String> recipients,
    })
    rotateGroupKey,
    required Future<void> Function({
      required Chat groupChat,
      required List<String> recipients,
      required String action,
      required List<String> changedPeerIds,
    })
    broadcastGroupMembersUpdate,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final groupId = payload.groupId;
    final leavingPeerId = _sourcePeerId(msg);
    if (groupId.isEmpty || leavingPeerId.isEmpty) {
      return;
    }
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      developer.log(
        'group leave drop: unknown group=$groupId from=$leavingPeerId',
        name: 'chat',
      );
      return;
    }
    final ownerPeerId = (chat.ownerPeerId ?? payload.ownerPeerId).trim();
    if (ownerPeerId.isNotEmpty && leavingPeerId == ownerPeerId) {
      developer.log(
        'group leave drop: owner cannot leave via leave action group=$groupId',
        name: 'chat',
      );
      return;
    }
    if (!chat.memberPeerIds.contains(leavingPeerId)) {
      developer.log(
        'group leave drop: sender is not member group=$groupId from=$leavingPeerId',
        name: 'chat',
      );
      return;
    }

    final previousMembers = chat.memberPeerIds.toList(growable: false);
    chat.memberPeerIds = previousMembers
        .where((peerId) => peerId != leavingPeerId)
        .toSet()
        .toList(growable: false);
    if (payload.groupName.isNotEmpty) {
      chat.name = payload.groupName;
    }
    if (ownerPeerId.isNotEmpty) {
      chat.ownerPeerId = ownerPeerId;
    }
    await persistChatSummary(chat);

    if (ownerPeerId == localPeerId) {
      await syncGroupMembershipWithRelay(chat);
      await rotateGroupKey(chat, recipients: chat.memberPeerIds);
      await broadcastGroupMembersUpdate(
        groupChat: chat,
        recipients: <String>{...previousMembers}.toList(growable: false),
        action: 'remove',
        changedPeerIds: <String>[leavingPeerId],
      );
    }
    notifyMessageUpdated(groupId);
  }

  Future<void> handleIncomingGroupBlobRef(
    ChatMessage msg, {
    required String groupId,
    required Chat groupChat,
    required Chat? existingGroupChat,
    required IncomingBlobRefPayload blobRef,
    required String notificationSenderLabel,
    required String localPeerId,
    required Future<String?> Function({
      required String groupId,
      required String blobId,
      String? fallback,
    })
    restoreGroupBlobText,
    required Future<RelayBlobDownload> Function(String blobId) downloadBlob,
    required Future<Uint8List> Function({
      required String groupId,
      required Uint8List encryptedBytes,
    })
    decodeGroupBlobBytes,
    required Future<void> Function({
      required Chat groupChat,
      required Uint8List bytes,
      required String mimeType,
      required int updatedAtMs,
    })
    saveGroupAvatarBytes,
    required String Function({
      required String groupId,
      required String messageId,
      required String blobId,
    })
    groupBlobTransferId,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(Message message, {required bool isGroup, bool force})
    restoreMediaInBackground,
    required void Function(ChatMessage msg) notifyNewMessage,
    required int Function() unreadMessagesCount,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    if (blobRef.chatPeerId != groupId || blobRef.blobId.isEmpty) {
      _logGroupFlow(
        'group blob-ref drop group=$groupId source=${_sourcePeerId(msg)} '
        'chatPeerId=${blobRef.chatPeerId} blob=${blobRef.blobId}',
      );
      return;
    }
    if (existingGroupChat == null && blobRef.memberPeerIds.isNotEmpty) {
      final members = <String>{
        ...blobRef.memberPeerIds,
        _sourcePeerId(msg),
        localPeerId,
      };
      groupChat.memberPeerIds = members.toList(growable: false);
    }
    final ownerPeerId = blobRef.ownerPeerId;
    if (ownerPeerId != null && ownerPeerId.isNotEmpty) {
      groupChat.ownerPeerId = ownerPeerId;
    }

    if (blobRef.contentKind == 'text') {
      _logGroupFlow(
        'group blob-ref text start group=$groupId source=${_sourcePeerId(msg)} blob=${blobRef.blobId}',
      );
      final text = await restoreGroupBlobText(
        groupId: groupId,
        blobId: blobRef.blobId,
        fallback: blobRef.textPreview,
      );
      if (text == null || text.isEmpty) {
        _logGroupFlow(
          'group blob-ref text drop group=$groupId source=${_sourcePeerId(msg)} blob=${blobRef.blobId}',
        );
        return;
      }
      final incoming = Message(
        id: blobRef.messageId,
        peerId: groupId,
        text: text,
        senderPeerId: _sourcePeerId(msg),
        incoming: true,
        timestamp: DateTime.now(),
        replyToMessageId: msg.replyToMessageId,
        replyToSenderPeerId: msg.replyToSenderPeerId,
        replyToSenderLabel: msg.replyToSenderLabel,
        replyToTextPreview: msg.replyToTextPreview,
        replyToKind: msg.replyToKind,
        status: MessageStatus.sent,
        isRead: false,
      );
      await appendMessage(groupId, incoming);
      _logGroupFlow(
        'group blob-ref text appended group=$groupId source=${_sourcePeerId(msg)} messageId=${incoming.id}',
      );
      notifyMessageUpdated(groupId);
      notifyNewMessage(
        ChatMessage(id: blobRef.messageId, peerId: groupId, text: text),
      );
      await showMessageNotification(
        fromPeerId: notificationSenderLabel,
        message: text,
        badgeCount: unreadMessagesCount(),
      ).catchError((error) {
        developer.log('notification error: $error', name: 'chat');
      });
      return;
    }

    if (blobRef.contentKind == 'avatar') {
      _logGroupFlow(
        'group blob-ref avatar start group=$groupId source=${_sourcePeerId(msg)} blob=${blobRef.blobId}',
      );
      try {
        final blob = await downloadBlob(blobRef.blobId);
        if (blob.isNotFound) {
          return;
        }
        final avatarBytes = await decodeGroupBlobBytes(
          groupId: groupId,
          encryptedBytes: blob.payload,
        );
        final avatarMime = blobRef.mimeType;
        await saveGroupAvatarBytes(
          groupChat: groupChat,
          bytes: avatarBytes,
          mimeType: avatarMime?.isNotEmpty == true ? avatarMime! : 'image/png',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        notifyMessageUpdated(groupId);
      } catch (_) {}
      return;
    }

    if (blobRef.contentKind != 'media') {
      _logGroupFlow(
        'group blob-ref drop unsupported content group=$groupId content=${blobRef.contentKind}',
      );
      return;
    }
    final fileName = (blobRef.fileName ?? '').trim();
    if (fileName.isEmpty) {
      return;
    }
    final incoming = Message(
      id: blobRef.messageId,
      peerId: groupId,
      text: fileName,
      senderPeerId: _sourcePeerId(msg),
      incoming: true,
      timestamp: DateTime.now(),
      kind: MessageKind.file,
      fileName: fileName,
      mimeType: blobRef.mimeType,
      transferId: groupBlobTransferId(
        groupId: groupId,
        messageId: blobRef.messageId,
        blobId: blobRef.blobId,
      ),
      fileSizeBytes: blobRef.fileSizeBytes,
      replyToMessageId: msg.replyToMessageId,
      replyToSenderPeerId: msg.replyToSenderPeerId,
      replyToSenderLabel: msg.replyToSenderLabel,
      replyToTextPreview: msg.replyToTextPreview,
      replyToKind: msg.replyToKind,
      status: MessageStatus.sent,
      isRead: false,
    );
    await appendMessage(groupId, incoming);
    _logGroupFlow(
      'group blob-ref media appended group=$groupId source=${_sourcePeerId(msg)} messageId=${incoming.id}',
    );
    notifyMessageUpdated(groupId);
    restoreMediaInBackground(incoming, isGroup: true, force: false);
    notifyNewMessage(
      ChatMessage(
        id: blobRef.messageId,
        peerId: groupId,
        text: fileName,
        kind: 'file',
        fileName: fileName,
        mimeType: blobRef.mimeType,
      ),
    );
    await showMessageNotification(
      fromPeerId: notificationSenderLabel,
      message: fileName,
      badgeCount: unreadMessagesCount(),
    ).catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
  }

  Future<void> handleIncomingDirectBlobRef(
    ChatMessage msg,
    IncomingBlobRefPayload blobRef, {
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Chat Function(String peerId, {String? fallbackName}) ensureChat,
    required Future<void> Function(String peerId) persistLoadedChat,
    required String Function({
      required String peerId,
      required String messageId,
      required String blobId,
    })
    directBlobTransferId,
    required void Function(String peerId) notifyMessageUpdated,
    required bool Function(Message message) shouldAutoRestoreIncomingMedia,
    required String incomingRelayFetchStatus,
    required void Function(Message message, {required bool isGroup, bool force})
    restoreMediaInBackground,
    required void Function(ChatMessage msg) notifyNewMessage,
    required int Function() unreadMessagesCount,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    final peerId = msg.peerId;
    final payloadPeerId = blobRef.raw['peerId'] as String? ?? '';
    final messageId = blobRef.messageId.trim().isNotEmpty
        ? blobRef.messageId
        : msg.id;
    final fileName = (blobRef.fileName ?? '').trim();
    final blobId = blobRef.blobId.trim();
    final contentKind = blobRef.contentKind.trim();

    if (payloadPeerId.isNotEmpty && payloadPeerId != peerId) {
      developer.log(
        '[chat] direct blob ref ignored peer-mismatch payloadPeer=$payloadPeerId actualPeer=$peerId',
        name: 'chat',
      );
      return;
    }
    if (contentKind != 'media' ||
        messageId.isEmpty ||
        fileName.isEmpty ||
        blobId.isEmpty) {
      return;
    }

    await ensureChatLoaded(peerId);
    final chat = ensureChat(peerId);
    final existingIndex = chat.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (existingIndex == -1) {
      chat.messages.add(
        Message(
          id: messageId,
          peerId: peerId,
          text: fileName,
          senderPeerId: peerId,
          incoming: true,
          timestamp: DateTime.now(),
          kind: MessageKind.file,
          fileName: fileName,
          mimeType: blobRef.mimeType,
          transferId: directBlobTransferId(
            peerId: peerId,
            messageId: messageId,
            blobId: blobId,
          ),
          fileSizeBytes: blobRef.fileSizeBytes,
          replyToMessageId: msg.replyToMessageId,
          replyToSenderPeerId: msg.replyToSenderPeerId,
          replyToSenderLabel: msg.replyToSenderLabel,
          replyToTextPreview: msg.replyToTextPreview,
          replyToKind: msg.replyToKind,
          transferredBytes: 0,
          transferStatus: incomingRelayFetchStatus,
          status: MessageStatus.sent,
          isRead: false,
        ),
      );
      await persistLoadedChat(peerId);
      notifyMessageUpdated(peerId);
      restoreMediaInBackground(
        chat.messages.last,
        isGroup: false,
        force: false,
      );
    } else if (shouldAutoRestoreIncomingMedia(chat.messages[existingIndex])) {
      notifyMessageUpdated(peerId);
      restoreMediaInBackground(
        chat.messages[existingIndex],
        isGroup: false,
        force: false,
      );
    } else {
      notifyMessageUpdated(peerId);
    }

    notifyNewMessage(
      ChatMessage(
        id: messageId,
        peerId: peerId,
        text: fileName,
        kind: 'file',
        fileName: fileName,
        mimeType: blobRef.mimeType,
      ),
    );
    await showMessageNotification(
      fromPeerId: chat.name,
      message: fileName,
      badgeCount: unreadMessagesCount(),
    ).catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
  }
}
