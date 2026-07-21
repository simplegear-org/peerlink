import '../localization/app_strings.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import '../state/chat_controller_models.dart';
import '../state/presence_service.dart';
import 'chat_screen_helpers.dart';

class ChatScreenPresenter {
  final Chat Function() chat;
  final ChatController Function() controller;
  final PresenceService Function() presenceService;
  final AppStrings Function() strings;
  final ChatConnectionStatus Function() connectionStatus;
  final String? Function() connectionError;
  final bool Function() isGroupChat;

  const ChatScreenPresenter({
    required this.chat,
    required this.controller,
    required this.presenceService,
    required this.strings,
    required this.connectionStatus,
    required this.connectionError,
    required this.isGroupChat,
  });

  bool get canAddChatContact =>
      !isGroupChat() &&
      chat().peerId.trim().isNotEmpty &&
      controller().contactNameForPeer(chat().peerId) == null;

  String shortPeerId(String peerId) {
    if (peerId.length <= 8) {
      return peerId;
    }
    return '${peerId.substring(0, 4)}...${peerId.substring(peerId.length - 4)}';
  }

  String? senderLabelFor(Message message) {
    if (!isGroupChat() || !message.incoming) {
      return null;
    }
    final senderPeerId = message.senderPeerId;
    if (senderPeerId == null || senderPeerId.trim().isEmpty) {
      return null;
    }
    final contactName = controller().contactNameForPeer(senderPeerId);
    if (contactName != null && contactName.trim().isNotEmpty) {
      return contactName;
    }
    return shortPeerId(senderPeerId);
  }

  String? replySenderLabelFor(Message message) {
    if (!message.incoming) {
      return strings().you;
    }
    if (isGroupChat()) {
      return senderLabelFor(message) ??
          shortPeerId(message.senderPeerId ?? message.peerId);
    }
    return chat().name;
  }

  String replyPreviewFor(Message message) {
    if (message.kind == MessageKind.file) {
      if (message.isAudio) {
        return strings().voiceMessage;
      }
      if (message.isImage) {
        return strings().photo;
      }
      if (message.isVideo) {
        return strings().video;
      }
      return message.fileName?.trim().isNotEmpty == true
          ? message.fileName!
          : strings().file;
    }
    final text = message.text.trim();
    if (text.isEmpty) {
      return strings().message;
    }
    return text;
  }

  String statusLabel() => ChatScreenHelpers.statusLabel(
    connectionStatus(),
    connectionError(),
    isPeerOnline: presenceService().isPeerOnline(chat().peerId),
    lastSeenAt: presenceService().peerLastSeenAt(chat().peerId),
    fallbackLastSeenAt: fallbackLastSeenFromMessages(),
    strings: strings(),
  );

  DateTime? fallbackLastSeenFromMessages() {
    final messages = chat().messages;
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.incoming) {
        return message.timestamp;
      }
    }
    final preview = chat().previewMessage;
    if (preview != null && preview.incoming) {
      return preview.timestamp;
    }
    return null;
  }
}
