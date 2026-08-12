import '../../core/node/node_facade.dart';
import '../models/chat.dart';
import 'chat_controller_models.dart';

class ChatDirectLifecycleService {
  const ChatDirectLifecycleService({
    required NodeFacade facade,
    required Map<String, Chat> chats,
    required String Function(String peerId, {String? fallback}) contactNameFor,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) schedulePersistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
  }) : _facade = facade,
       _chats = chats,
       _contactNameFor = contactNameFor,
       _persistChatSummary = persistChatSummary,
       _schedulePersistChatSummary = schedulePersistChatSummary,
       _notifyMessageUpdated = notifyMessageUpdated,
       _setStatus = setStatus;

  final NodeFacade _facade;
  final Map<String, Chat> _chats;
  final String Function(String peerId, {String? fallback}) _contactNameFor;
  final Future<void> Function(Chat chat) _persistChatSummary;
  final void Function(String peerId) _schedulePersistChatSummary;
  final void Function(String peerId) _notifyMessageUpdated;
  final void Function(
    String peerId,
    ChatConnectionStatus status, {
    String? error,
  })
  _setStatus;

  Chat ensureChat(String peerId, {String? fallbackName}) {
    final chat = _chats.putIfAbsent(
      peerId,
      () => Chat(
        peerId: peerId,
        name: _contactNameFor(peerId, fallback: fallbackName ?? peerId),
      ),
    );

    final resolvedName = _contactNameFor(peerId, fallback: chat.name);
    if (chat.name != resolvedName) {
      chat.name = resolvedName;
      _schedulePersistChatSummary(peerId);
    }
    if (!chat.isGroup && Chat.isGroupLikePeerId(chat.peerId)) {
      chat.isGroup = true;
      _schedulePersistChatSummary(peerId);
    }

    return chat;
  }

  Future<Chat> createDirectChat({required String peerId, String? name}) async {
    final chat = ensureChat(peerId, fallbackName: name);
    if (chat.isGroup || Chat.isGroupLikePeerId(chat.peerId)) {
      _notifyMessageUpdated(peerId);
      return chat;
    }
    chat.isGroup = false;
    chat.memberPeerIds = const <String>[];
    chat.ownerPeerId = null;
    await _persistChatSummary(chat);
    _notifyMessageUpdated(peerId);
    return chat;
  }

  Chat openChat(String peerId, String name) {
    final chat = ensureChat(peerId, fallbackName: name);
    _schedulePersistChatSummary(peerId);
    return chat;
  }

  Future<void> connect(String peerId) async {
    _setStatus(peerId, ChatConnectionStatus.connecting);
    if (_facade.peerId.compareTo(peerId) >= 0) {
      return;
    }
    try {
      await _facade.connectToPeer(peerId);
      _setStatus(peerId, ChatConnectionStatus.connected);
    } catch (e) {
      _setStatus(peerId, ChatConnectionStatus.error, error: e.toString());
      rethrow;
    }
  }

  List<Chat> getChatsSorted() {
    final list = _chats.values.toList();
    for (final chat in list) {
      chat.name = _contactNameFor(chat.peerId, fallback: chat.name);
    }

    list.sort((a, b) {
      final at = a.lastMessage?.timestamp ?? DateTime(0);
      final bt = b.lastMessage?.timestamp ?? DateTime(0);
      return bt.compareTo(at);
    });

    return list;
  }
}
