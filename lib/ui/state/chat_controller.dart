// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../core/messaging/chat_service.dart';
import '../../core/notification/notification_service.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/moderation_report_models.dart';
import '../../core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import '../models/contact.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import '../../features/profile/application/avatar_service.dart';
import 'package:peerlink/features/chat/application/chat_account_payload_decoder.dart';
import 'package:peerlink/features/chat/application/chat_controller_dependencies.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_controller_ports.dart';
import 'package:peerlink/features/chat/application/chat_controller_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_contacts_service.dart';
import 'package:peerlink/features/chat/application/chat_direct_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_groups_api.dart';
import 'package:peerlink/features/chat/application/chat_history_api.dart';
import 'package:peerlink/features/chat/application/chat_inbound_service.dart';
import 'package:peerlink/features/chat/application/chat_inbound_subscription_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_media_api.dart';
import 'package:peerlink/features/chat/application/chat_messages_api.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/application/chat_cleanup_api.dart';
import 'package:peerlink/features/chat/application/chat_safety_api.dart';
import 'package:peerlink/features/chat/application/chat_summary_service.dart';

class ChatController with WidgetsBindingObserver {
  static int _lastGeneratedMessageId = 0;
  final ChatRuntimeApi runtime;
  late final ChatOutboundCodec _outboundCodec;
  late final ChatSummaryService _chatSummaryService;
  late final ChatControllerLifecycleService _lifecycleService;
  late final ChatInboundService _chatInboundService;
  late final ChatContactsService _chatContactsService;
  late final ChatGroupsApi _groupsApi;
  late final ChatDirectLifecycleService _directLifecycleService;
  late final ChatMessagesApi _messagesApi;
  late final ChatMediaApi _mediaApi;
  late final Future<void> _startupReady;
  late final ChatInboundSubscriptionCoordinator _inboundSubscriptionCoordinator;
  late final ChatHistoryApi _historyApi;
  late final ChatCleanupApi _cleanupApi;
  late final ChatSafetyApi _safetyApi;

  final Map<String, Chat> chats = {};
  final Map<String, ChatConnectionStatus> _connectionStatus = {};
  final Map<String, String?> _connectionErrors = {};
  final _connectionStatusController = StreamController<String>.broadcast();
  final _messageUpdatesController = StreamController<String>.broadcast();
  final _newMessageNotificationController =
      StreamController<ChatMessage>.broadcast();
  final void Function(int unreadCount)? _onUnreadBadgeCountChanged;

  ChatController(
    this.runtime, {
    required StorageService storage,
    required AvatarService avatarService,
    required ChatControllerDependenciesFactory dependenciesFactory,
    void Function(int unreadCount)? onUnreadBadgeCountChanged,
  }) : _onUnreadBadgeCountChanged = onUnreadBadgeCountChanged {
    final dependencies = dependenciesFactory(
      runtime: runtime,
      storage: storage,
      avatarService: avatarService,
      presentationState: _ChatControllerPresentationStatePort(this),
      connectionState: _ChatControllerConnectionStatePort(this),
      messageState: _ChatControllerMessageStatePort(this),
      mediaState: _ChatControllerMediaStatePort(this),
      groupState: _ChatControllerGroupStatePort(this),
      notifications: _ChatControllerNotificationPort(this),
      lifecycle: _ChatControllerLifecyclePort(this),
      inbound: _ChatControllerInboundPort(this),
      accountPayloads: const _ChatControllerAccountPayloadPort(),
    );
    final persistence = dependencies.persistence;
    final messaging = dependencies.messaging;
    final groups = dependencies.groups;
    final mediaLifecycle = dependencies.mediaLifecycle;
    final safety = dependencies.safety;

    _historyApi = persistence.historyApi;
    _outboundCodec = messaging.outboundCodec;
    _chatSummaryService = persistence.summaryService;
    _messagesApi = messaging.messagesApi;
    _chatContactsService = groups.contactsService;
    _groupsApi = groups.groupsApi;
    _directLifecycleService = mediaLifecycle.directLifecycleService;
    _chatInboundService = mediaLifecycle.inboundService;
    _mediaApi = mediaLifecycle.mediaApi;
    _lifecycleService = mediaLifecycle.lifecycleService;
    _cleanupApi = mediaLifecycle.cleanupApi;
    _safetyApi = safety.safetyApi;
    _inboundSubscriptionCoordinator =
        mediaLifecycle.inboundSubscriptionCoordinator;
    WidgetsBinding.instance.addObserver(this);
    _startupReady = Future.wait(<Future<void>>[
      _loadChats(),
      _historyApi.initializeGroupKeys(),
    ]);
    _syncBadgeCount();
    _inboundSubscriptionCoordinator.start();
    _lifecycleService.start();
    unawaited(_pollRelayAfterStartupReady());
  }

