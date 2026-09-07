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
