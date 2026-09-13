import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/app/invites/invite_flow_coordinator.dart';
import 'package:peerlink/app/invites/invite_manifest_client.dart';
import 'package:peerlink/core/security/peer_identity_bundle_v3.dart';

void main() {
  final invite = InviteManifest.fromJson(<String, dynamic>{
    'version': 1,
    'inviteId': 'invite-123',
    'expiration': '2030-01-01T00:00:00Z',
    'inviter': <String, dynamic>{
      'peerId': 'inviter',
      'username': 'Vladimir',
      'identityBundle': const PeerIdentityBundleV3(
        peerId: 'inviter',
        signingPublicKey: 'signing',
        agreementPublicKey: 'agreement',
        signature: 'signature',
      ).toJson(),
    },
  });

  test(
    'verifies identity before contact and chat, and is idempotent',
    () async {
      final events = <String>[];
      final coordinator = _coordinator(
        invite: invite,
        events: events,
        identityResult: true,
      );

      final completed = await coordinator.handleInviteUrl(
        Uri.parse('https://simplegear.org/i/aaaaaaaaaaaaaaaaaaaaaa'),
      );
      expect(completed.type, InviteFlowResultType.completed);
      expect(completed.displayName, 'Vladimir');
      expect(events, <String>[
        'bootstrap',
        'servers',
        'verify:inviter',
        'contact:inviter:Vladimir',
        'chat:inviter:Vladimir',
        'open:inviter:Vladimir',
      ]);
      expect(
        (await coordinator.handleInviteUrl(
          Uri.parse('https://simplegear.org/i/aaaaaaaaaaaaaaaaaaaaaa'),
        )).type,
        InviteFlowResultType.duplicate,
      );
    },
  );

  test('emits safe structured diagnostics for completed lifecycle', () async {
    final diagnostics = <String>[];
    final coordinator = _coordinator(
      invite: invite,
      events: <String>[],
      diagnostics: diagnostics,
    );

    await coordinator.handleInviteUrl(
      Uri.parse('https://simplegear.org/i/gggggggggggggggggggggg'),
    );

    expect(diagnostics, <String>[
      'invite_received',
      'invite_resolve_start',
      'invite_resolve_success',
      'default_config_required',
      'default_config_ready',
      'identity_verified',
      'username_resolved',
      'contact_ready',
      'chat_ready',
      'chat_opened',
      'invite_completed',
    ]);
    expect(diagnostics.join(' '), isNot(contains('gggg')));
    expect(diagnostics.join(' '), isNot(contains('inviter')));
  });

  test(
    'does not create contact or chat when identity verification fails',
    () async {
      final events = <String>[];
      final coordinator = _coordinator(
        invite: invite,
        events: events,
        identityResult: false,
      );

      final result = await coordinator.handleInviteUrl(
        Uri.parse('https://simplegear.org/i/bbbbbbbbbbbbbbbbbbbbbb'),
      );
      expect(result.type, InviteFlowResultType.terminalFailure);
      expect(events, <String>['bootstrap', 'servers', 'verify:inviter']);
    },
  );

  test(
    'rejects a self invite before server or identity side effects',
    () async {
      final events = <String>[];
      final coordinator = _coordinator(
        invite: invite,
        events: events,
        localPeerId: 'inviter',
      );

      final result = await coordinator.handleInviteUrl(
        Uri.parse('https://simplegear.org/i/cccccccccccccccccccccc'),
      );
      expect(result.type, InviteFlowResultType.terminalFailure);
      expect(events, isEmpty);
    },
  );

  test(
    'propagates default-server bootstrap failure before side effects',
    () async {
      final events = <String>[];
      final coordinator = InviteFlowCoordinator(
        localPeerId: 'recipient',
        verifyIdentity: (bundle, {required expectedPeerId}) async {
          events.add('verify');
          return true;
        },
        ensureInitialServerConfig: () async =>
            throw StateError('initial config unavailable'),
        mergeServers: (config) async => events.add('servers'),
        upsertContact: ({required peerId, username}) async =>
            events.add('contact'),
        ensureDirectChat: ({required peerId, required name}) async =>
            events.add('chat'),
        openChat: (peerId, name) => events.add('open'),
        localIdentityBundle: invite.identityBundleV3,
        signInviteManifest: (manifest) async => 'signature',
        localUsername: () => 'Vladimir',
        currentServerConfig: () => invite.serverConfig,
        manifestClient: _FakeInviteManifestClient(invite),
      );

      final result = await coordinator.handleInviteUrl(
        Uri.parse('https://simplegear.org/i/dddddddddddddddddddddd'),
      );
      expect(result.type, InviteFlowResultType.retryableFailure);
      expect(events, isEmpty);
    },
  );

  test(
    'persists a retryable invite and clears it after restart succeeds',
    () async {
      final store = _PendingInviteTokenStore();
      final first = _coordinator(
        invite: invite,
        events: <String>[],
        pendingStore: store,
        manifestClient: _ThrowingInviteManifestClient(
          const InviteResolveException('offline', retryable: true),
        ),
      );

      final failed = await first.handleInviteUrl(
        Uri.parse('https://simplegear.org/i/eeeeeeeeeeeeeeeeeeeeee'),
      );
      expect(failed.type, InviteFlowResultType.retryableFailure);
      expect(store.token, 'eeeeeeeeeeeeeeeeeeeeee');

      final events = <String>[];
      final restarted = _coordinator(
        invite: invite,
        events: events,
        pendingStore: store,
      );
      final resumed = await restarted.resumePendingInvite();
      expect(resumed?.type, InviteFlowResultType.completed);
      expect(store.token, isNull);
      expect(events, contains('contact:inviter:Vladimir'));
    },
  );

  test('clears a terminal pending invite instead of retrying it', () async {
    final store = _PendingInviteTokenStore()..token = 'ffffffffffffffffffffff';
    final coordinator = _coordinator(
      invite: invite,
      events: <String>[],
      pendingStore: store,
      manifestClient: _ThrowingInviteManifestClient(
        const FormatException('expired'),
      ),
    );

    final result = await coordinator.resumePendingInvite();
    expect(result?.type, InviteFlowResultType.terminalFailure);
    expect(store.token, isNull);
  });
}