  Future<void> _waitUntilStartupReady() {
    return _startupReady;
  }

  Future<void> _pollRelayAfterStartupReady() async {
    await _startupReady;
    await runtime.pollRelay();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lifecycleService.handleAppResumed();
    }
  }

  Future<void> _loadChats() async {
    await _historyApi.loadChats();
  }

  bool _isGroupDeleted(String groupId) {
    return _groupsApi.isGroupDeleted(groupId);
  }

  Future<void> _rememberDeletedGroup(
    String groupId, {
    required String deletedByPeerId,
    Chat? chat,
  }) async {
    await _groupsApi.rememberDeletedGroup(
      groupId,
      deletedByPeerId: deletedByPeerId,
      chat: chat,
    );
  }

  Future<void> _restoreDeletedGroup(String groupId) async {
    await _groupsApi.restoreDeletedGroup(groupId);
  }

  Future<void> _runGroupKeyGc() async {
    await _groupsApi.runGroupKeyGc();
  }

  String _contactNameFor(String peerId, {String? fallback}) {
    return _chatContactsService.resolveChatName(peerId, fallback: fallback);
  }

  Chat _ensureChat(String peerId, {String? fallbackName}) {
    return _directLifecycleService.ensureChat(
      peerId,
      fallbackName: fallbackName,
    );
  }

  Future<void> ensureChatLoaded(String peerId) async {
    await _historyApi.ensureChatLoaded(peerId);
  }

  Future<void> _rememberOutgoingRelayMediaState(
    OutgoingRelayMediaState state,
  ) async {
    await _mediaApi.rememberOutgoingRelayMediaState(state);
  }

  Future<void> _forgetOutgoingRelayMediaState(
    String peerId,
    String messageId,
  ) async {
    await _mediaApi.forgetOutgoingRelayMediaState(peerId, messageId);
  }

  Future<void> _resumePendingOutgoingRelayMedia({
    required String reason,
  }) async {
    await _mediaApi.resumePendingOutgoingRelayMedia(reason: reason);
  }

  /// Загружает следующую страницу сообщений (при прокрутке вверх)
  Future<bool> loadMoreMessages(String peerId) async {
    return _historyApi.loadMoreMessages(peerId);
  }

  Future<void> unloadChatMessages(String peerId) async {
    await _historyApi.unloadChatMessages(peerId);
  }

  Future<int?> messageOffsetFromNewest(String peerId, String messageId) {
    return _historyApi.messageOffsetFromNewest(peerId, messageId);
  }

  Future<String?> firstInitialUnreadMessageId(String peerId) {
    return _historyApi.firstInitialUnreadMessageId(peerId);
  }

  Future<void> _persistChatSummary(Chat chat) async {
    await _chatSummaryService.persistChatSummary(chat);
  }

  void _schedulePersistChatSummary(String peerId) {
    final chat = chats[peerId];
    if (chat == null) {
      return;
    }
    unawaited(_persistChatSummary(chat));
  }

  Future<void> _appendMessage(String peerId, Message message) async {
    await _messagesApi.appendMessage(peerId, message);
  }

  Future<bool> _removeMessage(String peerId, String messageId) async {
    return _messagesApi.removeMessage(peerId, messageId);
  }

  Future<Message?> _findMessage(String peerId, String messageId) async {
    return _messagesApi.findMessage(peerId, messageId);
  }

  Future<void> _deleteManagedMediaForMessage(Message? message) async {
    await _messagesApi.deleteManagedMediaForMessage(message);
  }

  Future<bool> _removeMessageWithMediaCleanup(
    String peerId,
    String messageId,
  ) async {
    return _messagesApi.removeMessageWithMediaCleanup(peerId, messageId);
  }

  Future<bool> _removeMessageByAuthorWithMediaCleanup(
    String peerId,
    String messageId,
    String authorPeerId,
  ) async {
    return _messagesApi.removeMessageByAuthorWithMediaCleanup(
      peerId,
      messageId,
      authorPeerId,
    );
  }

  Future<void> _replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  ) async {
    await _messagesApi.replaceMessage(peerId, messageId, transform);
  }

  bool _isGroupDeletePayload(String text) {
    return _groupsApi.isGroupDeletePayload(text);
  }

  Future<void> _rotateGroupKey(
    Chat groupChat, {
    required List<String> recipients,
  }) async {
    await _groupsApi.rotateGroupKey(groupChat, recipients: recipients);
  }

  Future<void> _syncGroupMembershipWithRelay(Chat groupChat) async {
    await _groupsApi.syncGroupMembershipWithRelay(groupChat);
  }

  Future<String?> _decryptGroupText(String text) async {
    return _groupsApi.decryptGroupText(text);
  }

  Future<Uint8List?> _decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    return _groupsApi.decryptGroupBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  Future<void> _handleIncomingGroupMembersUpdate(
    ChatMessage msg, {
    IncomingGroupMembersPayload? payload,
  }) async {
    await _groupsApi.handleIncomingGroupMembersUpdate(msg, payload: payload);
  }

  Future<void> _handleIncomingDirectBlobRef(
    ChatMessage msg,
    IncomingBlobRefPayload blobRef,
  ) async {
    await _chatInboundService.handleIncomingDirectBlobRef(
      msg,
      blobRef,
      ensureChatLoaded: ensureChatLoaded,
      ensureChat: _ensureChat,
      persistLoadedChat: _historyApi.persistLoadedChat,
      directBlobTransferId: _outboundCodec.directBlobTransferId,
      notifyMessageUpdated: _notifyMessageUpdated,
      shouldAutoRestoreIncomingMedia: _shouldAutoRestoreIncomingMedia,
      incomingRelayFetchStatus: _mediaApi.incomingRelayFetchStatus,
      restoreMediaInBackground: _restoreMediaInBackground,
      sendDeliveredReceipt: _messagesApi.sendDeliveredForMessage,
      notifyNewMessage: _newMessageNotificationController.add,
      unreadMessagesCount: unreadMessagesCount,
      showMessageNotification:
          NotificationService.instance.showMessageNotification,
    );
  }

  Stream<ChatMessage> get newMessageNotifications =>
      _newMessageNotificationController.stream;

  Stream<String> get connectionStatusStream =>
      _connectionStatusController.stream;
  Stream<String> get messageUpdatesStream => _messageUpdatesController.stream;
  String get localPeerId => runtime.peerId;

  ChatConnectionStatus connectionStatus(String peerId) =>
      _connectionStatus[peerId] ?? ChatConnectionStatus.disconnected;

  String? connectionError(String peerId) => _connectionErrors[peerId];

  int unreadMessagesCount() {
    return _messagesApi.unreadMessagesCount();
  }

  void _syncBadgeCount() {
    _messagesApi.syncBadgeCount();
  }

  String _nextLocalMessageId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now <= _lastGeneratedMessageId) {
      _lastGeneratedMessageId += 1;
    } else {
      _lastGeneratedMessageId = now;
    }
    return _lastGeneratedMessageId.toString();
  }

  String? contactNameForPeer(String peerId) {
    return _chatContactsService.contactNameForPeer(peerId);
  }

  List<Contact> getContacts() {
    return _chatContactsService.getContacts();
  }

  Future<void> addOrUpdateContact({
    required String peerId,
    required String name,
  }) async {
    await _chatContactsService.addOrUpdateContact(
      peerId: peerId,
      name: name,
      chats: chats,
      schedulePersistChatSummary: _schedulePersistChatSummary,
      notifyContactsUpdated: () {
        _messageUpdatesController.add('');
      },
    );
  }

  Future<void> setGroupAvatar({
    required String groupId,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) async {
    await _groupsApi.setGroupAvatar(
      groupId: groupId,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  Future<void> _saveGroupAvatarBytes({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  }) async {
    await _groupsApi.saveGroupAvatarBytes(
      groupChat: groupChat,
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: updatedAtMs,
    );
  }

  Future<Chat> createGroupChat({
    required String name,
    required List<String> memberPeerIds,
    bool sendInvites = true,
  }) async {
    return _groupsApi.createGroupChat(
      name: name,
      memberPeerIds: memberPeerIds,
      sendInvites: sendInvites,
    );
  }

  Future<Chat> createDirectChat({required String peerId, String? name}) async {
    return _directLifecycleService.createDirectChat(peerId: peerId, name: name);
  }

  Future<void> addGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  }) async {
    await _groupsApi.addGroupParticipants(
      groupId: groupId,
      participantPeerIds: participantPeerIds,
    );
  }

  Future<void> removeGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  }) async {
    await _groupsApi.removeGroupParticipants(
      groupId: groupId,
      participantPeerIds: participantPeerIds,
    );
  }

  Future<void> renameGroupChat({
    required String groupId,
    required String newName,
  }) async {
    await _groupsApi.renameGroupChat(groupId: groupId, newName: newName);
  }

  Future<void> sendMessage(
    String peerId,
    String text, {
    Message? replyTo,
  }) async {
    if (_safetyApi.isPeerBlocked(peerId)) {
      throw StateError('Peer is blocked');
    }
    await _messagesApi.sendMessage(peerId, text, replyTo: replyTo);
  }

  Future<void> sendFile(
    String peerId, {
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    int? fileSizeBytes,
    String? mimeType,
    Message? replyTo,
  }) async {
    if (_safetyApi.isPeerBlocked(peerId)) {
      throw StateError('Peer is blocked');
    }
    await _mediaApi.sendFile(
      peerId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
    );
  }

  Future<void> requestDeleteForEveryone(String peerId, String messageId) async {
    await _groupsApi.requestDeleteForEveryone(peerId, messageId);
  }

  void _resumeRecoverableFileQueue() {
    _mediaApi.resumeRecoverableFileQueue();
  }

  Future<void> _broadcastGroupMembersUpdate({
    required Chat groupChat,
    required List<String> recipients,
    required String action,
    required List<String> changedPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  }) async {
    await _groupsApi.broadcastGroupMembersUpdate(
      groupChat: groupChat,
      recipients: recipients,
      action: action,
      changedPeerIds: changedPeerIds,
      avatarBlobId: avatarBlobId,
      avatarMimeType: avatarMimeType,
      avatarFileSizeBytes: avatarFileSizeBytes,
      avatarUpdatedAtMs: avatarUpdatedAtMs,
    );
  }

  Future<void> applyGroupMembersUpdateFromPush(
    Map<String, dynamic> payload, {
    String? sourcePeerId,
  }) async {
    await _groupsApi.applyGroupMembersUpdateFromPush(
      payload,
      sourcePeerId: sourcePeerId,
    );
  }

  Future<void> cancelFileTransfer(String peerId, String messageId) async {
    await _mediaApi.cancelFileTransfer(peerId, messageId);
  }

  Future<void> retryMessage(String peerId, String messageId) async {
    await _messagesApi.retryMessage(peerId, messageId);
  }

  Future<void> connect(String peerId) async {
    await _directLifecycleService.connect(peerId);
  }

  List<Chat> getChatsSorted() {
    return _directLifecycleService
        .getChatsSorted()
        .where(_safetyApi.isChatVisible)
        .toList(growable: false);
  }

  List<Message> visibleMessages(Chat chat) => _safetyApi.visibleMessages(chat);

  Message? visiblePreview(Chat chat) => _safetyApi.visiblePreview(chat);

  Future<void> clearManagedMediaReferencesInMemory() async {
    await _cleanupApi.clearManagedMediaReferencesInMemory();
  }

  void clearAllChatsFromMemory() {
    _cleanupApi.clearAllChatsFromMemory();
  }

  Chat openChat(String peerId, String name) {
    return _directLifecycleService.openChat(peerId, name);
  }

  Future<void> addMessage(String peerId, Message message) async {
    await ensureChatLoaded(peerId);
    await _messagesApi.appendMessage(peerId, message);
    _messageUpdatesController.add(peerId);
  }

  Future<void> deleteMessage(String peerId, String messageId) async {
    await _cleanupApi.deleteMessage(peerId, messageId);
  }

  Future<void> deleteChat(String peerId) async {
    await _cleanupApi.deleteChat(peerId);
  }

  bool isPeerBlocked(String peerId) => _safetyApi.isPeerBlocked(peerId);

  Future<void> blockPeer(String peerId, {String? reason}) async {
    await blockAndReportPeer(
      peerId,
      reason: ModerationReportReason.values.firstWhere(
        (value) => value.name == reason,
        orElse: () => ModerationReportReason.other,
      ),
    );
  }

  Future<void> blockAndReportPeer(
    String peerId, {
    required ModerationReportReason reason,
    String? groupId,
  }) => _safetyApi.blockAndReport(peerId, reason: reason, groupId: groupId);

  Future<void> unblockPeer(String peerId) async {
    await _safetyApi.unblock(peerId);
  }

  Future<void> reportPeer({
    required String peerId,
    required ModerationReportReason reason,
    Message? selectedMessage,
    String? groupId,
  }) {
    return _safetyApi.reportPeer(
      peerId: peerId,
      reason: reason,
      selectedMessage: selectedMessage,
      groupId: groupId,
    );
  }

  Future<void> _deleteChatLocal(
    String peerId, {
    bool rememberDeletedGroup = false,
    String? deletedByPeerId,
  }) async {
    await _groupsApi.deleteChatLocal(
      peerId,
      rememberDeletedGroup: rememberDeletedGroup,
      deletedByPeerId: deletedByPeerId,
    );
  }

  Future<void> markChatAsRead(String peerId) async {
    await _messagesApi.markChatAsRead(peerId);
  }

  Future<void> _handleIncomingMessageReceipt(
    IncomingMessageReceiptPayload payload,
  ) async {
    await _messagesApi.applyIncomingReceipt(payload);
  }

  Future<void> _updateMessageStatusById(
    String peerId,
    String messageId,
    MessageStatus status,
  ) async {
    await _messagesApi.updateMessageStatusById(peerId, messageId, status);
  }

  String _transferStatusForError(Object error, {required String fallback}) {
    return _mediaApi.transferStatusForError(error, fallback: fallback);
  }

  Future<void> _updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  }) async {
    await _mediaApi.updateFileProgress(
      peerId,
      messageId,
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
    );
  }

  void _clearProgressUpdate(String peerId, String messageId) {
    _mediaApi.clearProgressUpdate(peerId, messageId);
  }

  String _incomingMediaKey(String peerId, String messageId) =>
      _mediaApi.incomingMediaKey(peerId, messageId);

  Future<void> _resumeInterruptedIncomingMediaQueue({
    required String reason,
  }) async {
    await _mediaApi.resumeInterruptedIncomingMediaQueue(reason: reason);
  }

  Future<String?> restoreMediaFromEmbedded(String peerId, Message message) {
    return _mediaApi.restoreMediaFromEmbedded(peerId, message);
  }

  Future<String?> restoreGroupBlobMedia(Message message) {
    return _mediaApi.restoreGroupBlobMedia(message);
  }

  Future<String?> restoreDirectBlobMedia(Message message) {
    return _mediaApi.restoreDirectBlobMedia(message);
  }

  Future<String?> _ensureThumbnail(Message message) {
    return _mediaApi.ensureThumbnail(message);
  }

  void _restoreMediaInBackground(
    Message message, {
    required bool isGroup,
    bool force = false,
  }) {
    _mediaApi.restoreMediaInBackground(message, isGroup: isGroup, force: force);
  }

  bool isIncomingRelayMediaRestoreInProgress(Message message) {
    return _mediaApi.isIncomingRelayMediaRestoreInProgress(message);
  }

  bool isIncomingRelayMediaRestoreFailed(Message message) {
    return _mediaApi.isIncomingRelayMediaRestoreFailed(message);
  }

  bool isInitialUnreadAnchor(Message message) {
    return _mediaApi.isInitialUnreadAnchor(message);
  }

  bool _shouldAutoRestoreIncomingMedia(Message message) {
    return _mediaApi.shouldAutoRestoreIncomingMedia(message);
  }

  Future<Uint8List> _decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    return _groupsApi.decodeGroupBlobBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  Future<String?> _restoreGroupBlobText({
    required String groupId,
    required String blobId,
    List<String>? relayServers,
    String? fallback,
  }) async {
    return _mediaApi.restoreGroupBlobText(
      groupId: groupId,
      blobId: blobId,
      relayServers: relayServers,
      fallback: fallback,
    );
  }

  void _setStatus(String peerId, ChatConnectionStatus status, {String? error}) {
    _connectionStatus[peerId] = status;
    _connectionErrors[peerId] = error;
    _connectionStatusController.add(peerId);
  }

  void _notifyMessageUpdated(String peerId) {
    _messageUpdatesController.add(peerId);
  }

  void _logQueue(String message) {
    developer.log('queue:$message', name: 'chat');
    AppFileLogger.log('[chat_queue] $message');
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _mediaApi.dispose();
    await _inboundSubscriptionCoordinator.dispose();
    await _lifecycleService.dispose();
    await _connectionStatusController.close();
    await _messageUpdatesController.close();
    await _newMessageNotificationController.close();
  }

  Stream<List<String>> get discoveredPeersStream =>
      runtime.discoveredPeersStream;

  Future<void> startCall(String peerId) {
    if (_safetyApi.isPeerBlocked(peerId)) {
      throw StateError('Peer is blocked');
    }
    return runtime.startCall(peerId);
  }
}

