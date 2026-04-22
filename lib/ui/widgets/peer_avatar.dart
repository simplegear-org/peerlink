import 'dart:io';

import 'package:flutter/material.dart';

import '../state/avatar_service.dart';
import '../theme/app_theme.dart';

class PeerAvatar extends StatelessWidget {
  final String peerId;
  final String displayName;
  final AvatarService avatarService;
  final String? imagePath;
  final double size;
  final bool showInitialWhenNoAvatar;
  final bool transparentWhenNoAvatar;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const PeerAvatar({
    super.key,
    required this.peerId,
    required this.displayName,
    required this.avatarService,
    this.imagePath,
    this.size = 48,
    this.showInitialWhenNoAvatar = true,
    this.transparentWhenNoAvatar = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final path = imagePath ?? avatarService.avatarPathForPeer(peerId);
    final theme = Theme.of(context);
    final bg = backgroundColor ?? AppTheme.pineSoft;
    final fg = foregroundColor ?? AppTheme.pine;

    if (path != null && path.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallback(theme, bg, fg),
        ),
      );
    }

    return _fallback(theme, bg, fg);
  }

  Widget _fallback(ThemeData theme, Color bg, Color fg) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: transparentWhenNoAvatar ? Colors.transparent : bg,
        border: Border.all(color: AppTheme.stroke),
      ),
      alignment: Alignment.center,
      child: !showInitialWhenNoAvatar
          ? null
          : Text(
              _initial(displayName),
              style: theme.textTheme.titleMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  String _initial(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed.substring(0, 1).toUpperCase();
  }
}
