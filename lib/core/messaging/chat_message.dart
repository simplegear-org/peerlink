enum ChatMessageStatus {
  sending,
  sent,
  delivered,
  failed,
}

class ChatMessage {
  final String messageId;
  final String chatId;
  final String from;
  final String text;
  final int timestamp;
  ChatMessageStatus status;

  ChatMessage({
    required this.messageId,
    required this.chatId,
    required this.from,
    required this.text,
    required this.timestamp,
    this.status = ChatMessageStatus.sending,
  });

  Map<String, dynamic> toJson() => {
        "messageId": messageId,
        "chatId": chatId,
        "from": from,
        "text": text,
        "timestamp": timestamp,
        "status": status.name,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: json["messageId"],
      chatId: json["chatId"],
      from: json["from"],
      text: json["text"],
      timestamp: json["timestamp"],
      status: ChatMessageStatus.values
          .firstWhere((e) => e.name == json["status"]),
    );
  }
}