final class _ChatControllerPresentationStatePort
    implements ChatPresentationStatePort {
  const _ChatControllerPresentationStatePort(this._controller);

  final ChatController _controller;

  @override
  Map<String, Chat> get chats => _controller.chats;

  @override
  String Function(String peerId, {String? fallback}) get contactNameFor =>
      _controller._contactNameFor;

  @override
  Chat ensureChat(String peerId, {String? fallbackName}) {
    return _controller._ensureChat(peerId, fallbackName: fallbackName);
  }

  @override
  Future<void> ensureChatLoaded(String peerId) {
    return _controller.ensureChatLoaded(peerId);
  }

  @override
  Future<void> persistChatSummary(Chat chat) {
    return _controller._persistChatSummary(chat);
  }

  @override
  void schedulePersistChatSummary(String peerId) {
    _controller._schedulePersistChatSummary(peerId);
  }

  @override
  bool isInitialUnreadAnchor(Message message) {
    return _controller.isInitialUnreadAnchor(message);
  }
}

final class _ChatControllerConnectionStatePort
    implements ChatConnectionStatePort {
  const _ChatControllerConnectionStatePort(this._controller);

  final ChatController _controller;

  @override
  void setStatus(String peerId, ChatConnectionStatus status, {String? error}) {
    _controller._setStatus(peerId, status, error: error);
  }
}

