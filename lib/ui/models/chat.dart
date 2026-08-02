import 'message.dart';

class Chat {
  static bool isGroupLikePeerId(String peerId) => peerId.startsWith('group:');

  final String peerId;
  String name;
  bool isGroup;
  List<String> memberPeerIds;
  String? ownerPeerId;
  String? avatarPath;
  int unreadCount;
  bool messagesLoaded;
  bool hasMoreMessages;
  Message? previewMessage;

  List<Message> messages = [];

  Chat({
    required this.peerId,
    required this.name,
    this.isGroup = false,
    List<String>? memberPeerIds,
    this.ownerPeerId,
    this.avatarPath,
    this.unreadCount = 0,
    this.messagesLoaded = false,
    this.hasMoreMessages = true,
    this.previewMessage,
  }) : memberPeerIds = memberPeerIds ?? <String>[];

  String get id => peerId;

  factory Chat.fromJson(Map<String, dynamic> json) {
    Message? preview;
    final rawPreview = json['lastMessage'];
    if (rawPreview is Map<String, dynamic>) {
      preview = Message.fromSummaryJson(Map<String, dynamic>.from(rawPreview));
    }

    final peerId = json['peerId'] as String;
    final isGroupFlag = json['isGroup'] as bool? ?? false;
    return Chat(
      peerId: peerId,
      name: json['name'] as String,
      isGroup: isGroupFlag || isGroupLikePeerId(peerId),
      memberPeerIds: (json['memberPeerIds'] as List? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      ownerPeerId: json['ownerPeerId'] as String?,
      avatarPath: json['avatarPath'] as String?,
      unreadCount: json['unreadCount'] as int? ?? 0,
      messagesLoaded: false,
      hasMoreMessages: json['hasMoreMessages'] as bool? ?? true,
      previewMessage: preview,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'peerId': peerId,
      'name': name,
      'isGroup': isGroup,
      'memberPeerIds': memberPeerIds,
      'ownerPeerId': ownerPeerId,
      'avatarPath': avatarPath,
      'unreadCount': unreadCount,
      'messagesLoaded': messagesLoaded,
      'hasMoreMessages': hasMoreMessages,
      'lastMessage': lastMessage?.toSummaryJson(),
    };
  }

  Message? get lastMessage {
    if (messages.isNotEmpty) {
      return messages.last;
    }
    return previewMessage;
  }
}
