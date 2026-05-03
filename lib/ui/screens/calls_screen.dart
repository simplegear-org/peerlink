import 'package:flutter/material.dart';

import '../../core/calls/call_log_entry.dart';
import '../../core/calls/call_models.dart';
import '../../core/node/node_facade.dart';
import '../models/chat.dart';
import '../localization/app_strings.dart';
import '../state/chat_controller.dart';
import '../state/calls_controller.dart';
import '../state/avatar_service.dart';
import '../state/presence_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'calls_screen_styles.dart';
import 'calls_screen_view.dart';

class CallsScreen extends StatefulWidget {
  final NodeFacade facade;
  final ChatController controller;
  final CallsController callsController;
  final PresenceService presenceService;
  final AvatarService avatarService;
  final int refreshVersion;

  const CallsScreen({
    super.key,
    required this.facade,
    required this.controller,
    required this.callsController,
    required this.presenceService,
    required this.avatarService,
    required this.refreshVersion,
  });

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  List<CallLogEntry> _entries = const <CallLogEntry>[];
  bool _loading = true;
  String? _callingPeerId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CallsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _load();
    }
  }

  Future<void> _load() async {
    final entries = await widget.callsController.loadEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _groupedEntries(_entries);

    return Scaffold(
      appBar: AppBar(title: Text(context.strings.calls)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? const CallsEmptyState()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: CallsScreenStyles.tileSeparatorHeight),
              itemBuilder: (context, index) {
                final item = items[index];
                final data = _tileData(item);
                return CallHistoryTile(
                  key: ValueKey('call-${item.primary.id}-${item.missedCount}'),
                  data: data,
                  onTap: () => _redial(item),
                  onLongPress: () => _showEntryActions(item),
                  onCallTap: () => _redial(item),
                  onDeleteRequested: () => _confirmDeleteEntry(item),
                );
              },
            ),
    );
  }

  CallHistoryTileData _tileData(_CallListItem item) {
    final entry = item.primary;
    return CallHistoryTileData(
      entry: entry,
      icon: _iconFor(entry),
      statusColor: _statusColor(entry.status),
      isCalling: _callingPeerId == entry.peerId,
      missedCount: item.missedCount,
      subtitle: _subtitle(item),
      timeLabel: _timeLabel(entry),
      durationLabel: _durationLabel(entry),
    );
  }

  List<_CallListItem> _groupedEntries(List<CallLogEntry> entries) {
    final items = <_CallListItem>[];
    for (final entry in entries) {
      final canMerge =
          entry.status == CallLogStatus.missed &&
          entry.direction == CallDirection.incoming &&
          items.isNotEmpty &&
          items.last.primary.status == CallLogStatus.missed &&
          items.last.primary.direction == CallDirection.incoming &&
          items.last.primary.peerId == entry.peerId;

      if (canMerge) {
        items.last.entries.add(entry);
        continue;
      }

      items.add(_CallListItem(entries: <CallLogEntry>[entry]));
    }
    return items;
  }

  Future<void> _redial(_CallListItem item) async {
    final entry = item.primary;
    if (entry.peerId.trim().isEmpty) {
      return;
    }

    setState(() {
      _callingPeerId = entry.peerId;
    });

    try {
      await widget.facade.startCall(entry.peerId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.callStartError(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (_callingPeerId == entry.peerId) {
            _callingPeerId = null;
          }
        });
      }
    }
  }

  Future<void> _showEntryActions(_CallListItem item) async {
    final action = await showModalBottomSheet<_CallEntryAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.call_rounded),
                title: Text(context.strings.callBack),
                onTap: () => Navigator.of(context).pop(_CallEntryAction.redial),
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                title: Text(context.strings.openChat),
                onTap: () =>
                    Navigator.of(context).pop(_CallEntryAction.openChat),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(context.strings.deleteFromHistory),
                onTap: () => Navigator.of(context).pop(_CallEntryAction.delete),
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
      case _CallEntryAction.redial:
        await _redial(item);
        return;
      case _CallEntryAction.openChat:
        await _openChat(item.primary);
        return;
      case _CallEntryAction.delete:
        await _deleteEntry(item);
        return;
    }
  }

  Future<void> _openChat(CallLogEntry entry) async {
    final peerId = entry.peerId.trim();
    if (peerId.isEmpty) {
      return;
    }

    await widget.controller.ensureChatLoaded(peerId);
    if (!mounted) {
      return;
    }

    final chat =
        widget.controller.chats[peerId] ??
        Chat(peerId: peerId, name: entry.contactName);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chat: chat,
          controller: widget.controller,
          presenceService: widget.presenceService,
          avatarService: widget.avatarService,
        ),
      ),
    );
  }

  Future<void> _deleteEntry(_CallListItem item) async {
    await widget.callsController.deleteEntries(item.entries);
    await _load();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          item.missedCount > 1
              ? context.strings.missedGroupDeleted
              : context.strings.callDeleted,
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteEntry(_CallListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.deleteEntryTitle),
          content: Text(
            item.missedCount > 1
                ? strings.deleteMissedGroupMessage
                : strings.deleteCallMessage,
          ),
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
    await _deleteEntry(item);
    return true;
  }

  IconData _iconFor(CallLogEntry entry) {
    if (entry.direction == CallDirection.incoming) {
      switch (entry.status) {
        case CallLogStatus.completed:
          return Icons.call_received_rounded;
        case CallLogStatus.missed:
          return Icons.call_missed_rounded;
        case CallLogStatus.declined:
          return Icons.call_end_rounded;
        case CallLogStatus.canceled:
          return Icons.call_end_rounded;
        case CallLogStatus.busy:
          return Icons.phone_disabled_rounded;
        case CallLogStatus.failed:
          return Icons.error_outline_rounded;
      }
    }
    switch (entry.status) {
      case CallLogStatus.completed:
        return Icons.call_made_rounded;
      case CallLogStatus.missed:
        return Icons.phone_missed_rounded;
      case CallLogStatus.declined:
        return Icons.call_end_rounded;
      case CallLogStatus.canceled:
        return Icons.cancel_outlined;
      case CallLogStatus.busy:
        return Icons.phone_disabled_rounded;
      case CallLogStatus.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color _statusColor(CallLogStatus status) {
    switch (status) {
      case CallLogStatus.completed:
        return AppTheme.pine;
      case CallLogStatus.missed:
        return Colors.orange.shade700;
      case CallLogStatus.declined:
      case CallLogStatus.canceled:
      case CallLogStatus.failed:
        return Colors.red.shade400;
      case CallLogStatus.busy:
        return Colors.blueGrey.shade600;
    }
  }

  String _subtitle(_CallListItem item) {
    final entry = item.primary;
    final direction = entry.direction == CallDirection.incoming
        ? context.strings.incoming
        : context.strings.outgoing;
    if (item.missedCount > 1) {
      return '$direction • ${context.strings.missedInARow(item.missedCount)}';
    }
    return '$direction • ${_statusLabel(entry.status)}';
  }

  String _statusLabel(CallLogStatus status) {
    switch (status) {
      case CallLogStatus.completed:
        return context.strings.ended;
      case CallLogStatus.missed:
        return context.strings.missed;
      case CallLogStatus.declined:
        return context.strings.rejected;
      case CallLogStatus.canceled:
        return context.strings.canceled;
      case CallLogStatus.busy:
        return context.strings.busy;
      case CallLogStatus.failed:
        return context.strings.callError;
    }
  }

  String _timeLabel(CallLogEntry entry) {
    final value = entry.endedAt;
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month $hour:$minute';
  }

  String _durationLabel(CallLogEntry entry) {
    final seconds = entry.durationSeconds;
    if (seconds <= 0) {
      return '00:00';
    }
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }
}

class _CallListItem {
  final List<CallLogEntry> entries;

  _CallListItem({required this.entries});

  CallLogEntry get primary => entries.first;
  int get missedCount => entries.length;
}

enum _CallEntryAction { redial, openChat, delete }
