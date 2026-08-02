import 'dart:typed_data';

import '../../core/security/group_message_crypto_service.dart';
import '../models/chat.dart';
import 'chat_group_flow_service.dart';

class ChatGroupCryptoCoordinator {
  const ChatGroupCryptoCoordinator({
    required ChatGroupFlowService groupFlowService,
    required GroupMessageCryptoService groupMessageCryptoService,
  }) : _groupFlowService = groupFlowService,
       _groupMessageCryptoService = groupMessageCryptoService;

  final ChatGroupFlowService _groupFlowService;
  final GroupMessageCryptoService _groupMessageCryptoService;

  Future<void> rotateGroupKey(
    Chat groupChat, {
    required List<String> recipients,
  }) {
    return _groupFlowService.rotateGroupKey(groupChat, recipients: recipients);
  }

  Future<String> ensureGroupKey(Chat groupChat) {
    return _groupFlowService.ensureGroupKey(groupChat);
  }

  Future<void> syncGroupMembershipWithRelay(Chat groupChat) {
    return _groupFlowService.syncGroupMembershipWithRelay(groupChat);
  }

  Future<String?> encryptGroupText({
    required String groupId,
    required String plainText,
  }) {
    return _groupMessageCryptoService.encryptGroupText(
      groupId: groupId,
      plainText: plainText,
    );
  }

  Future<Uint8List?> encryptGroupBytes({
    required String groupId,
    required Uint8List plainBytes,
  }) {
    return _groupMessageCryptoService.encryptGroupBytes(
      groupId: groupId,
      plainBytes: plainBytes,
    );
  }

  Future<String?> decryptGroupText(String text) {
    return _groupMessageCryptoService.decryptGroupText(text);
  }

  Future<Uint8List?> decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) {
    return _groupMessageCryptoService.decryptGroupBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  Future<Uint8List> decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) {
    return _groupMessageCryptoService.decodeGroupBlobBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  List<String> collectGroupRecipients(Chat groupChat) {
    return _groupFlowService.collectGroupRecipients(groupChat);
  }
}
