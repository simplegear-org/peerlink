import '../models/message.dart';

class ChatScreenUnreadTargetResolver {
  const ChatScreenUnreadTargetResolver._();

  static bool containsMessage(List<Message> messages, String messageId) {
    return messages.any((message) => message.id == messageId);
  }

  static String? firstUnreadMessageId(
    List<Message> messages, {
    required bool Function(Message message) isInitialUnreadAnchor,
  }) {
    for (final message in messages) {
      if (isInitialUnreadAnchor(message)) {
        return message.id;
      }
    }
    return null;
  }
}
