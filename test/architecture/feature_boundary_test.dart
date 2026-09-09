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

  test('feature modules do not import other feature concrete code', () {
    final imports = dartSourcesUnder(const [
      'lib/features',
    ]).expand((source) => source.imports());

    final violations = <String>[];
    for (final import in imports) {
      final sourceFeature = _featureName(import.sourcePath);
      final targetPath = import.resolvePeerlinkPath();
      final targetFeature = _featureName(targetPath);
      if (sourceFeature == null ||
          targetFeature == null ||
          sourceFeature == targetFeature) {
        continue;
      }
      if (_approvedCrossFeatureContracts.contains(targetPath)) {
        continue;
      }
      violations.add('${import.location} -> ${import.uri}');
    }
    violations.sort();

    expect(
      violations,
      isEmpty,
      reason:
          'Cross-feature integration must use explicit contracts/adapters, '
          'not concrete implementation imports.',
    );
  });

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

const _approvedCrossFeatureContracts = {
  'lib/features/contacts/domain/contact.dart',
  'lib/features/moderation/application/access_policy_api.dart',
  'lib/features/moderation/application/moderation_reports_api.dart',
  'lib/features/moderation/domain/moderation_report_models.dart',
  'lib/features/profile/application/profile_avatar_inbound_handler.dart',
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
