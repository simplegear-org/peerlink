import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('core runtime inventory is explicit', () {
    final actual =
        Directory('lib/core/runtime')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .map((file) => file.uri.pathSegments.last)
            .toList()
          ..sort();

    expect(
      actual,
      equals(_approvedRuntimeFiles),
      reason:
          'New runtime files must be explicitly classified as true runtime '
          'or moved to the owning feature module.',
    );
  });

  test('migrated feature runtime paths remain forwarding exports only', () {
    final violations = <String>[];

    for (final path in _migratedFeatureRuntimeExports) {
      final file = File('lib/core/runtime/$path');
      final content = file.readAsStringSync();
      final hasExport = RegExp(
        r"^\s*export\s+'package:peerlink/features/",
        multiLine: true,
      ).hasMatch(content);
      final declaresRuntimeType = RegExp(
        r'^\s*(class|abstract\s+class|enum|mixin|typedef)\s+',
        multiLine: true,
      ).hasMatch(content);
      if (!hasExport || declaresRuntimeType) {
        violations.add(path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Feature-owned runtime compatibility files must not grow new '
          'implementations.',
    );
  });

  test('StorageService does not keep static mutable application state', () {
    final content = File(
      'lib/core/runtime/storage_service.dart',
    ).readAsStringSync();
    final violations = RegExp(
      r'^\s*static\s+(?!const\b)(?:final\s+)?[A-Za-z_<][^=;{]*\s+_\w+',
      multiLine: true,
    ).allMatches(content).map((match) => match.group(0)!.trim()).toList();

    expect(
      violations,
      isEmpty,
      reason:
          'StorageService runtime state must belong to instance lifetime, '
          'not static mutable application state.',
    );
  });

  test('StorageService does not expose call log business API', () {
    final content = File(
      'lib/core/runtime/storage_service.dart',
    ).readAsStringSync();
    final violations = <String>[
      'readCallLogs',
      'prependCallLog',
      'deleteCallLog',
    ].where(content.contains).toList();

    expect(
      violations,
      isEmpty,
      reason: 'Call log operations belong to CallLogRepository.',
    );
  });

  test('StorageService does not expose chat message paging API', () {
    final content = File(
      'lib/core/runtime/storage_service.dart',
    ).readAsStringSync();
    final violations =
        <String>[
          'loadLatestMessages',
          'loadMessagesPage',
          'loadMessagesIndex',
          'getMessageOffsetFromNewest',
          'deleteChatMessagesByIds',
          'readChatMessages',
          'writeChatMessages',
          'upsertChatMessages',
          'loadAllChatSummaries',
          'getChatSummary',
          'saveChatSummaryMap',
          'deleteChatSummaryMap',
        ].where((method) {
          return RegExp(
            r'^\s*Future<[^>]+>\s+' + method + r'\s*\(',
            multiLine: true,
          ).hasMatch(content);
        }).toList();

    expect(
      violations,
      isEmpty,
      reason: 'Chat message paging belongs to ChatRepository.',
    );
  });
}

const _approvedRuntimeFiles = [
  'account_device_event.dart',
  'account_membership_update_payload.dart',
  'account_pairing_payload.dart',
  'android_call_log_service.dart',
  'android_call_notification_service.dart',
  'app_bootstrap_coordinator.dart',
  'app_data_cleaner_service.dart',
  'app_file_logger.dart',
  'app_interaction_gate.dart',
  'app_storage_stats.dart',
  'avatar_service.dart',
  'bootstrap_servers_service.dart',
  'call_log_repository.dart',
  'chat_database.dart',
  'contact_name_resolver.dart',
  'contacts_repository.dart',
  'deep_link_service.dart',
  'diagnostic_log.dart',
  'file_read_isolate.dart',
  'initial_server_config_bootstrapper.dart',
  'ios_callkit_service.dart',
  'media_gallery_service.dart',
  'moderation_api_client.dart',
  'moderation_delivery_service.dart',
  'moderation_policy_service.dart',
  'moderation_report_models.dart',
  'moderation_report_service.dart',
  'network_config.dart',
  'network_dependencies.dart',
  'network_event.dart',
  'network_event_bus.dart',
  'network_state.dart',
  'peer_access_control_service.dart',
  'push_access_policy_sync_service.dart',
  'push_device_registration_service.dart',
  'push_server_sharing_preferences.dart',
  'push_servers_service.dart',
  'push_token_service.dart',
  'reconnect_scheduler.dart',
  'relay_servers_service.dart',
  'runtime_servers_merge_orchestrator.dart',
  'secure_storage_platform_options.dart',
  'secure_storage_wrapper.dart',
  'self_hosted_deploy_command_builder.dart',
  'self_hosted_deploy_service.dart',
  'server_availability.dart',
  'server_availability_poller.dart',
  'server_availability_provider.dart',
  'server_config_payload.dart',
  'server_health_coordinator.dart',
  'server_runtime_utils.dart',
  'server_update.dart',
  'server_update_callback_registry.dart',
  'server_update_parser.dart',
  'server_update_storage_merger.dart',
  'source_metadata.dart',
  'storage_service.dart',
  'storage_service_media.dart',
  'storage_service_migrations.dart',
  'storage_service_paths.dart',
  'terms_acceptance_service.dart',
  'turn_servers_service.dart',
];

const _migratedFeatureRuntimeExports = [
  'android_call_log_service.dart',
  'android_call_notification_service.dart',
  'avatar_service.dart',
  'call_log_repository.dart',
  'chat_database.dart',
  'contact_name_resolver.dart',
  'contacts_repository.dart',
  'ios_callkit_service.dart',
];
