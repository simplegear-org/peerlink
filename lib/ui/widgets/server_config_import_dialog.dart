import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
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
      final strings = dialogContext.strings;
      return AlertDialog(
        title: Text(strings.importConfig),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.importConfigFound(
                bootstrap: preview.bootstrapTotal,
                relay: preview.relayTotal,
                turn: preview.turnTotal,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              strings.importConfigMergeAdds(
                bootstrap: preview.bootstrapNew,
                relay: preview.relayNew,
                turn: preview.turnNew,
              ),
            ),
            const SizedBox(height: 12),
            Text(strings.importConfigReplaceWarning),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, ServerConfigImportMode.merge),
            child: Text(strings.merge),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, ServerConfigImportMode.replace),
            child: Text(strings.replace),
          ),
        ],
      );
    },
  );
}