final class _ChatControllerMessageStatePort implements ChatMessageStatePort {
  const _ChatControllerMessageStatePort(this._controller);

  final ChatController _controller;

  @override
  String nextLocalMessageId() => _controller._nextLocalMessageId();

  @override
  Future<Message?> findMessage(String peerId, String messageId) {
    return _controller._findMessage(peerId, messageId);
  }

  @override
  Future<void> appendMessage(String peerId, Message message) {
    return _controller._appendMessage(peerId, message);
  }

  @override
  Future<void> replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  ) {
    return _controller._replaceMessage(peerId, messageId, transform);
  }

  @override
  Future<bool> removeMessage(String peerId, String messageId) {
    return _controller._removeMessage(peerId, messageId);
  }

  @override
  Future<bool> removeMessageWithMediaCleanup(String peerId, String messageId) {
    return _controller._removeMessageWithMediaCleanup(peerId, messageId);
  }

  @override
  Future<bool> removeMessageByAuthorWithMediaCleanup(
    String peerId,
    String messageId,
    String authorPeerId,
  ) {
    return _controller._removeMessageByAuthorWithMediaCleanup(
      peerId,
      messageId,
      authorPeerId,
    );
  }

  @override
  Future<void> deleteManagedMediaForMessage(Message? message) {
    return _controller._deleteManagedMediaForMessage(message);
  }

  @override
  Future<void> updateMessageStatusById(
    String peerId,
    String messageId,
    MessageStatus status,
  ) {
    return _controller._updateMessageStatusById(peerId, messageId, status);
  }
}

