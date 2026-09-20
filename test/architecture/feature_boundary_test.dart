import 'package:test/test.dart';

import 'architecture_test_utils.dart';

void main() {
  test(
    'calls and messaging do not import each other concrete implementations',
    () {
      final callsImports = _importsFrom('lib/core/calls');
      final messagingImports = _importsFrom('lib/core/messaging');

      final callsToMessaging = callsImports
          .where(
            (import) =>
                import.resolvePeerlinkPath()?.startsWith(
                  'lib/core/messaging/',
                ) ??
                false,
          )
          .map((import) => '${import.location} -> ${import.uri}')
          .toList();
      final messagingToCalls = messagingImports
          .where(
            (import) =>
                import.resolvePeerlinkPath()?.startsWith('lib/core/calls/') ??
                false,
          )
          .map((import) => '${import.location} -> ${import.uri}')
          .toList();

      expect(
        [...callsToMessaging, ...messagingToCalls],
        isEmpty,
        reason:
            'Calls and messaging integration must stay behind explicit seams, '
            'not concrete cross-feature imports.',
      );
    },
  );

  test('core feature modules do not import UI implementation code', () {
    final imports = dartSourcesUnder(const [
      'lib/core/calls',
      'lib/core/messaging',
      'lib/core/relay',
      'lib/core/firebase',
      'lib/core/push',
      'lib/core/signaling',
      'lib/core/transport',
    ]).expand((source) => source.imports());

    final violations =
        imports
            .where(
              (import) =>
                  import.resolvePeerlinkPath()?.startsWith('lib/ui/') ?? false,
            )
            .map((import) => '${import.location} -> ${import.uri}')
            .toList()
          ..sort();

    expect(violations, isEmpty);
  });

  test('feature modules do not import UI implementation code', () {
    final imports = dartSourcesUnder(const [
      'lib/features',
    ]).expand((source) => source.imports());

    final violations =
        imports
            .where(
              (import) =>
                  import.resolvePeerlinkPath()?.startsWith('lib/ui/') ?? false,
            )
            .map((import) => '${import.location} -> ${import.uri}')
            .toList()
          ..sort();

    expect(
      violations,
      isEmpty,
      reason:
          'Feature domain/application/infrastructure code must not depend on UI '
          'implementation paths.',
    );
  });

  test('feature domain does not depend on application or infrastructure', () {
    final violations = _layerImportViolations(
      sourceLayer: 'domain',
      forbiddenTargetLayers: const {'application', 'infrastructure'},
    );

    expect(
      violations,
      isEmpty,
      reason:
          'Feature domain must not depend on application services or '
          'infrastructure implementations.',
    );
  });

  test(
    'feature application infrastructure imports do not grow beyond legacy baseline',
    () {
      final imports = _layerImports(sourceLayer: 'application');
      final violations =
          imports
              .where(
                (import) =>
                    _featureLayer(_projectPath(import)) == 'infrastructure',
              )
              .map((import) => _importEdge(import))
              .where(
                (edge) =>
                    !_legacyApplicationInfrastructureImports.contains(edge),
              )
              .toList()
            ..sort();

      expect(
        violations,
        isEmpty,
        reason:
            'Application services must depend on ports/contracts, not '
            'concrete infrastructure. Legacy imports may only be removed.',
      );
    },
  );

  test(
    'feature modules do not import concrete implementations of other features',
    () {
      final violations = <String>[];
      for (final import in dartSourcesUnder(const [
        'lib/features',
      ]).expand((source) => source.imports())) {
        final sourceFeature = _featureName(import.sourcePath);
        final targetPath = _projectPath(import);
        final targetFeature = _featureName(targetPath);
        if (sourceFeature == null ||
            targetFeature == null ||
            sourceFeature == targetFeature ||
            _isApprovedCrossFeatureContract(targetPath)) {
          continue;
        }
        final edge = _importEdge(import);
        if (!_legacyCrossFeatureConcreteImports.contains(edge)) {
          violations.add(edge);
        }
      }
      violations.sort();

      expect(
        violations,
        isEmpty,
        reason:
            'Cross-feature integration must use explicit contracts, not '
            'concrete implementations. Legacy imports may only be removed.',
      );
    },
  );

  test(
    'only composition imports concrete feature infrastructure from app layer',
    () {
      final violations = <String>[];
      for (final import in dartSourcesUnder(const [
        'lib/app',
      ]).expand((source) => source.imports())) {
        final targetPath = _projectPath(import);
        if (_featureLayer(targetPath) == 'infrastructure' &&
            !import.sourcePath.startsWith('lib/app/composition/')) {
          violations.add(_importEdge(import));
        }
      }
      violations.sort();

      expect(
        violations,
        isEmpty,
        reason:
            'App orchestration must select concrete feature implementations '
            'only in composition modules.',
      );
    },
  );

  test('settings application does not import NodeFacade', () {
    final imports = dartSourcesUnder(const [
      'lib/features/settings/application',
    ]).expand((source) => source.imports());

    final violations =
        imports
            .where(
              (import) =>
                  import.resolvePeerlinkPath() ==
                  'lib/core/node/node_facade.dart',
            )
            .map((import) => '${import.location} -> ${import.uri}')
            .toList()
          ..sort();

    expect(
      violations,
      isEmpty,
      reason:
          'Settings application services should depend on callbacks or narrow '
          'capability APIs instead of unrestricted NodeFacade.',
    );
  });

  test('chat application does not import NodeFacade', () {
    final imports = dartSourcesUnder(const [
      'lib/features/chat/application',
    ]).expand((source) => source.imports());

    final violations =
        imports
            .where(
              (import) =>
                  import.resolvePeerlinkPath() ==
                  'lib/core/node/node_facade.dart',
            )
            .map((import) => '${import.location} -> ${import.uri}')
            .toList()
          ..sort();

    expect(
      violations,
      isEmpty,
      reason:
          'Chat application services should depend on ChatRuntimeApi or '
          'narrower ports instead of unrestricted NodeFacade.',
    );
  });

  test('chat safety uses moderation contracts instead of implementations', () {
    final sources = dartSourcesUnder(const ['lib/features/chat/application'])
        .where(
          (source) => {
            'lib/features/chat/application/chat_safety_api.dart',
            'lib/features/chat/application/chat_safety_service.dart',
          }.contains(source.path),
        );
    final imports = sources
        .expand((source) => source.imports())
        .map((import) => import.resolvePeerlinkPath())
        .whereType<String>()
        .toSet();

    expect(
      imports.intersection(const {
        'core/runtime/moderation_report_service.dart',
        'core/runtime/peer_access_control_service.dart',
        'core/runtime/moderation_api_client.dart',
        'features/moderation/application/moderation_report_service.dart',
        'features/moderation/application/peer_access_control_service.dart',
        'features/moderation/infrastructure/moderation_api_client.dart',
      }),
      isEmpty,
      reason:
          'Chat safety must use moderation contracts, not concrete services.',
    );
    expect(
      imports,
      contains('features/moderation/application/access_policy_api.dart'),
    );
    expect(
      imports,
      contains('features/moderation/application/moderation_reports_api.dart'),
    );
  });

  test('chat lifecycle does not own moderation retry', () {
    final source = dartSourcesUnder(const ['lib/features/chat/application'])
        .singleWhere(
          (source) =>
              source.path ==
              'lib/features/chat/application/chat_controller_lifecycle_service.dart',
        );

    expect(source.content.toLowerCase(), isNot(contains('moderation')));
  });

  test('chat application imports only moderation contracts and models', () {
    final violations = dartSourcesUnder(const ['lib/features/chat/application'])
        .expand((source) => source.imports())
        .where((import) {
          final uri = import.uri;
          return uri.contains('moderation_') &&
              !uri.endsWith('access_policy_api.dart') &&
              !uri.endsWith('access_policy_models.dart') &&
              !uri.endsWith('moderation_reports_api.dart') &&
              !uri.endsWith('moderation_report_models.dart');
        })
        .map((import) => import.location)
        .toList();

    expect(violations, isEmpty);
  });

  test('incoming chat relay discovery does not merge configured servers', () {
    final chatService = dartSourcesUnder(const ['lib/core/messaging'])
        .singleWhere(
          (source) => source.path == 'lib/core/messaging/chat_service.dart',
        );
    final imports = chatService
        .imports()
        .map((import) => import.resolvePeerlinkPath())
        .toSet();

    expect(
      imports,
      isNot(
        contains('lib/core/runtime/runtime_servers_merge_orchestrator.dart'),
      ),
      reason:
          'Relay metadata carried by a chat message belongs in the peer relay '
          'directory, never in the persistent configured relay pool.',
    );
    expect(imports, contains('lib/core/relay/peer_relay_directory.dart'));
  });

  test('UI does not construct moderation infrastructure', () {
    final violations =
        constructorCallViolations(dartSourcesUnder(const ['lib/ui']), const [
          'ModerationApiClient',
          'ModerationDeliveryService',
          'StorageModerationReportOutbox',
        ]);

    expect(violations, isEmpty);
  });

  test('runtime moderation paths are compatibility exports only', () {
    final paths = <String>{
      'lib/core/runtime/moderation_api_client.dart',
      'lib/core/runtime/moderation_delivery_service.dart',
      'lib/core/runtime/moderation_policy_service.dart',
      'lib/core/runtime/moderation_report_models.dart',
      'lib/core/runtime/moderation_report_service.dart',
      'lib/core/runtime/peer_access_control_service.dart',
    };
    final violations = dartSourcesUnder(const ['lib/core/runtime'])
        .where((source) => paths.contains(source.path))
        .where(
          (source) => !RegExp(
            r'^\s*export\s+',
            multiLine: true,
          ).hasMatch(source.content),
        )
        .map((source) => source.path)
        .toList();

    expect(violations, isEmpty);
  });

  test('profile application does not import NodeFacade', () {
    final imports = dartSourcesUnder(const [
      'lib/features/profile/application',
    ]).expand((source) => source.imports());

    final violations =
        imports
            .where(
              (import) =>
                  import.resolvePeerlinkPath() ==
                  'lib/core/node/node_facade.dart',
            )
            .map((import) => '${import.location} -> ${import.uri}')
            .toList()
          ..sort();

    expect(
      violations,
      isEmpty,
      reason:
          'Profile application services should depend on profile-owned ports '
          'instead of unrestricted NodeFacade.',
    );
  });

  test('profile avatar application uses Contacts contract, not UI state', () {
    final source = dartSourcesUnder(const ['lib/features/profile/application'])
        .singleWhere(
          (source) =>
              source.path ==
              'lib/features/profile/application/avatar_service.dart',
        );
    final imports = source
        .imports()
        .map((import) => import.resolvePeerlinkPath())
        .whereType<String>()
        .toSet();

    expect(imports, isNot(contains('lib/ui/state/contacts_controller.dart')));
    expect(
      imports,
      contains('features/contacts/application/contact_profile_api.dart'),
    );
  });

  test(
    'profile metadata has typed Profile persistence and no Settings owner',
    () {
      final source =
          dartSourcesUnder(const [
            'lib/features/profile/application',
          ]).singleWhere(
            (source) =>
                source.path ==
                'lib/features/profile/application/profile_metadata_service.dart',
          );
      final imports = source
          .imports()
          .map((import) => import.resolvePeerlinkPath())
          .whereType<String>()
          .toSet();

      expect(
        imports,
        contains('features/profile/application/profile_store.dart'),
      );
      expect(imports, isNot(contains('ui/state/settings_controller.dart')));
      expect(source.content, contains('updateAbout'));
      expect(source.content, contains('PeerProfileStore'));
    },
  );

  test('Invite domain does not import dart:io', () {
    final violations = dartSourcesUnder(const ['lib/features/invites/domain'])
        .where((source) => source.content.contains("import 'dart:io'"))
        .map((source) => source.path)
        .toList();

    expect(violations, isEmpty);
  });

  test(
    'Invite feature layers keep UI and concrete feature dependencies out',
    () {
      final sources = dartSourcesUnder(const ['lib/features/invites']);
      final violations = <String>[];
      for (final source in sources) {
        for (final import in source.imports()) {
          final target = import.resolvePeerlinkPath() ?? '';
          final isUi = target.startsWith('ui/');
          final isConcreteCrossFeature =
              source.path.contains('/application/') &&
              (target.startsWith('features/contacts/') ||
                  target.startsWith('features/chat/'));
          if (isUi || isConcreteCrossFeature) {
            violations.add('${import.location} -> ${import.uri}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Invite domain/application/infrastructure must use contracts and '
            'must not depend on UI or concrete Contacts/Chat feature code.',
      );
    },
  );

  test(
    'MeshNode does not directly wire ChatService and CallService control callbacks',
    () {
      final meshNode = dartSourcesUnder(const [
        'lib/core/node',
      ]).singleWhere((source) => source.path == 'lib/core/node/mesh_node.dart');

      expect(meshNode.content, isNot(contains('setReliableControlSender')));
      expect(meshNode.content, isNot(contains('setControlHandler')));
      expect(meshNode.content, isNot(contains('handleReliableControlPayload')));
    },
  );

  test('MeshNode does not construct StorageService internally', () {
    final meshNode = dartSourcesUnder(const [
      'lib/core/node',
    ]).singleWhere((source) => source.path == 'lib/core/node/mesh_node.dart');

    expect(meshNode.containsConstructorCall('StorageService'), isFalse);
  });

  test('MeshNode does not construct integration helper services internally', () {
    final meshNode = dartSourcesUnder(const [
      'lib/core/node',
    ]).singleWhere((source) => source.path == 'lib/core/node/mesh_node.dart');

    for (final className in _meshNodeIntegrationHelpers) {
      expect(
        meshNode.containsConstructorCall(className),
        isFalse,
        reason:
            '$className construction belongs in MeshNodeRuntimeAdapterFactory.',
      );
    }
  });
}

List<ImportRecord> _importsFrom(String root) {
  return dartSourcesUnder([root]).expand((source) => source.imports()).toList();
}

String? _featureName(String? path) {
  if (path == null || !path.startsWith('lib/features/')) {
    return null;
  }
  final parts = path.split('/');
  if (parts.length < 3) {
    return null;
  }
  return parts[2];
}

String? _featureLayer(String? path) {
  if (path == null || !path.startsWith('lib/features/')) {
    return null;
  }
  final parts = path.split('/');
  return parts.length >= 4 ? parts[3] : null;
}

String? _projectPath(ImportRecord import) {
  final resolved = import.resolvePeerlinkPath();
  if (resolved == null) {
    return null;
  }
  return resolved.startsWith('lib/') ? resolved : 'lib/$resolved';
}

String _importEdge(ImportRecord import) =>
    '${import.sourcePath} -> ${_projectPath(import)}';

List<ImportRecord> _layerImports({required String sourceLayer}) {
  return dartSourcesUnder(const ['lib/features'])
      .where((source) => _featureLayer(source.path) == sourceLayer)
      .expand((source) => source.imports())
      .toList();
}

List<String> _layerImportViolations({
  required String sourceLayer,
  required Set<String> forbiddenTargetLayers,
}) {
  final violations =
      _layerImports(sourceLayer: sourceLayer)
          .where(
            (import) => forbiddenTargetLayers.contains(
              _featureLayer(_projectPath(import)),
            ),
          )
          .map(_importEdge)
          .toList()
        ..sort();
  return violations;
}

bool _isApprovedCrossFeatureContract(String? path) {
  if (path == null) {
    return false;
  }
  return _approvedCrossFeatureContracts.contains(path) ||
      _featureLayer(path) == 'domain';
}

const _approvedCrossFeatureContracts = {
  'lib/features/contacts/application/contact_profile_api.dart',
  'lib/features/contacts/domain/contact.dart',
  'lib/features/moderation/application/access_policy_api.dart',
  'lib/features/moderation/application/access_policy_models.dart',
  'lib/features/moderation/application/moderation_reports_api.dart',
  'lib/features/moderation/domain/moderation_report_models.dart',
  'lib/features/profile/application/profile_avatar_inbound_handler.dart',
  'lib/features/profile/application/profile_inbound_handler.dart',
};

const _legacyApplicationInfrastructureImports = {
  'lib/features/chat/application/chat_cleanup_coordinator.dart -> lib/features/chat/infrastructure/chat_repository.dart',
  'lib/features/chat/application/chat_cleanup_coordinator.dart -> lib/features/chat/infrastructure/chat_summary_store.dart',
  'lib/features/chat/application/chat_history_load_coordinator.dart -> lib/features/chat/infrastructure/chat_repository.dart',
  'lib/features/chat/application/chat_history_load_coordinator.dart -> lib/features/chat/infrastructure/chat_summary_store.dart',
  'lib/features/chat/application/chat_message_mutation_service.dart -> lib/features/chat/infrastructure/chat_repository.dart',
  'lib/features/chat/application/chat_messages_api.dart -> lib/features/chat/infrastructure/chat_repository.dart',
  'lib/features/chat/application/chat_read_state_service.dart -> lib/features/chat/infrastructure/chat_repository.dart',
  'lib/features/chat/application/chat_receipt_service.dart -> lib/features/chat/infrastructure/chat_repository.dart',
  'lib/features/chat/application/chat_summary_service.dart -> lib/features/chat/infrastructure/chat_summary_store.dart',
  'lib/features/moderation/application/peer_access_control_service.dart -> lib/features/contacts/infrastructure/contacts_repository.dart',
  'lib/features/profile/application/avatar_service.dart -> lib/features/chat/infrastructure/chat_summary_store.dart',
};

const _legacyCrossFeatureConcreteImports = {
  'lib/features/calls/platform/ios_callkit_service.dart -> lib/features/contacts/infrastructure/contact_name_resolver.dart',
  'lib/features/moderation/application/peer_access_control_service.dart -> lib/features/contacts/infrastructure/contacts_repository.dart',
  'lib/features/profile/application/avatar_service.dart -> lib/features/chat/infrastructure/chat_summary_store.dart',
};

const _meshNodeIntegrationHelpers = {
  'MeshCallPushHelper',
  'MeshSignalRouter',
  'PushTokenService',
  'PushEventFactory',
  'PushEventService',
  'PushRuntimeMetadataBuilder',
  'PushAccessPolicySyncService',
  'PushDeviceRegistrationService',
  'ModerationApiClient',
  'ModerationDeliveryService',
  'ModerationPolicyService',
};
