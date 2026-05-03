import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../localization/app_strings.dart';
import '../state/chat_controller.dart';
import '../state/avatar_service.dart';
import '../state/presence_service.dart';
import '../widgets/compact_card_tile_styles.dart';
import '../widgets/chat_tile.dart';
import '../widgets/peer_avatar.dart';
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
  StreamSubscription<String>? _avatarSubscription;

  @override
  void initState() {
    super.initState();
    _messageSubscription = widget.controller.messageUpdatesStream.listen((
      peerId,
    ) {
      if (!mounted) return;
      setState(() {});
    });
    _avatarSubscription = widget.avatarService.updatesStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _avatarSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = widget.controller.getChatsSorted();

    return Scaffold(
      appBar: AppBar(title: Text(context.strings.chats)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateChatTypeSheet,
        icon: const Icon(Icons.group_add_rounded),
        label: Text(context.strings.newChat),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            if (chats.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: const ChatsEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final chat = chats[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == chats.length - 1
                            ? 0
                            : CompactCardTileStyles.tileSeparatorHeight,
                      ),
                      child: ChatTile(
                        key: ValueKey('chat-${chat.peerId}'),
                        chat: chat,
                        avatar: PeerAvatar(
                          peerId: chat.peerId,
                          displayName: chat.name,
                          avatarService: widget.avatarService,
                          imagePath: chat.isGroup ? chat.avatarPath : null,
                          size: CompactCardTileStyles.avatarSize,
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
                      ),
                    );
                  }, childCount: chats.length),
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
                  title: Text(context.strings.directChat),
                  onTap: () => Navigator.pop(ctx, 'direct'),
                ),
                ListTile(
                  leading: const Icon(Icons.groups_2_rounded),
                  title: Text(context.strings.groupChat),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.addContactsFirst)));
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
                leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.addContactsFirst)));
      return;
    }

    final nameCtrl = TextEditingController();
    final selectedPeerIds = <String>{};
    var isCreating = false;

    final createdChat = await showModalBottomSheet<Chat>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final canCreate =
                !isCreating &&
                nameCtrl.text.trim().isNotEmpty &&
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
                    Text(
                      context.strings.createGroupChat,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: context.strings.chatName,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setLocalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.strings.members,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 260,
                      child: ListView.builder(
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          final selected = selectedPeerIds.contains(
                            contact.peerId,
                          );
                          return CheckboxListTile(
                            value: selected,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(contact.name),
                            subtitle: Text(contact.shortId()),
                            onChanged: isCreating
                                ? null
                                : (value) {
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
                            onPressed: isCreating
                                ? null
                                : () => Navigator.pop(context),
                            child: Text(context.strings.cancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: canCreate
                                ? () async {
                                    setLocalState(() {
                                      isCreating = true;
                                    });
                                    try {
                                      final chat = await widget.controller
                                          .createGroupChat(
                                            name: nameCtrl.text.trim(),
                                            memberPeerIds: selectedPeerIds
                                                .toList(growable: false),
                                          );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      Navigator.pop(context, chat);
                                    } catch (_) {
                                      if (!context.mounted) {
                                        return;
                                      }
                                      setLocalState(() {
                                        isCreating = false;
                                      });
                                    }
                                  }
                                : null,
                            child: Text(
                              isCreating
                                  ? context.strings.creatingGroupChat
                                  : context.strings.create,
                            ),
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
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.deleteChatTitle),
          content: Text(_deleteChatDialogContent(chat, strings)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.delete),
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
        SnackBar(content: Text(context.strings.deleteChatError(error))),
      );
      return false;
    }
  }

  String _deleteChatDialogContent(Chat chat, AppStrings strings) {
    if (!chat.isGroup) {
      return strings.deleteChatContent(chat.name);
    }
    final isOwner = chat.ownerPeerId == widget.controller.facade.peerId;
    return isOwner
        ? strings.deleteGroupChatContent(chat.name)
        : strings.deleteGroupChatLocalContent(chat.name);
  }
}
