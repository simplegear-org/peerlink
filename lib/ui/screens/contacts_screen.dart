import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../state/chat_controller.dart';
import '../state/contacts_controller.dart';
import '../state/avatar_service.dart';
import '../state/presence_service.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/server_config_import_dialog.dart';
import '../widgets/contact_tile.dart';
import '../widgets/peer_avatar.dart';
import 'chat_screen_helpers.dart';
import 'chat_screen.dart';
import 'contacts_screen_view.dart';
import 'qr_scan_screen.dart';

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
  StreamSubscription<String>? _statusSubscription;
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
    _statusSubscription =
        widget.controller.connectionStatusStream.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
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
        return AlertDialog(
          title: const Text('Новый контакт'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Имя'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: idCtrl,
                      decoration: const InputDecoration(labelText: 'Peer ID'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    onPressed: () async {
                      final result = await Navigator.of(dialogContext).push(
                        MaterialPageRoute(
                          builder: (_) => const QrScanScreen(),
                        ),
                      );
                      if (!mounted) {
                        return;
                      }
                      if (result is String && result.isNotEmpty) {
                        final handled = await _tryImportServerConfigFromQr(result);
                        if (handled) {
                          return;
                        }
                        final parsedPeerId =
                            widget.settingsController.extractPeerIdFromUserQr(result);
                        idCtrl.text = (parsedPeerId != null && parsedPeerId.isNotEmpty)
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
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                unawaited(controller.addContact(
                  Contact(
                    peerId: idCtrl.text,
                    name: nameCtrl.text,
                  ),
                ));
                setState(() {});
                Navigator.pop(dialogContext);
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    developer.log('[ui] ContactsScreen.build contacts=${controller.contacts.length}');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Контакты'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: addContactDialog,
        child: const Icon(Icons.add),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: const ContactsScreenHeader(),
          ),
          if (controller.contacts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: const ContactsEmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final contact = controller.contacts[index];
                    final status = widget.controller.connectionStatus(contact.peerId);
                    final icon = _statusIcon(status);

                    return ContactTile(
                      key: ValueKey('contact-${contact.peerId}'),
                      contact: contact,
                      statusIcon: icon,
                      avatar: PeerAvatar(
                        peerId: contact.peerId,
                        displayName: contact.name,
                        avatarService: widget.avatarService,
                        size: 50,
                      ),
                      lastSeenText: _contactLastSeenText(contact.peerId),
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
                      onDeleteRequested: () => _confirmAndRemoveContact(contact),
                    );
                  },
                  childCount: controller.contacts.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusIcon(ChatConnectionStatus status) {
    final iconData = status == ChatConnectionStatus.connected
        ? Icons.link
        : status == ChatConnectionStatus.connecting
            ? Icons.sync
            : status == ChatConnectionStatus.error
                ? Icons.error_outline
                : Icons.link_off;
    final color = status == ChatConnectionStatus.connected
        ? AppTheme.pine
        : status == ChatConnectionStatus.connecting
            ? AppTheme.accent
            : status == ChatConnectionStatus.error
                ? Colors.red.shade400
                : AppTheme.muted;
    return Icon(iconData, color: color);
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
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
    );
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
                ? 'Серверные параметры заменены из QR'
                : 'Серверные параметры объединены с данными из QR',
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
        return AlertDialog(
          title: const Text('Удалить контакт?'),
          content: Text('Контакт "${contact.name}" будет удален.'),
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
    await _removeContact(contact.peerId);
    return true;
  }
}
