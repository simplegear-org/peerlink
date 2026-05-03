import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/contact.dart';
import '../state/chat_controller.dart';
import '../state/contacts_controller.dart';
import '../state/avatar_service.dart';
import '../state/presence_service.dart';
import '../state/settings_controller.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/server_config_import_dialog.dart';
import '../widgets/compact_card_tile_styles.dart';
import '../widgets/contact_tile.dart';
import '../widgets/peer_avatar.dart';
import 'chat_screen_helpers.dart';
import 'chat_screen.dart';
import 'contacts_screen_view.dart';
import 'qr_scan_screen.dart';

enum _ContactAction { rename }

class ContactsScreen extends StatefulWidget {
  final ChatController controller;
  final ContactsController contactsController;
  final SettingsController settingsController;
  final PresenceService presenceService;
  final AvatarService avatarService;

  const ContactsScreen({
    super.key,
    required this.controller,
    required this.contactsController,
    required this.settingsController,
    required this.presenceService,
    required this.avatarService,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final ContactsController controller;
  StreamSubscription<String>? _presenceSubscription;
  StreamSubscription<String>? _avatarSubscription;
  StreamSubscription<List<String>>? _discoverySubscription;
  Timer? _presenceRefreshTimer;

  @override
  void initState() {
    super.initState();
    developer.log('[ui] ContactsScreen.initState');
    controller = widget.contactsController;
    controller.contacts
      ..clear()
      ..addAll(controller.loadContacts());
    _discoverySubscription = widget.controller.discoveredPeersStream.listen((
      peers,
    ) {
      unawaited(_applyDiscoveredPeers(peers));
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

  void addContactDialog() {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();

    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.newContact),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: strings.name),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: idCtrl,
                      decoration: InputDecoration(labelText: strings.peerId),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    onPressed: () async {
                      final result = await Navigator.of(dialogContext).push(
                        MaterialPageRoute(builder: (_) => const QrScanScreen()),
                      );
                      if (!mounted) {
                        return;
                      }
                      if (result is String && result.isNotEmpty) {
                        final handled = await _tryImportServerConfigFromQr(
                          result,
                        );
                        if (handled) {
                          return;
                        }
                        final inviteHandled = await _tryImportInviteFromQr(
                          result,
                        );
                        if (inviteHandled) {
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          return;
                        }
                        final parsedPeerId = widget.settingsController
                            .extractPeerIdFromUserQr(result);
                        idCtrl.text =
                            (parsedPeerId != null && parsedPeerId.isNotEmpty)
                            ? parsedPeerId
                            : result;
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () {
                unawaited(
                  controller.addContact(
                    Contact(peerId: idCtrl.text, name: nameCtrl.text),
                  ),
                );
                setState(() {});
                Navigator.pop(dialogContext);
              },
              child: Text(strings.add),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    developer.log(
      '[ui] ContactsScreen.build contacts=${controller.contacts.length}',
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.contacts),
        actions: [
          TextButton(onPressed: _showInviteSheet, child: Text(strings.invite)),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: addContactDialog,
        child: const Icon(Icons.add),
      ),
      body: CustomScrollView(
        slivers: [
          if (controller.contacts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: const ContactsEmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final contact = controller.contacts[index];

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == controller.contacts.length - 1
                          ? 0
                          : CompactCardTileStyles.tileSeparatorHeight,
                    ),
                    child: ContactTile(
                      key: ValueKey('contact-${contact.peerId}'),
                      contact: contact,
                      avatar: PeerAvatar(
                        peerId: contact.peerId,
                        displayName: contact.name.trim().isNotEmpty
                            ? contact.name.trim()
                            : contact.shortId(),
                        avatarService: widget.avatarService,
                        size: CompactCardTileStyles.avatarSize,
                      ),
                      lastSeenText: _contactLastSeenText(contact.peerId),
                      onLongPress: () {
                        unawaited(_showContactMenu(contact));
                      },
                      onTap: () {
                        final chat = widget.controller.openChat(
                          contact.peerId,
                          contact.name,
                        );
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
                        ).then((_) => setState(() {}));
                      },
                      onDeleteRequested: () =>
                          _confirmAndRemoveContact(contact),
                    ),
                  );
                }, childCount: controller.contacts.length),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel();
    _avatarSubscription?.cancel();
    _discoverySubscription?.cancel();
    _presenceRefreshTimer?.cancel();
    super.dispose();
  }

  String _contactLastSeenText(String peerId) {
    final chat = widget.controller.chats[peerId];
    DateTime? fallbackLastSeenAt;
    if (chat != null) {
      for (var i = chat.messages.length - 1; i >= 0; i--) {
        final message = chat.messages[i];
        if (message.incoming) {
          fallbackLastSeenAt = message.timestamp;
          break;
        }
      }
      fallbackLastSeenAt ??= chat.previewMessage?.incoming == true
          ? chat.previewMessage!.timestamp
          : null;
    }
    return ChatScreenHelpers.lastSeenLabel(
      isPeerOnline: widget.presenceService.isPeerOnline(peerId),
      lastSeenAt: widget.presenceService.peerLastSeenAt(peerId),
      fallbackLastSeenAt: fallbackLastSeenAt,
      strings: context.strings,
    );
  }

  Future<void> _showContactMenu(Contact contact) async {
    final action = await showModalBottomSheet<_ContactAction>(
      context: context,
      useRootNavigator: false,
      builder: (sheetContext) {
        final strings = sheetContext.strings;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(strings.renameContact),
                onTap: () {
                  Navigator.pop(sheetContext, _ContactAction.rename);
                },
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ContactAction.rename:
        await _showRenameContactDialog(contact);
    }
  }

  Future<void> _showRenameContactDialog(Contact contact) async {
    final initialName = contact.name.trim();
    final nameCtrl = TextEditingController(
      text: initialName == contact.peerId ? '' : initialName,
    );

    try {
      final nextName = await showDialog<String>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) {
          final strings = dialogContext.strings;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final canSave = nameCtrl.text.trim().isNotEmpty;
              return AlertDialog(
                title: Text(strings.renameContact),
                content: TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(labelText: strings.contactName),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) {
                    final value = nameCtrl.text.trim();
                    if (value.isNotEmpty) {
                      Navigator.pop(dialogContext, value);
                    }
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(strings.cancel),
                  ),
                  FilledButton(
                    onPressed: canSave
                        ? () {
                            Navigator.pop(dialogContext, nameCtrl.text.trim());
                          }
                        : null,
                    child: Text(strings.save),
                  ),
                ],
              );
            },
          );
        },
      );