final class _ChatControllerMediaStatePort implements ChatMediaStatePort {
  const _ChatControllerMediaStatePort(this._controller);

  final ChatController _controller;

  @override
  Future<void> updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  }) {
    return _controller._updateFileProgress(
      peerId,
      messageId,
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
    );
  }

  @override
  void clearProgressUpdate(String peerId, String messageId) {
    _controller._clearProgressUpdate(peerId, messageId);
  }

  @override
  Future<String?> ensureThumbnail(Message message) {
    return _controller._ensureThumbnail(message);
  }

  @override
  String mediaKeyFor(String peerId, String messageId) {
    return _controller._incomingMediaKey(peerId, messageId);
  }

  @override
  Future<Uint8List> decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) {
    return _controller._decodeGroupBlobBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  @override
  Future<void> rememberOutgoingRelayMediaState(OutgoingRelayMediaState state) {
    return _controller._rememberOutgoingRelayMediaState(state);
  }

  @override
  Future<void> forgetOutgoingRelayMediaState(String peerId, String messageId) {
    return _controller._forgetOutgoingRelayMediaState(peerId, messageId);
  }

  @override
  String transferStatusForError(Object error, {required String fallback}) {
    return _controller._transferStatusForError(error, fallback: fallback);
  }

  @override
  void restoreMediaInBackground(
    Message message, {
    required bool isGroup,
    bool force = false,
  }) {
    _controller._restoreMediaInBackground(
      message,
      isGroup: isGroup,
      force: force,
    );
  }

  @override
  Future<String?> restoreGroupBlobText({
    required String groupId,
    required String blobId,
    List<String>? relayServers,
    String? fallback,
  }) {
    return _controller._restoreGroupBlobText(
      groupId: groupId,
      blobId: blobId,
      relayServers: relayServers,
      fallback: fallback,
    );
  }
}

