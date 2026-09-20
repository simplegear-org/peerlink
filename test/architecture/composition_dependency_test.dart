import 'package:test/test.dart';

import 'architecture_test_utils.dart';

void main() {
  test(
    'NetworkDependencies.create remains limited to current bootstrap entrypoints',
    () {
      final counts = constructorCallCounts(
        dartSourcesUnder(const ['lib']),
        'NetworkDependencies.create',
      );

      expect(
        counts,
        equals(const {'lib/app/composition/app_composition_root.dart': 1}),
      );
    },
  );

  test('NetworkDependencies does not keep singleton runtime state', () {
    final source = dartSourcesUnder(const ['lib/core/runtime']).singleWhere(
      (source) => source.path == 'lib/core/runtime/network_dependencies.dart',
    );

    expect(source.content, isNot(contains('static NetworkDependencies?')));
    expect(
      source.content,
      isNot(contains('static Future<NetworkDependencies>?')),
    );
  });

  test('production NodeFacade consumers do not grow beyond the baseline', () {
    final consumers = dartSourcesUnder(const ['lib'])
        .where(
          (source) => source.imports().any(
            (import) =>
                import.resolvePeerlinkPath() ==
                'lib/core/node/node_facade.dart',
          ),
        )
        .map((source) => source.path)
        .toSet();

    expect(
      consumers.difference(_nodeFacadeConsumerBaseline),
      isEmpty,
      reason:
          'NodeFacade is migration debt. New production consumers must use '
          'narrow capability APIs; the baseline may only shrink.',
    );
  });

  test(
    'production StorageService construction does not grow outside baseline',
    () {
      final counts = constructorCallCounts(
        dartSourcesUnder(const ['lib']),
        'StorageService',
      );

      expect(
        counts,
        equals(const {
          'lib/core/firebase/firebase_messaging_service.dart': 1,
          'lib/app/composition/app_composition_root.dart': 1,
        }),
        reason:
            'Production storage may be created only by app/bootstrap '
            'entrypoints. The Firebase background handler is a separate '
            'background isolate composition root.',
      );
    },
  );

  test('migrated app coordinators depend on narrow node capability APIs', () {
    final sources = dartSourcesUnder(const [
      'lib/app/calls',
      'lib/app/deep_links',
      'lib/app/push',
    ]);
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
          'Migrated app coordinators should receive CallsApi, NetworkApi, '
          'IdentityApi, or other narrow node contracts instead of NodeFacade.',
    );
  });

  test(
    'InviteFlowCoordinator depends on InviteApi, not HTTP infrastructure',
    () {
      final source = dartSourcesUnder(const ['lib/app/invites']).singleWhere(
        (source) =>
            source.path == 'lib/app/invites/invite_flow_coordinator.dart',
      );
      final imports = source
          .imports()
          .map((import) => import.resolvePeerlinkPath())
          .whereType<String>()
          .toSet();

      expect(imports, contains('features/invites/application/invite_api.dart'));
      expect(
        imports,
        isNot(
          contains(
            'features/invites/infrastructure/invite_manifest_client.dart',
          ),
        ),
      );
      expect(
        imports.where((path) => path.startsWith('ui/')),
        isEmpty,
        reason:
            'InviteFlowCoordinator is app orchestration and must receive UI '
            'workflows through narrow commands, not UI implementations.',
      );
    },
  );

  test('ChatControllerComposition uses narrow ports instead of callbacks', () {
    final composition = dartSourcesUnder(const ['lib/app/composition'])
        .singleWhere(
          (source) =>
              source.path ==
              'lib/app/composition/chat_controller_composition.dart',
        );
    final dependencies =
        dartSourcesUnder(const ['lib/features/chat/application']).singleWhere(
          (source) =>
              source.path ==
              'lib/features/chat/application/chat_controller_dependencies.dart',
        );

    final callbackParameters = RegExp(
      r'required\s+(?:Future<[^>]+>|void|bool|int|String|Chat|Message)'
      r'\s+Function\s*\(',
    );

    expect(
      callbackParameters.allMatches(composition.content),
      isEmpty,
      reason:
          'ChatControllerComposition.create must receive cohesive chat ports, '
          'not a giant callback signature from ChatController.',
    );
    expect(
      callbackParameters.allMatches(dependencies.content),
      isEmpty,
      reason:
          'ChatControllerDependenciesFactory must expose cohesive chat ports, '
          'not a giant callback signature from ChatController.',
    );
  });

  test(
    'composition modules do not contain imperative business control flow',
    () {
      final violations = <String>[];
      final businessControlFlow = RegExp(
        r'\b(?:if|for|while|switch|try|catch)\s*(?:\(|\{)',
      );

      for (final source in dartSourcesUnder(const ['lib/app/composition'])) {
        if (businessControlFlow.hasMatch(source.content)) {
          violations.add(source.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Composition may construct and connect services, but business '
            'decisions and imperative workflows belong to application services.',
      );
    },
  );

  test('ChatControllerDependencies exposes grouped dependency surface', () {
    final source = dartSourcesUnder(const ['lib/features/chat/application'])
        .singleWhere(
          (source) =>
              source.path ==
              'lib/features/chat/application/chat_controller_dependencies.dart',
        );
    final classMatch = RegExp(
      r'class\s+ChatControllerDependencies\s*\{([\s\S]*?)\n\}',
    ).firstMatch(source.content);

    expect(classMatch, isNotNull);

    final topLevelFields = RegExp(
      r'^\s*final\s+Chat[A-Za-z]+Dependencies\s+\w+;',
      multiLine: true,
    ).allMatches(classMatch!.group(1)!);

    expect(
      topLevelFields.length,
      lessThanOrEqualTo(6),
      reason:
          'ChatControllerDependencies must expose grouped application-level '
          'dependency contracts instead of dozens of individual services.',
    );
  });

  test('migrated runtime support services avoid NodeFacade', () {
    final sources = dartSourcesUnder(const [
      'lib/core/runtime',
    ]).where((source) => _migratedRuntimeSupportServices.contains(source.path));
    final violations = <String>[];

    for (final source in sources) {
      for (final import in source.imports()) {
        if (import.resolvePeerlinkPath() == 'lib/core/node/node_facade.dart') {
          violations.add(import.location);
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Migrated runtime support services should depend on narrow node '
          'capability APIs instead of unrestricted NodeFacade.',
    );
  });
}

const _migratedRuntimeSupportServices = {
  'lib/core/runtime/app_data_cleaner_service.dart',
  'lib/core/runtime/bootstrap_servers_service.dart',
  'lib/core/runtime/relay_servers_service.dart',
  'lib/core/runtime/server_health_coordinator.dart',
  'lib/core/runtime/turn_servers_service.dart',
};

const _nodeFacadeConsumerBaseline = {
  'lib/app/composition/app_dependencies.dart',
  'lib/app/composition/app_ui_dependencies.dart',
  'lib/app/composition/chat_runtime_node_adapter.dart',
  'lib/app/composition/profile_avatar_node_adapter.dart',
  'lib/core/runtime/network_dependencies.dart',
  'lib/core/runtime/push_device_registration_service.dart',
  'lib/features/calls/platform/ios_callkit_service.dart',
  'lib/main.dart',
  'lib/ui/ui_app.dart',
};
