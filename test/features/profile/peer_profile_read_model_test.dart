import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/contacts/application/contact_profile_api.dart';
import 'package:peerlink/features/moderation/application/access_policy_api.dart';
import 'package:peerlink/features/profile/application/peer_profile_api.dart';
import 'package:peerlink/features/profile/application/peer_profile_read_model.dart';
import 'package:peerlink/features/profile/application/profile_metadata_api.dart';
import 'package:peerlink/features/profile/domain/peer_profile.dart';

class _Profiles implements PeerProfileApi {
  _Profiles(this._profiles);

  final Map<String, PeerProfile> _profiles;

  @override
  PeerProfile? profileForPeer(String peerId) => _profiles[peerId.trim()];
}

class _Contacts implements ContactProfileApi {
  _Contacts(this._contactIds, [this._names = const <String, String>{}]);

  final Set<String> _contactIds;
  final Map<String, String> _names;

  @override
  bool hasContact(String peerId) => _contactIds.contains(peerId.trim());

  @override
  Iterable<String> get knownPeerIds => _contactIds;

  @override
  String? contactDisplayNameFor(String peerId) {
    final normalizedPeerId = peerId.trim();
    final name = _names[normalizedPeerId]?.trim() ?? '';
    return name.isEmpty || name == normalizedPeerId ? null : name;
  }

  @override
  Future<bool> applyRemoteUsername({
    required String peerId,
    required String username,
  }) => Future<bool>.value(false);
}

class _AccessPolicy implements AccessPolicyApi {
  _AccessPolicy(this._blockedPeerIds);

  final Set<String> _blockedPeerIds;

  @override
  bool isBlocked(String peerId) => _blockedPeerIds.contains(peerId.trim());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LocalProfile implements ProfileMetadataApi {
  _LocalProfile({required this.displayName, required this.about});

  @override
  final String displayName;

  @override
  final String about;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('uses remote profile data instead of a manual contact alias', () {
    final service = PeerProfileReadService(
      profiles: _Profiles(<String, PeerProfile>{
        'peer-a': const PeerProfile(
          peerId: 'peer-a',
          displayName: 'Remote Alice',
          about: 'Remote about',
          updatedAtMs: 1,
        ),
      }),
      contacts: _Contacts(<String>{'peer-a'}),
      accessPolicy: _AccessPolicy(<String>{'peer-a'}),
      localProfile: _LocalProfile(displayName: 'Local', about: 'Local about'),
      localPeerId: 'local-peer',
    );

    final peer = service.readForPeer(' peer-a ');

    expect(peer.peerId, 'peer-a');
    expect(peer.displayName, 'Remote Alice');
    expect(peer.about, 'Remote about');
    expect(peer.hasAbout, isTrue);
    expect(peer.isContact, isTrue);
    expect(peer.isBlocked, isTrue);
    expect(peer.isLocalPeer, isFalse);
  });

  test('uses a contact name first in peer and group presentation', () {
    final service = PeerProfileReadService(
      profiles: _Profiles(<String, PeerProfile>{
        'peer-a': const PeerProfile(
          peerId: 'peer-a',
          displayName: 'PeerLink Alice',
          about: '',
          updatedAtMs: 1,
        ),
      }),
      contacts: _Contacts(
        <String>{'peer-a'},
        <String, String>{'peer-a': 'Alice from contacts'},
      ),
      accessPolicy: _AccessPolicy(<String>{}),
      localProfile: _LocalProfile(displayName: 'Local', about: ''),
      localPeerId: 'local-peer',
    );

    final peer = service.readForPeer('peer-a');

    expect(peer.displayName, 'PeerLink Alice');
    expect(peer.preferredDisplayName, 'Alice from contacts');
  });

  test('uses a safe peer id fallback for an unknown remote profile', () {
    final service = PeerProfileReadService(
      profiles: _Profiles(<String, PeerProfile>{}),
      contacts: _Contacts(<String>{}),
      accessPolicy: _AccessPolicy(<String>{}),
      localProfile: _LocalProfile(displayName: 'Local', about: 'Local about'),
      localPeerId: 'local-peer',
    );

    final peer = service.readForPeer('1234567890');

    expect(peer.displayName, '1234...7890');
    expect(peer.about, isEmpty);
    expect(peer.hasAbout, isFalse);
    expect(peer.isContact, isFalse);
    expect(peer.isBlocked, isFalse);
    expect(peer.isLocalPeer, isFalse);
  });

  test('uses the local Profile for the current peer', () {
    final service = PeerProfileReadService(
      profiles: _Profiles(<String, PeerProfile>{}),
      contacts: _Contacts(<String>{}),
      accessPolicy: _AccessPolicy(<String>{}),
      localProfile: _LocalProfile(displayName: 'My PeerLink name', about: 'Me'),
      localPeerId: 'local-peer',
    );

    final peer = service.readForPeer('local-peer');

    expect(peer.displayName, 'My PeerLink name');
    expect(peer.about, 'Me');
    expect(peer.isLocalPeer, isTrue);
  });
}
