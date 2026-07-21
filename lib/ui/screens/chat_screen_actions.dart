import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_strings.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';
import 'avatar_crop_screen.dart';

enum ChatMessageAction {
  addContact,
  saveMessage,
  saveToGallery,
  retrySend,
  deleteLocal,
  deleteEveryone,
}

enum ChatAttachAction { gallery, paste, file, location }

enum ChatMenuAction {
  addContact,
  addParticipants,
  removeParticipants,
  renameGroup,
  setAvatar,
  deleteChat,
}

class ChatScreenActions {
  const ChatScreenActions();

  Future<void> confirmDeleteMessage({
    required BuildContext context,
    required ChatController controller,
    required Chat chat,
    required Message message,
    required String Function(String peerId) shortPeerId,
    required Future<void> Function(String peerId) showAddContactDialog,
    required Future<void> Function(Message message) saveMediaToGallery,
    required Future<void> Function(String peerId, String messageId)
    removeMessage,
  }) async {
    if (message.isPendingOutgoingTransfer) {
      final shouldCancel = await _showPendingTransferSheet(context: context);
      if (shouldCancel == true) {
        await controller.cancelFileTransfer(chat.peerId, message.id);
      }
      return;
    }

    final senderPeerId = (message.senderPeerId ?? message.peerId).trim();
    final canAddContact =
        message.incoming &&
        senderPeerId.isNotEmpty &&
        controller.contactNameForPeer(senderPeerId) == null;
    final canSaveMessage = message.kind == MessageKind.text;
    final canSaveToGallery =
        message.kind == MessageKind.file && message.isMedia;
    final canRetry =
        !message.incoming && message.status == MessageStatus.failed;
    final action = await _showMessageActionSheet(
      context: context,
      canAddContact: canAddContact,
      canSaveMessage: canSaveMessage,
      canSaveToGallery: canSaveToGallery,
      canRetry: canRetry,
      canDeleteEverywhere: !message.incoming,
    );
    if (action == null) {
      return;
    }

    if (action == ChatMessageAction.addContact) {
      await showAddContactDialog(senderPeerId);
      return;
    }

    if (action == ChatMessageAction.saveMessage) {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.messageCopied)));
      return;
    }

    if (action == ChatMessageAction.saveToGallery) {
      await saveMediaToGallery(message);
      return;
    }

    if (action == ChatMessageAction.retrySend) {
      await controller.retryMessage(chat.peerId, message.id);
      return;
    }

    await removeMessage(chat.peerId, message.id);
    if (action == ChatMessageAction.deleteEveryone) {
      await controller.requestDeleteForEveryone(chat.peerId, message.id);
    }
  }

  Future<void> showAddContactDialog({
    required BuildContext context,
    required ChatController controller,
    required String peerId,
  }) async {
    final nameCtrl = TextEditingController();
    final enteredName = await showDialog<String>(
      context: context,
      builder: (context) {
        final strings = context.strings;
        return AlertDialog(
          title: Text(strings.addContact),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: strings.contactName,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(nameCtrl.text.trim()),
              child: Text(strings.add),
            ),
          ],
        );
      },
    );

    final name = enteredName?.trim() ?? '';
    if (name.isEmpty) {
      return;
    }
    await controller.addOrUpdateContact(peerId: peerId, name: name);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.contactAdded(name))));
  }

  Future<void> showAddParticipantsSheet({
    required BuildContext context,
    required ChatController controller,
    required Chat chat,
  }) async {
    final available = controller
        .getContacts()
        .where((contact) => !chat.memberPeerIds.contains(contact.peerId))
        .toList(growable: false);
    if (available.isEmpty) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.noContactsToAdd)));
      return;
    }

    final selectedPeerIds = <String>{};
    final toAdd = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.strings.addParticipants,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 280,
                      child: ListView.builder(
                        itemCount: available.length,
                        itemBuilder: (context, index) {
                          final contact = available[index];
                          final selected = selectedPeerIds.contains(
                            contact.peerId,
                          );
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(context.strings.cancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: selectedPeerIds.isEmpty
                                ? null
                                : () => Navigator.pop(
                                    context,
                                    selectedPeerIds.toList(growable: false),
                                  ),
                            child: Text(context.strings.add),
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

    if (toAdd == null || toAdd.isEmpty) {
      return;
    }
    await controller.addGroupParticipants(
      groupId: chat.peerId,
      participantPeerIds: toAdd,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.participantsAdded)));
  }

  Future<void> showRenameGroupDialog({
    required BuildContext context,
    required ChatController controller,
    required Chat chat,
  }) async {
    final ctrl = TextEditingController(text: chat.name);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) {
        final strings = context.strings;
        return AlertDialog(
          title: Text(strings.renameChat),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: strings.chatNameLabel,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
              child: Text(strings.save),
            ),
          ],
        );
      },
    );

    final name = nextName?.trim() ?? '';
    if (name.isEmpty || name == chat.name) {
      return;
    }
    await controller.renameGroupChat(groupId: chat.peerId, newName: name);
  }

  Future<void> showRemoveParticipantsSheet({
    required BuildContext context,
    required ChatController controller,
    required Chat chat,
    required String Function(String peerId) shortPeerId,
  }) async {
    final removablePeerIds = chat.memberPeerIds
        .where(
          (peerId) =>
              peerId != controller.facade.peerId && peerId != chat.ownerPeerId,
        )
        .toList(growable: false);
    if (removablePeerIds.isEmpty) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.noParticipantsToRemove)),
      );
      return;
    }

    final selected = <String>{};
    final toRemove = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.strings.removeParticipants,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 280,
                      child: ListView.builder(
                        itemCount: removablePeerIds.length,
                        itemBuilder: (context, index) {
                          final peerId = removablePeerIds[index];
                          final name =
                              controller.contactNameForPeer(peerId) ??
                              shortPeerId(peerId);
                          final checked = selected.contains(peerId);
                          return CheckboxListTile(
                            value: checked,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(name),
                            subtitle: Text(shortPeerId(peerId)),
                            onChanged: (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selected.add(peerId);
                                } else {
                                  selected.remove(peerId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(context.strings.cancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(
                                    context,
                                    selected.toList(growable: false),
                                  ),
                            child: Text(context.strings.delete),
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

    if (toRemove == null || toRemove.isEmpty) {
      return;
    }
    await controller.removeGroupParticipants(
      groupId: chat.peerId,
      participantPeerIds: toRemove,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.strings.participantsRemoved)),
    );
  }

  Future<void> pickAndSetGroupAvatar({
    required BuildContext context,
    required ChatController controller,
    required String groupId,
    required String selectedFileNameFallback,
    required VoidCallback refresh,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (!context.mounted || result == null || result.files.isEmpty) {
      return;
    }

    final selected = result.files.first;
    Uint8List? bytes = selected.bytes;
    if (bytes == null || bytes.isEmpty) {
      final path = selected.path;
      if (path != null && path.isNotEmpty) {
        bytes = await File(path).readAsBytes();
      }
    }
    if (!context.mounted || bytes == null || bytes.isEmpty) {
      return;
    }

    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => AvatarCropScreen(sourceBytes: bytes!)),
    );
    if (!context.mounted || cropped == null || cropped.isEmpty) {
      return;
    }

    try {
      await controller.setGroupAvatar(
        groupId: groupId,
        bytes: cropped,
        mimeType: _mimeTypeForPath(selected.name, selectedFileNameFallback),
      );
      if (!context.mounted) {
        return;
      }
      refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.chatAvatarUpdated)),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.chatAvatarUpdateError(error))),
      );
    }
  }

  Future<void> confirmDeleteChat({
    required BuildContext context,
    required ChatController controller,
    required Chat chat,
    required bool isGroupOwner,
  }) async {
    final shouldDelete = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final strings = context.strings;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.deleteDialog, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  chat.isGroup
                      ? (isGroupOwner
                            ? strings.deleteGroupChatContent(chat.name)
                            : strings.deleteGroupChatLocalContent(chat.name))
                      : strings.deleteDialogDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_forever_rounded),
                  title: Text(strings.deleteDialog),
                  onTap: () => Navigator.of(context).pop(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.close_rounded),
                  title: Text(strings.cancel),
                  onTap: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }
    await controller.deleteChat(chat.peerId);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<ChatAttachAction?> showAttachMenu({required BuildContext context}) {
    return showModalBottomSheet<ChatAttachAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final strings = context.strings;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(strings.gallery),
                  onTap: () {
                    Navigator.of(context).pop(ChatAttachAction.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.content_paste_rounded),
                  title: Text(strings.paste),
                  onTap: () {
                    Navigator.of(context).pop(ChatAttachAction.paste);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.attach_file_rounded),
                  title: Text(strings.file),
                  onTap: () {
                    Navigator.of(context).pop(ChatAttachAction.file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(strings.location),
                  onTap: () {
                    Navigator.of(context).pop(ChatAttachAction.location);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: Text(strings.cancel),
                  onTap: () {
                    Navigator.of(context).pop(null);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showPendingTransferSheet({required BuildContext context}) {
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final strings = context.strings;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.cancelSending, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  strings.cancelSendingDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cancel_outlined),
                  title: Text(strings.cancelSending),
                  onTap: () => Navigator.of(context).pop(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.close_rounded),
                  title: Text(strings.cancel),
                  onTap: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<ChatMessageAction?> _showMessageActionSheet({
    required BuildContext context,
    required bool canAddContact,
    required bool canSaveMessage,
    required bool canSaveToGallery,
    required bool canRetry,
    required bool canDeleteEverywhere,
  }) {
    return showModalBottomSheet<ChatMessageAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final strings = context.strings;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canAddContact)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_add_alt_1_rounded),
                    title: Text(strings.addContact),
                    onTap: () {
                      Navigator.of(context).pop(ChatMessageAction.addContact);
                    },
                  ),
                if (canSaveMessage)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.content_copy_rounded),
                    title: Text(strings.saveMessage),
                    onTap: () {
                      Navigator.of(context).pop(ChatMessageAction.saveMessage);
                    },
                  ),
                if (canSaveToGallery)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.save_alt_rounded),
                    title: Text(strings.saveToGallery),
                    onTap: () {
                      Navigator.of(
                        context,
                      ).pop(ChatMessageAction.saveToGallery);
                    },
                  ),
                if (canRetry)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.refresh_rounded),
                    title: Text(strings.resend),
                    onTap: () {
                      Navigator.of(context).pop(ChatMessageAction.retrySend);
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(strings.deleteForMe),
                  onTap: () {
                    Navigator.of(context).pop(ChatMessageAction.deleteLocal);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_forever_rounded),
                  title: Text(strings.deleteForEveryone),
                  enabled: canDeleteEverywhere,
                  subtitle: canDeleteEverywhere
                      ? null
                      : Text(strings.onlyAuthorCanDeleteForPeer),
                  onTap: canDeleteEverywhere
                      ? () {
                          Navigator.of(
                            context,
                          ).pop(ChatMessageAction.deleteEveryone);
                        }
                      : null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.close_rounded),
                  title: Text(strings.cancel),
                  onTap: () => Navigator.of(context).pop(null),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _mimeTypeForPath(String fileName, String fallbackName) {
    final lower = (fileName.isNotEmpty ? fileName : fallbackName).toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
