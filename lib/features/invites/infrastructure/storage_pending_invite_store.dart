import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/invites/application/pending_invite_store.dart';
import 'package:peerlink/features/invites/domain/invite_manifest.dart';

class StoragePendingInviteStore implements PendingInviteStore {
  static const _key = 'peerlink.invites.pending_token.v1';

  StoragePendingInviteStore(this._storage);

  final StorageService _storage;

  @override
  Future<String?> load() async {
    final value = _storage.getSettings().get(_key);
    if (value is String && InviteManifest.isValidToken(value)) return value;
    if (value != null) await _storage.getSettings().delete(_key);
    return null;
  }

  @override
  Future<void> save(String token) async {
    if (!InviteManifest.isValidToken(token)) {
      throw const FormatException('Недопустимый token приглашения');
    }
    await _storage.getSettings().put(_key, token);
  }

  @override
  Future<void> clear(String token) async {
    if (_storage.getSettings().get(_key) == token) {
      await _storage.getSettings().delete(_key);
    }
  }
}
