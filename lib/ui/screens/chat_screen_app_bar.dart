import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/runtime/avatar_service.dart';
import '../localization/app_strings.dart';
import '../models/chat.dart';
import '../theme/app_theme.dart';
import '../widgets/peer_avatar.dart';
import 'chat_screen_actions.dart';

class ChatScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Chat chat;
  final AvatarService avatarService;
  final bool isGroupChat;
  final bool isGroupOwner;
  final bool canAddChatContact;
  final String subtitle;
  final VoidCallback? onCallPressed;
  final Future<void> Function(String peerId) onAddContactPressed;
  final Future<void> Function() onAddParticipantsPressed;
  final Future<void> Function() onRemoveParticipantsPressed;
  final Future<void> Function() onRenameGroupPressed;
  final Future<void> Function() onSetAvatarPressed;
  final Future<void> Function() onDeleteChatPressed;

  const ChatScreenAppBar({
    super.key,
    required this.chat,
    required this.avatarService,
    required this.isGroupChat,
    required this.isGroupOwner,
    required this.canAddChatContact,
    required this.subtitle,
    required this.onCallPressed,
    required this.onAddContactPressed,
    required this.onAddParticipantsPressed,
    required this.onRemoveParticipantsPressed,
    required this.onRenameGroupPressed,
    required this.onSetAvatarPressed,
    required this.onDeleteChatPressed,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return AppBar(
      titleSpacing: 20,
      title: Row(
        children: [
          PeerAvatar(
            peerId: chat.peerId,
            displayName: chat.name,
            avatarService: avatarService,
            imagePath: isGroupChat ? chat.avatarPath : null,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chat.name),
                Text(
                  subtitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!isGroupChat && onCallPressed != null)
          IconButton(
            icon: const Icon(Icons.call_rounded),
            onPressed: onCallPressed,
          ),
        PopupMenuButton<ChatMenuAction>(
          onSelected: (action) {
            switch (action) {
              case ChatMenuAction.addContact:
                unawaited(onAddContactPressed(chat.peerId));
                break;
              case ChatMenuAction.addParticipants:
                unawaited(onAddParticipantsPressed());
                break;
              case ChatMenuAction.removeParticipants:
                unawaited(onRemoveParticipantsPressed());
                break;
              case ChatMenuAction.renameGroup:
                unawaited(onRenameGroupPressed());
                break;
              case ChatMenuAction.setAvatar:
                unawaited(onSetAvatarPressed());
                break;
              case ChatMenuAction.deleteChat:
                unawaited(onDeleteChatPressed());
                break;
            }
          },
          itemBuilder: (context) => [
            if (canAddChatContact)
              PopupMenuItem(
                value: ChatMenuAction.addContact,
                child: Text(strings.addContact),
              ),
            if (isGroupOwner)
              PopupMenuItem(
                value: ChatMenuAction.addParticipants,
                child: Text(strings.addParticipants),
              ),
            if (isGroupOwner)
              PopupMenuItem(
                value: ChatMenuAction.removeParticipants,
                child: Text(strings.removeParticipants),
              ),
            if (isGroupOwner)
              PopupMenuItem(
                value: ChatMenuAction.renameGroup,
                child: Text(strings.renameChat),
              ),
            if (isGroupOwner)
              PopupMenuItem(
                value: ChatMenuAction.setAvatar,
                child: Text(strings.addAvatar),
              ),
            PopupMenuItem(
              value: ChatMenuAction.deleteChat,
              child: Text(strings.deleteDialog),
            ),
          ],
        ),
      ],
    );
  }
}