InviteFlowCoordinator _coordinator({
  required InviteManifest invite,
  required List<String> events,
  bool identityResult = true,
  String localPeerId = 'recipient',
  _PendingInviteTokenStore? pendingStore,
  InviteManifestClient? manifestClient,
  List<String>? diagnostics,
}) {
  return InviteFlowCoordinator(
    localPeerId: localPeerId,
    verifyIdentity: (bundle, {required expectedPeerId}) async {
      events.add('verify:$expectedPeerId');
      return identityResult;
    },
    ensureInitialServerConfig: () async => events.add('bootstrap'),
    mergeServers: (config) async => events.add('servers'),
    upsertContact: ({required peerId, username}) async =>
        events.add('contact:$peerId:$username'),
    ensureDirectChat: ({required peerId, required name}) async =>
        events.add('chat:$peerId:$name'),
    openChat: (peerId, name) => events.add('open:$peerId:$name'),
    localIdentityBundle: invite.identityBundleV3,
    signInviteManifest: (manifest) async => 'signature',
    localUsername: () => 'Vladimir',
    currentServerConfig: () => invite.serverConfig,
    loadPendingInviteToken: pendingStore?.load,
    savePendingInviteToken: pendingStore?.save,
    clearPendingInviteToken: pendingStore?.clear,
    manifestClient: manifestClient ?? _FakeInviteManifestClient(invite),
    logDiagnostic: diagnostics?.add,
  );
}

class _FakeInviteManifestClient extends InviteManifestClient {
  _FakeInviteManifestClient(this.invite);

  final InviteManifest invite;

  @override
  Future<InviteManifest> resolve(String token) async => invite;
}

class _ThrowingInviteManifestClient extends InviteManifestClient {
  _ThrowingInviteManifestClient(this.error);

  final Object error;

  @override
  Future<InviteManifest> resolve(String token) =>
      Future<InviteManifest>.error(error);
}

class _PendingInviteTokenStore {
  String? token;

  Future<String?> load() async => token;

  Future<void> save(String value) async {
    token = value;
  }

  Future<void> clear(String value) async {
    if (token == value) token = null;
  }
}
