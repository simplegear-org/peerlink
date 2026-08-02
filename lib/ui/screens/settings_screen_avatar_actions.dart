import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/runtime/avatar_service.dart';
import '../localization/app_strings.dart';
import 'avatar_capture_screen.dart';
import 'avatar_crop_screen.dart';

class SettingsScreenAvatarActions {
  final AvatarService avatarService;
  final bool Function() isMounted;

  const SettingsScreenAvatarActions({
    required this.avatarService,
    required this.isMounted,
  });

  Future<void> showAvatarActions(BuildContext context) async {
    final hasAvatar = (avatarService.localAvatarPath ?? '').isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: Text(sheetContext.strings.takePhoto),
                onTap: () => Navigator.of(sheetContext).pop('camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(sheetContext.strings.chooseFromGallery),
                onTap: () => Navigator.of(sheetContext).pop('gallery'),
              ),
              if (hasAvatar)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(sheetContext.strings.deleteAvatar),
                  onTap: () => Navigator.of(sheetContext).pop('delete'),
                ),
            ],
          ),
        );
      },
    );
    if (!isMounted() || action == null) {
      return;
    }
    if (action == 'camera') {
      if (!context.mounted) {
        return;
      }
      await _captureAvatar(context);
      return;
    }
    if (action == 'gallery') {
      if (!context.mounted) {
        return;
      }
      await _pickAvatarFromGallery(context);
      return;
    }
    if (action == 'delete') {
      if (!context.mounted) {
        return;
      }
      await _confirmDeleteAvatar(context);
    }
  }

  Future<void> _captureAvatar(BuildContext context) async {
    final rawBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const AvatarCaptureScreen()),
    );
    if (!isMounted() || rawBytes == null || rawBytes.isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _processAvatarBytes(
      context,
      rawBytes,
      mimeType: 'image/png',
    );
  }

  Future<void> _pickAvatarFromGallery(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (!isMounted() || result == null || result.files.isEmpty) {
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
    if (!isMounted() || bytes == null || bytes.isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _processAvatarBytes(
      context,
      bytes,
      mimeType: _mimeTypeForPath(selected.name),
    );
  }

  Future<void> _processAvatarBytes(
    BuildContext context,
    Uint8List sourceBytes, {
    required String mimeType,
  }) async {
    final croppedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => AvatarCropScreen(sourceBytes: sourceBytes),
      ),
    );
    if (!isMounted() || croppedBytes == null || croppedBytes.isEmpty) {
      return;
    }
    try {
      await avatarService.setLocalAvatar(croppedBytes, mimeType: mimeType);
      if (!isMounted() || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.avatarUpdated)));
    } catch (error) {
      if (!isMounted() || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.avatarSaveError(error))),
      );
    }
  }

  Future<void> _confirmDeleteAvatar(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.deleteAvatarTitle),
          content: Text(strings.deleteAvatarDescription),
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
      return;
    }
    await avatarService.clearLocalAvatar();
    if (!isMounted() || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.avatarDeleted)));
  }

  String _mimeTypeForPath(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
