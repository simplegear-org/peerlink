import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/profile/domain/profile.dart';
import 'package:peerlink/features/profile/infrastructure/settings_profile_store.dart';

void main() {
  late Directory root;
  late StorageService storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('peerlink-profile-store-');
    await StorageService.resetForTesting();
    storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
  });

  tearDown(() async {
    await StorageService.resetForTesting();
    await root.delete(recursive: true);
  });

  test('migrates legacy invite username into typed Profile storage', () async {
    await storage.getSettings().put(
      SettingsProfileStore.legacyInviteUsernameKey,
      '  Alice  ',
    );

    final store = SettingsProfileStore(storage: storage);
    await store.migration;

    expect(store.profile.displayName, 'Alice');
    expect(
      storage.getSettings().get(SettingsProfileStore.profileKey),
      <String, dynamic>{'displayName': 'Alice', 'about': ''},
    );
    expect(
      storage.getSettings().get(SettingsProfileStore.legacyInviteUsernameKey),
      isNull,
    );
  });

  test('normalizes and persists an empty display name', () async {
    final store = SettingsProfileStore(storage: storage);

    await store.save(const Profile(displayName: '  Alice  '));
    await store.save(const Profile(displayName: ''));

    expect(store.profile.displayName, isEmpty);
    expect(
      storage.getSettings().get(SettingsProfileStore.profileKey),
      <String, dynamic>{'displayName': '', 'about': ''},
    );
  });

  test('rejects invalid display names before persistence', () async {
    final store = SettingsProfileStore(storage: storage);

    expect(
      () => Profile.normalizeDisplayName('bad\u0000name'),
      throwsFormatException,
    );
    expect(() => Profile.normalizeDisplayName('a' * 65), throwsFormatException);
    expect(store.profile.displayName, isEmpty);
  });

  test('trims and persists about with 160 Unicode characters', () async {
    final store = SettingsProfileStore(storage: storage);
    final about = List<String>.filled(160, '🙂').join();

    await store.save(Profile(about: '  $about  '));

    expect(store.profile.about, about);
    expect(
      () => Profile.normalizeAbout(List<String>.filled(161, '🙂').join()),
      throwsFormatException,
    );
  });
}
