import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../state/chat_controller.dart';
import '../state/avatar_service.dart';
import '../state/presence_service.dart';
import '../widgets/chat_tile.dart';
import '../widgets/peer_avatar.dart';
import 'chat_screen_helpers.dart';
import 'chat_screen.dart';
import 'chats_screen_view.dart';

class ChatsScreen extends StatefulWidget {
  final ChatController controller;
  final PresenceService presenceService;
  final AvatarService avatarService;

  const ChatsScreen({
    super.key,
    required this.controller,
    required this.presenceService,
    required this.avatarService,
  });

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<String>? _presenceSubscription;
  StreamSubscription<String>? _avatarSubscription;
  Timer? _presenceRefreshTimer;

  @override
  void initState() {
    super.initState();
    _messageSubscription = widget.controller.messageUpdatesStream.listen((peerId) {
      if (!mounted) return;
      setState(() {});
    });
    _presenceSubscription = widget.presenceService.updatesStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    _avatarSubscription = widget.avatarService.updatesStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    _presenceRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _presenceSubscription?.cancel();
    _avatarSubscription?.cancel();
    _presenceRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = widget.controller.getChatsSorted();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateChatTypeSheet,
        icon: const Icon(Icons.group_add_rounded),
        label: const Text('Новый чат'),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: const ChatsScreenHeader(),
            ),
            if (chats.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: const ChatsEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final chat = chats[index];
                      return ChatTile(
                        key: ValueKey('chat-${chat.peerId}'),
                        chat: chat,
                        avatar: PeerAvatar(
                          peerId: chat.peerId,
                          displayName: chat.name,
                          avatarService: widget.avatarService,
                          imagePath: chat.isGroup ? chat.avatarPath : null,
                          size: 52,
                        ),
                        lastSeenText: chat.isGroup
                            ? null
                            : ChatScreenHelpers.lastSeenLabel(
                                isPeerOnline: widget.presenceService.isPeerOnline(chat.peerId),
                                lastSeenAt: widget.presenceService.peerLastSeenAt(chat.peerId),
                                fallbackLastSeenAt: _fallbackLastSeenForChat(chat),
                              ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                chat: chat,
                                controller: widget.controller,
                                presenceService: widget.presenceService,
                                avatarService: widget.avatarService,
                              ),
                            ),
                          );
                        },
                        onDeleteRequested: () => _confirmAndDeleteChat(chat),
                      );
                    },
                    childCount: chats.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateChatTypeSheet() async {
    final selectedType = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: const Text('Индивидуальный чат'),
                  onTap: () => Navigator.pop(ctx, 'direct'),
                ),
                ListTile(
                  leading: const Icon(Icons.groups_2_rounded),
                  title: const Text('Групповой чат'),
                  onTap: () => Navigator.pop(ctx, 'group'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedType == null) {
      return;
    }
    if (selectedType == 'direct') {
      await _showCreateDirectChatSheet();
      return;
    }
    await _showCreateGroupChatSheet();
  }

  Future<void> _showCreateDirectChatSheet() async {
    final contacts = widget.controller.getContacts();
    if (contacts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала добавьте контакты.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<Chat>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: contacts.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_rounded),
                ),
                title: Text(contact.name),
                subtitle: Text(contact.shortId()),
                onTap: () async {
                  final chat = await widget.controller.createDirectChat(
                    peerId: contact.peerId,
                    name: contact.name,
                  );
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.pop(context, chat);
                },
              );
            },
          ),
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }
    setState(() {});
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chat: selected,
          controller: widget.controller,
          presenceService: widget.presenceService,
          avatarService: widget.avatarService,
        ),
      ),
    );
  }

  Future<void> _showCreateGroupChatSheet() async {
    final contacts = widget.controller.getContacts();
    if (contacts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала добавьте контакты.')),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final selectedPeerIds = <String>{};

    final createdChat = await showModalBottomSheet<Chat>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final canCreate = nameCtrl.text.trim().isNotEmpty &&
                selectedPeerIds.isNotEmpty;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Создать групповой чат',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Название чата',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setLocalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Участники',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 260,
                      child: ListView.builder(
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          final selected =
                              selectedPeerIds.contains(contact.peerId);
                          return CheckboxListTile(
                            value: selected,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(contact.name),
                            subtitle: Text(contact.shortId()),
                            onChanged: (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selectedPeerIds.add(contact.peerId);
                                } else {
                                  selectedPeerIds.remove(contact.peerId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: canCreate
                                ? () async {
                                    final chat = await widget.controller
                                        .createGroupChat(
                                      name: nameCtrl.text.trim(),
                                      memberPeerIds:
                                          selectedPeerIds.toList(growable: false),
                                    );
                                    if (!context.mounted) {
                                      return;
                                    }
                                    Navigator.pop(context, chat);
                                  }
                                : null,
                            child: const Text('Создать'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || createdChat == null) {
      return;
    }
    setState(() {});
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chat: createdChat,
          controller: widget.controller,
          presenceService: widget.presenceService,
          avatarService: widget.avatarService,
        ),
      ),
    );
  }

  Future<bool> _confirmAndDeleteChat(Chat chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить чат?'),
          content: Text('Чат "${chat.name}" будет удален.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return false;
    }

    try {
      await widget.controller.deleteChat(chat.peerId);
      if (!mounted) {
        return true;
      }
      setState(() {});
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить чат: $error')),
      );
      return false;
    }
  }

  DateTime? _fallbackLastSeenForChat(Chat chat) {
    for (var i = chat.messages.length - 1; i >= 0; i--) {
      final message = chat.messages[i];
      if (message.incoming) {
        return message.timestamp;
      }
    }
    final preview = chat.previewMessage;
    if (preview != null && preview.incoming) {
      return preview.timestamp;
    }
    return null;
  }
}