final class _ChatControllerGroupStatePort implements ChatGroupStatePort {
  const _ChatControllerGroupStatePort(this._controller);

  final ChatController _controller;

  @override
  Future<void> handleIncomingGroupMembersUpdate(
    ChatMessage message, {
    IncomingGroupMembersPayload? payload,
  }) {
    return _controller._handleIncomingGroupMembersUpdate(
      message,
      payload: payload,
    );
  }

  @override
  Future<void> rememberDeletedGroup(
    String groupId, {
    required String deletedByPeerId,
    Chat? chat,
  }) {
    return _controller._rememberDeletedGroup(
      groupId,
      deletedByPeerId: deletedByPeerId,
      chat: chat,
    );
  }

  @override
  Future<void> runGroupKeyGc() => _controller._runGroupKeyGc();

  @override
  bool isGroupDeleted(String groupId) => _controller._isGroupDeleted(groupId);

  @override
  Future<void> restoreDeletedGroup(String groupId) {
    return _controller._restoreDeletedGroup(groupId);
  }

  @override
  Future<String?> decryptGroupText(String text) {
    return _controller._decryptGroupText(text);
  }

  @override
  Future<Uint8List?> decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) {
    return _controller._decryptGroupBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  @override
  Future<void> saveGroupAvatarBytes({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  }) {
    return _controller._saveGroupAvatarBytes(
      groupChat: groupChat,
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: updatedAtMs,
    );
  }

  @override
  Future<void> rotateGroupKey(Chat chat, {required List<String> recipients}) {
    return _controller._rotateGroupKey(chat, recipients: recipients);
  }

  @override
  Future<void> syncGroupMembershipWithRelay(Chat chat) {
    return _controller._syncGroupMembershipWithRelay(chat);
  }

  @override
  Future<void> broadcastGroupMembersUpdate({
    required Chat groupChat,
    required List<String> recipients,
    required String action,
    required List<String> changedPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  }) {
    return _controller._broadcastGroupMembersUpdate(
      groupChat: groupChat,
      recipients: recipients,
      action: action,
      changedPeerIds: changedPeerIds,
      avatarBlobId: avatarBlobId,
      avatarMimeType: avatarMimeType,
      avatarFileSizeBytes: avatarFileSizeBytes,
      avatarUpdatedAtMs: avatarUpdatedAtMs,
    );
  }

  @override
  Future<void> deleteChatLocal(
    String peerId, {
    bool rememberDeletedGroup = false,
    String? deletedByPeerId,
  }) {
    return _controller._deleteChatLocal(
      peerId,
      rememberDeletedGroup: rememberDeletedGroup,
      deletedByPeerId: deletedByPeerId,
    );
  }

  @override
  bool isGroupDeletePayload(String text) {
    return _controller._isGroupDeletePayload(text);
  }
}

