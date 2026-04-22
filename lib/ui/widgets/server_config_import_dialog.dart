import 'package:flutter/material.dart';

import '../state/settings_controller.dart';
import '../../core/runtime/server_config_payload.dart';

Future<ServerConfigImportMode?> showServerConfigImportDialog(
  BuildContext context, {
  required SettingsController controller,
  required ServerConfigPayload payload,
}) {
  final preview = controller.previewImport(payload);
  return showDialog<ServerConfigImportMode>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Импорт конфигурации'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'В QR найдено: bootstrap ${preview.bootstrapTotal}, relay ${preview.relayTotal}, TURN ${preview.turnTotal}.',
            ),
            const SizedBox(height: 12),
            Text(
              'При объединении будет добавлено: bootstrap ${preview.bootstrapNew}, relay ${preview.relayNew}, TURN ${preview.turnNew}.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Заменить: текущие списки серверов будут полностью перезаписаны.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              ServerConfigImportMode.merge,
            ),
            child: const Text('Объединить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              ServerConfigImportMode.replace,
            ),
            child: const Text('Заменить'),
          ),
        ],
      );
    },
  );
}
