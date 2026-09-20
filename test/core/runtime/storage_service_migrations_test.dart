import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/secure_storage_wrapper.dart';
import 'package:peerlink/core/runtime/storage_service_migrations.dart';

void main() {
  test('preserves a legacy group avatar in group metadata', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peerlink-storage-migration-test-',
    );
    addTearDown(() async {
      SecureStorageWrapper.resetForTesting();
      await directory.delete(recursive: true);
    });
    SecureStorageWrapper.resetForTesting();
    await SecureStorageWrapper.initialize(fallbackDirectory: directory);
    await SecureStorageWrapper.write(
      'peerlink.chats',
      jsonEncode(<String, dynamic>{
        'group:team': <String, dynamic>{
          'peerId': 'group:team',
          'name': 'Team',
          'isGroup': true,
          'memberPeerIds': <String>['alice', 'bob'],
          'avatarPath': '/legacy/media/group_avatar.png',
        },
      }),
    );

    final boxes = <String, Map<String, dynamic>>{
      'contacts': <String, dynamic>{},
      'settings': <String, dynamic>{},
      'group_meta': <String, dynamic>{},
      'group_keys': <String, dynamic>{},
    };
    final summaries = <String, Map<String, dynamic>>{};
    final migration = StorageServiceMigrations(
      boxes: boxes,
      contactsBoxName: 'contacts',
      settingsBoxName: 'settings',
      groupMetaBoxName: 'group_meta',
      groupKeysBoxName: 'group_keys',
      legacyChatsStorageKey: 'peerlink.chats',
      chatPageSize: 30,
      legacyGroupMetaSettingsKey: 'peerlink.group_meta.v1',
      legacyGroupKeysSettingsKey: 'peerlink.group_keys.v1',
      legacyGroupKeyVersionsSettingsKey: 'peerlink.group_key_versions.v1',
      groupKeyStoragePrefix: 'peerlink.group_key.v2.',
      groupKeyVersionStoragePrefix: 'peerlink.group_key_version.v2.',
      groupMetaStateKey: 'state.v1',
      boxKeyFor: (boxName) => 'peerlink.$boxName',
      persistBox: (_) async {},
      getChatSummary: (peerId) async => summaries[peerId],
      loadAllChatSummaries: () async => summaries.values.toList(),
      saveChatSummaryMap: (peerId, json) async {
        summaries[peerId] = json;
      },
      loadConversationHeads: () async => const <Map<String, dynamic>>[],
      readChatMessages: (_) async => <Map<String, dynamic>>[],
      writeChatMessages: (peerId, messages) async {},
    );

    await migration.migrateLegacyChatsToSqlite();

    final groupState = boxes['group_meta']!['state.v1'] as Map;
    final group = groupState['group:team'] as Map;
    expect(group['isGroup'], isTrue);
    expect(group['avatarPath'], '/legacy/media/group_avatar.png');
  });
}