final class _ChatControllerNotificationPort implements ChatNotificationPort {
  const _ChatControllerNotificationPort(this._controller);

  final ChatController _controller;

  @override
  void syncBadgeCount() {
    _controller._syncBadgeCount();
  }

  @override
  void notifyMessageUpdated(String peerId) {
    _controller._notifyMessageUpdated(peerId);
  }

  @override
  bool isMessageUpdatesClosed() {
    return _controller._messageUpdatesController.isClosed;
  }

  @override
  int unreadMessagesCount() => _controller.unreadMessagesCount();

  @override
  void Function(int unreadCount)? get onUnreadBadgeCountChanged =>
      _controller._onUnreadBadgeCountChanged;

  @override
  void notifyNewMessage(ChatMessage message) {
    _controller._newMessageNotificationController.add(message);
  }
}

final class _ChatControllerLifecyclePort implements ChatLifecyclePort {
  const _ChatControllerLifecyclePort(this._controller);

  final ChatController _controller;

  @override
  void logQueue(String message) {
    _controller._logQueue(message);
  }

  @override
  void resumeRecoverableFileQueue() {
    _controller._resumeRecoverableFileQueue();
  }

  @override
  Future<void> resumePendingOutgoingRelayMedia({required String reason}) {
    return _controller._resumePendingOutgoingRelayMedia(reason: reason);
  }

