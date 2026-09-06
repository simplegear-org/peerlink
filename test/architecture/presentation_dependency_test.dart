import 'dart:io';

import 'package:test/test.dart';

import 'architecture_test_utils.dart';

void main() {
  test(
    'presentation/state code does not instantiate infrastructure services',
    () {
      final sources = dartSourcesUnder(const [
        'lib/ui/screens',
        'lib/ui/state',
      ]);

      final violations = constructorCallViolations(sources, const [
        'StorageService',
        'ContactsRepository',
        'PeerAccessControlService',
        'ServerHealthCoordinator',
        'AppDataCleanerService',
        'PushTokenService',
        'TermsAcceptanceService',
        'NetworkDependencies',
        'FirebaseMessagingService',
        'HttpRelayClient',
        'PushApiClient',
        'ModerationApiClient',
        'BootstrapSignalingService',
        'MultiBootstrapSignalingService',
        'TransportManager',
        'TurnAllocator',
        'WebRtcTransport',
      ]);

      expect(
        violations,
        isEmpty,
        reason:
            'UI presentation/state must receive infrastructure through app '
            'composition or narrow injected APIs.',
      );
    },
  );

  test('SettingsController receives composed dependencies', () {
    final source = dartSourcesUnder(const ['lib/ui/state']).singleWhere(
      (source) => source.path == 'lib/ui/state/settings_controller.dart',
    );

    final violations = constructorCallViolations(
      [source],
      const [
        'ContactsRepository',
        'PeerAccessControlService',
        'ServerHealthCoordinator',
        'AppDataCleanerService',
        'PushTokenService',
        'TermsAcceptanceService',
        'SettingsPairingStateRepository',
        'SettingsPairingStateService',
        'SettingsPairingFlowService',
        'SettingsReadModelService',
        'SettingsServerConfigService',
        'SettingsStorageMaintenanceService',
        'SettingsAccountMembershipService',
      ],
    );

    expect(
      violations,
      isEmpty,
      reason:
          'SettingsController must not assemble infrastructure or application '
          'services inside presentation state.',
    );
  });

  test('SettingsController depends on narrow node APIs', () {
    final source = dartSourcesUnder(const ['lib/ui/state']).singleWhere(
      (source) => source.path == 'lib/ui/state/settings_controller.dart',
    );

    final violations = source
        .imports()
        .where(
          (import) =>
              import.resolvePeerlinkPath() == 'lib/core/node/node_facade.dart',
        )
        .map((import) => import.location)
        .toList(growable: false);

    expect(
      violations,
      isEmpty,
      reason:
          'SettingsController should receive identity, network, and messaging '
          'capabilities instead of unrestricted NodeFacade.',
    );
  });

  test('ChatController depends on ChatRuntimeApi instead of NodeFacade', () {
    final source = dartSourcesUnder(const ['lib/ui/state']).singleWhere(
      (source) => source.path == 'lib/ui/state/chat_controller.dart',
    );

    final violations = source
        .imports()
        .where(
          (import) =>
              import.resolvePeerlinkPath() == 'lib/core/node/node_facade.dart',
        )
        .map((import) => import.location)
        .toList(growable: false);

    expect(
      violations,
      isEmpty,
      reason:
          'ChatController should receive ChatRuntimeApi instead of unrestricted '
          'NodeFacade.',
    );
  });

  test('ChatController does not compose migrated chat application services', () {
    final source = dartSourcesUnder(const ['lib/ui/state']).singleWhere(
      (source) => source.path == 'lib/ui/state/chat_controller.dart',
    );

    final violations = constructorCallViolations(
      [source],
      const [
        'ChatCleanupCoordinator',
        'ChatControllerLifecycleService',
        'ChatDirectMediaCryptoService',
        'ChatDirectLifecycleService',
        'ChatFileProgressCoordinator',
        'ChatFileTransferCoordinator',
        'ChatGroupCryptoCoordinator',
        'ChatGroupInboundCoordinator',
        'ChatGroupOutboundCoordinator',
        'ChatHistoryLoadCoordinator',
        'ChatIncomingMediaRestoreCoordinator',
        'ChatMediaRestoreService',
        'ChatMediaThumbnailService',
        'ChatMessageMutationService',
        'ChatMessageSendCoordinator',
        'ChatInboundSubscriptionCoordinator',
        'ChatOutgoingRelayMediaResumeService',
        'ChatReceiptService',
        'ChatReplyMetadataResolver',
        'RelayMediaRetryCoordinator',
      ],
    );

    expect(
      violations,
      isEmpty,
      reason:
          'ChatController must receive migrated chat application services from '
          'app composition instead of constructing them in presentation state.',
    );
  });

  test('migrated settings application paths remain forwarding exports', () {
    final violations = <String>[];

    for (final path in _migratedSettingsStateExports) {
      final file = File('lib/ui/state/$path');
      final content = file.readAsStringSync();
      final hasExport = RegExp(
        r"^\s*export\s+'package:peerlink/features/settings/application/",
        multiLine: true,
      ).hasMatch(content);
      final declaresType = RegExp(
        r'^\s*(class|abstract\s+class|enum|mixin|typedef)\s+',
        multiLine: true,
      ).hasMatch(content);
      if (!hasExport || declaresType) {
        violations.add(path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Migrated settings application files under ui/state must stay as '
          'temporary compatibility exports only.',
    );
  });

  test('migrated call screen depends on CallsApi instead of NodeFacade', () {
    final sources = dartSourcesUnder(const ['lib/ui/screens']).where(
      (source) => {
        'lib/ui/screens/call_screen.dart',
        'lib/ui/screens/call_screen_view.dart',
      }.contains(source.path),
    );
    final violations = <String>[];
    for (final source in sources) {
      for (final import in source.imports()) {
        final resolved = import.resolvePeerlinkPath();
        if (resolved == 'lib/core/node/node_facade.dart') {
          violations.add(import.location);
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'The active call presentation surface should depend on CallsApi, '
          'not unrestricted NodeFacade.',
    );
  });

  test(
    'AccountRestrictedScreen depends on ModerationApi instead of NodeFacade',
    () {
      final source = dartSourcesUnder(const ['lib/ui/screens']).singleWhere(
        (source) =>
            source.path == 'lib/ui/screens/account_restricted_screen.dart',
      );

      final violations = source
          .imports()
          .where(
            (import) =>
                import.resolvePeerlinkPath() ==
                'lib/core/node/node_facade.dart',
          )
          .map((import) => import.location)
          .toList(growable: false);

      expect(
        violations,
        isEmpty,
        reason:
            'AccountRestrictedScreen submits moderation appeals only and should '
            'depend on ModerationApi.',
      );
    },
  );

  test('PresenceService depends on PresenceApi instead of NodeFacade', () {
    final source = dartSourcesUnder(const ['lib/ui/state']).singleWhere(
      (source) => source.path == 'lib/ui/state/presence_service.dart',
    );

    final violations = source
        .imports()
        .where(
          (import) =>
              import.resolvePeerlinkPath() == 'lib/core/node/node_facade.dart',
        )
        .map((import) => import.location)
        .toList(growable: false);

    expect(
      violations,
      isEmpty,
      reason: 'PresenceService needs only the presence stream capability.',
    );
  });

  test('AppRestrictionController depends on narrow node APIs', () {
    final source = dartSourcesUnder(const ['lib/ui/state']).singleWhere(
      (source) => source.path == 'lib/ui/state/app_restriction_controller.dart',
    );

    final violations = source
        .imports()
        .where(
          (import) =>
              import.resolvePeerlinkPath() == 'lib/core/node/node_facade.dart',
        )
        .map((import) => import.location)
        .toList(growable: false);

    expect(
      violations,
      isEmpty,
      reason:
          'AppRestrictionController needs identity, moderation, and calls '
          'capabilities, not unrestricted NodeFacade.',
    );
  });
}

const _migratedSettingsStateExports = [
  'settings_account_membership_service.dart',
  'settings_controller_dependencies.dart',
  'settings_controller_models.dart',
  'settings_pairing_flow_service.dart',
  'settings_pairing_state_repository.dart',
  'settings_pairing_state_service.dart',
  'settings_read_model_service.dart',
  'settings_server_config_service.dart',
  'settings_server_status_presenter.dart',
  'settings_storage_maintenance_service.dart',
];
