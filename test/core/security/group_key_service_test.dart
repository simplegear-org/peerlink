import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/security/group_key_service.dart';

class _MemoryGroupKeyStore implements GroupKeyStore {
  final Map<String, dynamic> data = <String, dynamic>{};

  @override
  Iterable<String> get keys => data.keys;

  @override
  dynamic get(String key) => data[key];

  @override
  Future<void> put(String key, dynamic value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

void main() {
  group('GroupKeyService', () {
    late _MemoryGroupKeyStore store;
    late GroupKeyService service;

    setUp(() {
      store = _MemoryGroupKeyStore();
      service = GroupKeyService(store);
    });

    test(
      'migrates legacy key maps into per-group storage and removes legacy',
      () async {
        store.data[GroupKeyService.legacyGroupKeysStorageKey] =
            <String, dynamic>{
              'group:1': base64Encode(List<int>.generate(32, (i) => i)),
            };
        store.data[GroupKeyService.legacyGroupKeyVersionsStorageKey] =
            <String, dynamic>{'group:1': 3};

        await service.initialize();

        expect(service.keyForGroup('group:1'), isNotNull);
        expect(service.keyVersionForGroup('group:1'), 3);
        expect(
          store.data.containsKey(GroupKeyService.legacyGroupKeysStorageKey),
          isFalse,
        );
        expect(
          store.data.containsKey(
            GroupKeyService.legacyGroupKeyVersionsStorageKey,
          ),
          isFalse,
        );
        expect(store.data.containsKey('peerlink.group_key.v2.group:1'), isTrue);
        expect(
          store.data.containsKey('peerlink.group_key_version.v2.group:1'),
          isTrue,
        );
      },
    );

    test('ensureGroupKey creates key and version=1 for new group', () async {
      await service.initialize();

      final key = await service.ensureGroupKey('group:new');

      expect(base64Decode(key).length, 32);
      expect(service.keyVersionForGroup('group:new'), 1);
      expect(store.data['peerlink.group_key.v2.group:new'], key);
      expect(store.data['peerlink.group_key_version.v2.group:new'], 1);
    });

    test('rotateGroupKey increments version and changes key', () async {
      await service.initialize();
      final first = await service.ensureGroupKey('group:r');

      final rotation = await service.rotateGroupKey('group:r');

      expect(rotation.version, 2);
      expect(rotation.keyBase64, isNot(first));
      expect(service.keyVersionForGroup('group:r'), 2);
      expect(service.keyForGroup('group:r'), rotation.keyBase64);
    });

    test(
      'applyIncomingGroupKey ignores older version and accepts newer version',
      () async {
        await service.initialize();
        final current = await service.ensureGroupKey('group:incoming');
        await service.rotateGroupKey('group:incoming');
        final currentV2 = service.keyForGroup('group:incoming');

        final olderApplied = await service.applyIncomingGroupKey(
          groupId: 'group:incoming',
          groupKeyBase64: current,
          keyVersion: 1,
        );
        expect(olderApplied, isFalse);
        expect(service.keyVersionForGroup('group:incoming'), 2);
        expect(service.keyForGroup('group:incoming'), currentV2);

        final newerKey = base64Encode(
          List<int>.generate(32, (i) => (255 - i) & 0xFF),
        );
        final newerApplied = await service.applyIncomingGroupKey(
          groupId: 'group:incoming',
          groupKeyBase64: newerKey,
          keyVersion: 3,
        );
        expect(newerApplied, isTrue);
        expect(service.keyVersionForGroup('group:incoming'), 3);
        expect(service.keyForGroup('group:incoming'), newerKey);
      },
    );

    test('runGc removes keys of non-active groups only', () async {
      await service.initialize();
      await service.ensureGroupKey('group:keep');
      await service.ensureGroupKey('group:remove');
      await service.rotateGroupKey('group:remove');

      final report = await service.runGc(activeGroupIds: {'group:keep'});

      expect(report.removedKeys, 1);
      expect(report.removedVersions, 1);
      expect(service.keyForGroup('group:keep'), isNotNull);
      expect(service.keyForGroup('group:remove'), isNull);
      expect(service.keyVersionForGroup('group:remove'), 0);
      expect(
        store.data.containsKey('peerlink.group_key.v2.group:remove'),
        isFalse,
      );
      expect(
        store.data.containsKey('peerlink.group_key_version.v2.group:remove'),
        isFalse,
      );
    });
  });
}