  @override
  Future<void> resumeInterruptedIncomingMediaQueue({required String reason}) {
    return _controller._resumeInterruptedIncomingMediaQueue(reason: reason);
  }

  @override
  Future<void> waitUntilReady() {
    return _controller._waitUntilStartupReady();
  }
}

final class _ChatControllerInboundPort implements ChatInboundPort {
  const _ChatControllerInboundPort(this._controller);

  final ChatController _controller;

  @override
  Future<void> handleIncomingDirectBlobRef(
    ChatMessage message,
    IncomingBlobRefPayload blobRef,
  ) {
    return _controller._handleIncomingDirectBlobRef(message, blobRef);
  }

  @override
  Future<void> handleIncomingMessageReceipt(
    IncomingMessageReceiptPayload payload,
  ) {
    return _controller._handleIncomingMessageReceipt(payload);
  }
}

final class _ChatControllerAccountPayloadPort
    implements ChatAccountPayloadPort {
  const _ChatControllerAccountPayloadPort();

  @override
  AccountPairingRequestPayloadDecoder get decodeAccountPairRequest =>
      ChatAccountPayloadDecoder.decodePairRequest;

  @override
  AccountPairingApprovalPayloadDecoder get decodeAccountPairApproval =>
      ChatAccountPayloadDecoder.decodePairApproval;

  @override
  AccountPairingRejectionPayloadDecoder get decodeAccountPairRejection =>
      ChatAccountPayloadDecoder.decodePairRejection;

  @override
  AccountMembershipUpdatePayloadDecoder get decodeAccountMembershipUpdate =>
      ChatAccountPayloadDecoder.decodeMembershipUpdate;
}
