class ReliableOperationId {
  const ReliableOperationId._();

  static String pendingMessage({
    required bool isGroup,
    required String targetId,
    String? messageId,
  }) {
    final prefix = isGroup ? 'group' : 'direct';
    final effectiveMessageId =
        messageId ?? DateTime.now().microsecondsSinceEpoch.toString();
    return '$prefix:$targetId:$effectiveMessageId';
  }
}
