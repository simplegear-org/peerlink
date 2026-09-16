abstract interface class PendingInviteStore {
  Future<String?> load();
  Future<void> save(String token);
  Future<void> clear(String token);
}