      if (nextName == null || nextName.trim().isEmpty) {
        return;
      }
      final normalizedName = nextName.trim();
      await controller.renameContact(contact.peerId, normalizedName);
      await widget.controller.addOrUpdateContact(
        peerId: contact.peerId,
        name: normalizedName,
      );
      if (!mounted) {
        return;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.contactRenamed(normalizedName))),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  Future<void> _showInviteSheet() async {
    await widget.settingsController.initialize();
    if (!mounted) {
      return;
    }
    final inviteDeepLink = widget.settingsController.exportInviteDeepLink();
    final inviteShareLink = widget.settingsController.exportInviteShareLink();
    final peerId = widget.settingsController.peerId;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      clipBehavior: Clip.none,
      builder: (sheetContext) {
        final strings = sheetContext.strings;
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.stroke),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.inviteTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.inviteDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: QrImageView(data: inviteDeepLink, size: 220),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    strings.peerId,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    peerId,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        unawaited(
                          SharePlus.instance.share(
                            ShareParams(
                              text: strings.inviteShareText(
                                peerId,
                                inviteShareLink,
                              ),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.ios_share_rounded),
                      label: Text(strings.sharePeer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _tryImportInviteFromQr(String raw) async {
    try {
      final settingsController = widget.settingsController;
      await settingsController.initialize();
      final invite = settingsController.parseInviteDeepLink(raw);
      if (invite.peerId == settingsController.peerId) {
        return true;
      }
      await settingsController.importServerConfigPayload(
        invite.serverConfig,
        mode: ServerConfigImportMode.merge,
      );
      final displayName = invite.displayName?.trim().isNotEmpty == true
          ? invite.displayName!.trim()
          : invite.peerId;
      await controller.addOrUpdateContact(
        Contact(peerId: invite.peerId, name: displayName),
      );
      if (!mounted) {
        return true;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.contactAdded(displayName))),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryImportServerConfigFromQr(String raw) async {
    try {
      final settingsController = widget.settingsController;
      await settingsController.initialize();
      final payload = settingsController.parseServerConfigQrPayload(raw);
      if (!mounted) {
        return true;
      }
      final mode = await showServerConfigImportDialog(
        context,
        controller: settingsController,
        payload: payload,
      );
      if (mode == null) {
        return true;
      }
      await settingsController.importServerConfigPayload(payload, mode: mode);
      if (!mounted) {
        return true;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == ServerConfigImportMode.replace
                ? context.strings.serverSettingsReplaced
                : context.strings.serverSettingsMerged,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyDiscoveredPeers(List<String> peers) async {
    var changed = false;
    for (final peerId in peers) {
      if (await controller.addDiscoveredPeer(peerId)) {
        changed = true;
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<void> _removeContact(String peerId) async {
    await controller.removeContact(peerId);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<bool> _confirmAndRemoveContact(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.deleteContactTitle),
          content: Text(strings.deleteContactContent(contact.name)),
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
    await _removeContact(contact.peerId);
    return true;
  }
}
