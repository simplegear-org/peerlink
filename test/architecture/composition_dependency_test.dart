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
}
