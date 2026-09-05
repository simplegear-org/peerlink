import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/runtime/account_pairing_payload.dart';
import 'package:peerlink/core/runtime/server_config_payload.dart';
import 'package:peerlink/core/security/account_identity.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';
import 'package:peerlink/ui/localization/app_language.dart';
import 'package:peerlink/ui/localization/app_strings.dart';
import 'package:peerlink/ui/state/settings_controller.dart';

void main() {
  test('server config QR exports only connected servers', () {
    const turnAvailable = TurnServerConfig(
      url: 'turn:available.example:3478?transport=tcp',
      username: 'turn-user',
      password: 'turn-secret',
      priority: 77,
    );
    const turnUnavailable = TurnServerConfig(
      url: 'turn:offline.example:3478?transport=tcp',
      username: 'offline-user',
      password: 'offline-secret',
      priority: 55,
    );
    final controller = _TestSettingsController(
      bootstrapPeers: const <String>[
        'wss://bootstrap.available',
        'wss://bootstrap.pending',
        'wss://bootstrap.offline',
      ],
      relayServers: const <String>[
        'https://relay.available',
        'https://relay.pending',
        'https://relay.offline',
      ],
      turnServers: const <TurnServerConfig>[turnAvailable, turnUnavailable],
      bootstrapStates: const <String, SettingsServerState>{
        'wss://bootstrap.available': SettingsServerState.connected,
        'wss://bootstrap.pending': SettingsServerState.connecting,
        'wss://bootstrap.offline': SettingsServerState.unavailable,
      },
      relayStates: const <String, SettingsServerState>{
        'https://relay.available': SettingsServerState.connected,
        'https://relay.pending': SettingsServerState.connecting,
        'https://relay.offline': SettingsServerState.unavailable,
      },
      turnStates: const <String, SettingsServerState>{
        'turn:available.example:3478?transport=tcp':
            SettingsServerState.connected,
        'turn:offline.example:3478?transport=tcp':
            SettingsServerState.unavailable,
      },
    );

    final payload = _decodeServerConfig(
      controller.exportServerConfigQrPayload(),
    );

    expect(payload.bootstrap, const <String>['wss://bootstrap.available']);
    expect(payload.relay, const <String>['https://relay.available']);
    expect(payload.turn, hasLength(1));
    expect(payload.turn.single.url, turnAvailable.url);
    expect(payload.turn.single.username, turnAvailable.username);
    expect(payload.turn.single.password, turnAvailable.password);
    expect(payload.turn.single.priority, turnAvailable.priority);
  });

  test('server config QR stays valid with empty available server lists', () {
    final controller = _TestSettingsController(
      bootstrapPeers: const <String>['wss://bootstrap.pending'],
      relayServers: const <String>['https://relay.offline'],
      turnServers: const <TurnServerConfig>[
        TurnServerConfig(
          url: 'turn:pending.example:3478?transport=tcp',
          username: 'user',
          password: 'pass',
        ),
      ],
      bootstrapStates: const <String, SettingsServerState>{
        'wss://bootstrap.pending': SettingsServerState.connecting,
      },
      relayStates: const <String, SettingsServerState>{
        'https://relay.offline': SettingsServerState.unavailable,
      },
      turnStates: const <String, SettingsServerState>{
        'turn:pending.example:3478?transport=tcp':
            SettingsServerState.connecting,
      },
    );

    final payload = _decodeServerConfig(
      controller.exportServerConfigQrPayload(),
    );

    expect(payload.bootstrap, isEmpty);
    expect(payload.relay, isEmpty);
    expect(payload.turn, isEmpty);
  });

  test('invite share link is HTTPS and parses like custom scheme invite', () {
    final controller = _TestSettingsController(
      peerId: 'peer-self',
      bootstrapPeers: const <String>[
        'wss://bootstrap.available',
        'wss://bootstrap.pending',
      ],
      relayServers: const <String>[
        'https://relay.available',
        'https://relay.pending',
      ],
      turnServers: const <TurnServerConfig>[],
      bootstrapStates: const <String, SettingsServerState>{
        'wss://bootstrap.available': SettingsServerState.connected,
        'wss://bootstrap.pending': SettingsServerState.connecting,
      },
      relayStates: const <String, SettingsServerState>{
        'https://relay.available': SettingsServerState.connected,
        'https://relay.pending': SettingsServerState.connecting,
      },
      turnStates: const <String, SettingsServerState>{},
    );

    final deepLink = Uri.parse(controller.exportInviteDeepLink());
    final shareLink = Uri.parse(controller.exportInviteShareLink());
    final shareText = const AppStrings(
      AppLanguage.en,
    ).inviteShareText('peer-self', deepLink.toString(), shareLink.toString());

    expect(deepLink.scheme, 'peerlink');
    expect(deepLink.host, 'invite');
    expect(shareLink.scheme, 'https');
    expect(shareLink.host, 'simplegear.org');
    expect(shareLink.pathSegments, contains('invite'));
    expect(shareLink.queryParameters['payload'], isNotEmpty);
    expect(shareText, contains('peerlink://invite?payload='));
    expect(shareText, contains('https://simplegear.org/invite?payload='));

    final deepInvite = controller.parseInviteDeepLink(deepLink.toString());
    final shareInvite = controller.parseInviteDeepLink(shareLink.toString());

    expect(deepInvite.peerId, 'peer-self');
    expect(shareInvite.peerId, deepInvite.peerId);
    expect(deepInvite.identityBundleV3?['peerId'], 'peer-self');
    expect(shareInvite.identityBundleV3, deepInvite.identityBundleV3);
    expect(
      shareInvite.serverConfig.bootstrap,
      deepInvite.serverConfig.bootstrap,
    );
    expect(shareInvite.serverConfig.bootstrap, const <String>[
      'wss://bootstrap.available',
    ]);
    expect(shareInvite.serverConfig.relay, deepInvite.serverConfig.relay);
    expect(shareInvite.serverConfig.relay, const <String>[
      'https://relay.available',
    ]);
  });

  test('server config share link is HTTPS and parses config payload', () {
    final controller = _TestSettingsController(
      peerId: 'peer-self',
      bootstrapPeers: const <String>[
        'wss://bootstrap.available',
        'wss://bootstrap.pending',
      ],
      relayServers: const <String>[
        'https://relay.available',
        'https://relay.pending',
      ],
      turnServers: const <TurnServerConfig>[
        TurnServerConfig(
          url: 'turn:turn.available:3478?transport=tcp',
          username: 'turn-user',
          password: 'turn-secret',
        ),
        TurnServerConfig(
          url: 'turn:turn.pending:3478?transport=tcp',
          username: 'turn-user',
          password: 'turn-secret',
        ),
      ],
      bootstrapStates: const <String, SettingsServerState>{
        'wss://bootstrap.available': SettingsServerState.connected,
        'wss://bootstrap.pending': SettingsServerState.connecting,
      },
      relayStates: const <String, SettingsServerState>{
        'https://relay.available': SettingsServerState.connected,
        'https://relay.pending': SettingsServerState.connecting,
      },
      turnStates: const <String, SettingsServerState>{
        'turn:turn.available:3478?transport=tcp': SettingsServerState.connected,
        'turn:turn.pending:3478?transport=tcp': SettingsServerState.connecting,
      },
    );

    final deepLink = Uri.parse(controller.exportServerConfigDeepLink());
    final shareLink = Uri.parse(controller.exportServerConfigShareLink());
    final shareText = controller.exportServerConfigShareText(
      const AppStrings(AppLanguage.en),
    );

    expect(deepLink.scheme, 'peerlink');
    expect(deepLink.host, 'config');
    expect(deepLink.queryParameters['payload'], isNotEmpty);
    expect(shareLink.scheme, 'https');
    expect(shareLink.host, 'simplegear.org');
    expect(shareLink.pathSegments, contains('config'));
    expect(shareLink.queryParameters['payload'], isNotEmpty);
    expect(shareText, contains('peerlink://config?payload='));
    expect(shareText, contains('https://simplegear.org/config?payload='));

    final deepPayload = controller.parseServerConfigDeepLink(
      deepLink.toString(),
    );
    final payload = controller.parseServerConfigDeepLink(shareLink.toString());

    expect(deepPayload.bootstrap, payload.bootstrap);
    expect(payload.bootstrap, const <String>['wss://bootstrap.available']);
    expect(payload.relay, const <String>['https://relay.available']);
    expect(payload.turn.map((server) => server.url), const <String>[
      'turn:turn.available:3478?transport=tcp',
    ]);
  });

  test(
    'account pairing deep link carries session metadata and full configured servers',
    () {
      final accountIdentity = AccountIdentity(
        accountId: 'account-1',
        displayName: 'Alice',
        devices: <AccountDeviceIdentity>[
          AccountDeviceIdentity(
            deviceId: 'device-self',
            peerId: 'device-self',
            signingPublicKey: 'signing-self',
            createdAtMs: 10,
            updatedAtMs: 20,
            isCurrentDevice: true,
          ),
        ],
      );
      final controller = _TestSettingsController(
        peerId: 'device-self',
        accountIdentity: accountIdentity,
        bootstrapPeers: const <String>[
          'wss://bootstrap.available',
          'wss://bootstrap.offline',
        ],
        relayServers: const <String>[
          'https://relay.available',
          'https://relay.pending',
        ],
        turnServers: const <TurnServerConfig>[],
        bootstrapStates: const <String, SettingsServerState>{
          'wss://bootstrap.available': SettingsServerState.connected,
          'wss://bootstrap.offline': SettingsServerState.unavailable,
        },
        relayStates: const <String, SettingsServerState>{
          'https://relay.available': SettingsServerState.connected,
          'https://relay.pending': SettingsServerState.connecting,
        },
        turnStates: const <String, SettingsServerState>{},
      );

      final deepLink = Uri.parse(controller.exportAccountPairingDeepLink());
      final payload = controller.parseAccountPairingDeepLink(
        deepLink.toString(),
      );
      final rawPayload = controller.parseAccountPairingPayload(
        controller.exportAccountPairingPayload(),
      );

      expect(deepLink.scheme, 'peerlink');
      expect(deepLink.host, 'pair');
      expect(payload.accountId, 'account-1');
      expect(payload.targetDeviceId, 'device-self');
      expect(payload.targetPeerId, 'device-self');
      expect(payload.serverConfig.bootstrap, const <String>[
        'wss://bootstrap.available',
        'wss://bootstrap.offline',
      ]);
      expect(payload.serverConfig.relay, const <String>[
        'https://relay.available',
        'https://relay.pending',
      ]);
      expect(rawPayload.accountId, payload.accountId);
      expect(rawPayload.sessionId, isNotEmpty);
      expect(payload.sessionId, isNotEmpty);
      expect(rawPayload.sessionId, isNot(payload.sessionId));
    },
  );

  test('account pairing can be staged and request-sent explicitly', () async {
    final controller = _TestSettingsController(
      peerId: 'device-self',
      accountIdentity: AccountIdentity(
        accountId: 'account-approve',
        displayName: 'Alice',
        devices: <AccountDeviceIdentity>[
          AccountDeviceIdentity(
            deviceId: 'device-self',
            peerId: 'device-self',
            signingPublicKey: 'signing-self',
            agreementPublicKey: 'agreement-self',
            createdAtMs: 10,
            updatedAtMs: 20,
            isCurrentDevice: true,
          ),
        ],
      ),
      bootstrapPeers: const <String>[],
      relayServers: const <String>[],
      turnServers: const <TurnServerConfig>[],
      bootstrapStates: const <String, SettingsServerState>{},
      relayStates: const <String, SettingsServerState>{},
      turnStates: const <String, SettingsServerState>{},
    );

    final pending = await controller.stageAccountPairingPayload(
      const AccountPairingPayload(
        sessionId: 'session-approve',
        accountId: 'account-approve',
        displayName: 'Alice',
        targetDeviceId: 'device-trusted',
        targetPeerId: 'peer-trusted',
        targetSigningPublicKey: 'signing-trusted',
        serverConfig: ServerConfigPayload(
          bootstrap: <String>['wss://bootstrap.available'],
          relay: <String>['https://relay.available'],
          turn: <TurnServerConfig>[],
          push: <String>[],
        ),
        createdAtMs: 123,
        expiresAtMs: 9999999999999,
      ),
      scannedAtMs: 456,
    );

    expect(controller.pendingAccountPairingRequest, isNotNull);
    expect(pending.scannedAtMs, 456);

    final request = await controller.approvePendingAccountPairing();

    expect(request.targetAccountId, 'account-approve');
    expect(controller.pendingAccountPairingRequest, isNull);
    expect(controller.importedServerConfigModes, <ServerConfigImportMode>[
      ServerConfigImportMode.merge,
    ]);
    expect(controller.sentControlKinds, <String>['accountPairRequest']);
  });

  test(
    'requestAccountPairingDeepLink temporarily imports servers before sending request',
    () async {
      final controller = _TestSettingsController(
        peerId: 'peer-b',
        accountIdentity: AccountIdentity(
          accountId: 'account-local',
          devices: <AccountDeviceIdentity>[
            AccountDeviceIdentity(
              deviceId: 'peer-b',
              peerId: 'peer-b',
              signingPublicKey: 'signing-b',
              agreementPublicKey: 'agreement-b',
              createdAtMs: 1,
              updatedAtMs: 2,
              isCurrentDevice: true,
            ),
          ],
        ),
        bootstrapPeers: const <String>[],
        relayServers: const <String>[],
        turnServers: const <TurnServerConfig>[],
        bootstrapStates: const <String, SettingsServerState>{},
        relayStates: const <String, SettingsServerState>{},
        turnStates: const <String, SettingsServerState>{},
      );

      final raw = jsonEncode(
        const AccountPairingPayload(
          sessionId: 'session-remote',
          accountId: 'account-remote',
          displayName: 'Remote',
          targetDeviceId: 'device-a',
          targetPeerId: 'peer-a',
          targetSigningPublicKey: 'signing-a',
          serverConfig: ServerConfigPayload(
            bootstrap: <String>['wss://bootstrap.available'],
            relay: <String>['https://relay.available'],
            turn: <TurnServerConfig>[
              TurnServerConfig(
                url: 'turn:relay.example:3478?transport=tcp',
                username: 'turn-user',
                password: 'turn-pass',
              ),
            ],
            push: <String>[],
          ),
          createdAtMs: 100,
          expiresAtMs: 9999999999999,
        ).toJson(),
      );

      final request = await controller.requestAccountPairingDeepLink(raw);

      expect(request.requesterPeerId, 'peer-b');
      expect(request.sessionId, 'session-remote');
      expect(request.targetAccountId, 'account-remote');
      expect(controller.importedServerConfigModes, <ServerConfigImportMode>[
        ServerConfigImportMode.merge,
      ]);
      expect(controller.sentControlKinds, <String>['accountPairRequest']);
      expect(
        controller.readSettingValue(accountPairingOutgoingRequestStorageKey),
        isA<String>(),
      );
      expect(
        controller.readSettingValue(accountPairingStagedServerConfigStorageKey),
        isA<String>(),
      );
    },
  );

  test('rejected account pairing restores previous server config', () async {
    final request = AccountPairingRequestPayload(
      requestId: 'pair:1',
      sessionId: 'session-1',
      targetAccountId: 'account-remote',
      targetDeviceId: 'device-a',
      requesterPeerId: 'peer-b',
      requesterAccountId: 'account-b',
      requesterDeviceId: 'device-b',
      requesterDisplayName: '',
      requesterSigningPublicKey: 'signing-b',
      requesterAgreementPublicKey: 'agreement-b',
      requesterEndpointId: null,
      requesterFcmTokenHash: null,
      requestedAtMs: 100,
    );
    final staged = AccountPairingStagedServerConfig(
      previousServerConfig: const ServerConfigPayload(
        bootstrap: <String>[],
        relay: <String>[],
        turn: <TurnServerConfig>[],
        push: <String>[],
      ),
      stagedServerConfig: const ServerConfigPayload(
        bootstrap: <String>['wss://bootstrap.available'],
        relay: <String>['https://relay.available'],
        turn: <TurnServerConfig>[],
        push: <String>[],
      ),
      stagedAtMs: 200,
    );
    final controller = _TestSettingsController(
      bootstrapPeers: const <String>[],
      relayServers: const <String>[],
      turnServers: const <TurnServerConfig>[],
      bootstrapStates: const <String, SettingsServerState>{},
      relayStates: const <String, SettingsServerState>{},
      turnStates: const <String, SettingsServerState>{},
      seedSettings: <String, dynamic>{
        accountPairingOutgoingRequestStorageKey: jsonEncode(request.toJson()),
        accountPairingRejectedPayloadStorageKey: jsonEncode(
          AccountPairingRejectedPayload(
            requestId: 'pair:1',
            sessionId: 'session-1',
            rejectedAtMs: 300,
          ).toJson(),
        ),
        accountPairingStagedServerConfigStorageKey: jsonEncode(staged.toJson()),
      },
    );

    final consumed = await controller
        .consumeRejectedAccountPairingIfAvailable();

    expect(consumed, isTrue);
    expect(controller.importedServerConfigModes, <ServerConfigImportMode>[
      ServerConfigImportMode.replace,
    ]);
    expect(
      controller.readSettingValue(accountPairingOutgoingRequestStorageKey),
      isNull,
    );
    expect(
      controller.readSettingValue(accountPairingRejectedPayloadStorageKey),
      isNull,
    );
    expect(
      controller.readSettingValue(accountPairingStagedServerConfigStorageKey),
      isNull,
    );
  });

  test(
    'stale outgoing account pairing request rolls back staged servers',
    () async {
      final request = AccountPairingRequestPayload(
        requestId: 'pair:stale',
        sessionId: 'session-stale',
        targetAccountId: 'account-remote',
        targetDeviceId: 'device-a',
        requesterPeerId: 'peer-b',
        requesterAccountId: 'account-b',
        requesterDeviceId: 'device-b',
        requesterDisplayName: '',
        requesterSigningPublicKey: 'signing-b',
        requesterAgreementPublicKey: 'agreement-b',
        requesterEndpointId: null,
        requesterFcmTokenHash: null,
        requestedAtMs: DateTime.now()
            .subtract(const Duration(minutes: 6))
            .millisecondsSinceEpoch,
      );
      final staged = AccountPairingStagedServerConfig(
        previousServerConfig: const ServerConfigPayload(
          bootstrap: <String>[],
          relay: <String>[],
          turn: <TurnServerConfig>[],
          push: <String>[],
        ),
        stagedServerConfig: const ServerConfigPayload(
          bootstrap: <String>['wss://bootstrap.available'],
          relay: <String>['https://relay.available'],
          turn: <TurnServerConfig>[],
          push: <String>[],
        ),
        stagedAtMs: 200,
      );
      final controller = _TestSettingsController(
        bootstrapPeers: const <String>[],
        relayServers: const <String>[],
        turnServers: const <TurnServerConfig>[],
        bootstrapStates: const <String, SettingsServerState>{},
        relayStates: const <String, SettingsServerState>{},
        turnStates: const <String, SettingsServerState>{},
        seedSettings: <String, dynamic>{
          accountPairingOutgoingRequestStorageKey: jsonEncode(request.toJson()),
          accountPairingStagedServerConfigStorageKey: jsonEncode(
            staged.toJson(),
          ),
        },
      );

      final expired = await controller
          .expireStaleOutgoingAccountPairingIfNeeded();

      expect(expired, isTrue);
      expect(controller.importedServerConfigModes, <ServerConfigImportMode>[
        ServerConfigImportMode.replace,
      ]);
      expect(
        controller.readSettingValue(accountPairingOutgoingRequestStorageKey),
        isNull,
      );
      expect(
        controller.readSettingValue(accountPairingStagedServerConfigStorageKey),
        isNull,
      );
    },
  );

  test(
    'restorePendingAccountPairingRequest restores pending pairing',
    () async {
      final controller = _TestSettingsController(
        bootstrapPeers: const <String>[],
        relayServers: const <String>[],
        turnServers: const <TurnServerConfig>[],
        bootstrapStates: const <String, SettingsServerState>{},
        relayStates: const <String, SettingsServerState>{},
        turnStates: const <String, SettingsServerState>{},
        seedSettings: <String, dynamic>{
          'pending_account_pairing_request.v1': jsonEncode(
            PendingAccountPairingRequest(
              payload: const AccountPairingPayload(
                sessionId: 'session-restore',
                accountId: 'account-restore',
                displayName: 'Restore',
                targetDeviceId: 'device-restore',
                targetPeerId: 'peer-restore',
                targetSigningPublicKey: 'signing-restore',
                serverConfig: ServerConfigPayload(
                  bootstrap: <String>['wss://bootstrap.available'],
                  relay: <String>[],
                  turn: <TurnServerConfig>[],
                  push: <String>[],
                ),
                createdAtMs: 3,
                expiresAtMs: 9999999999999,
              ),
              scannedAtMs: 4,
            ).toJson(),
          ),
        },
      );

      await controller.restorePendingAccountPairingRequest();

      expect(controller.pendingAccountPairingRequest, isNotNull);
      expect(
        controller.pendingAccountPairingRequest?.payload.accountId,
        'account-restore',
      );
    },
  );
}

ServerConfigPayload _decodeServerConfig(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return ServerConfigPayload.fromJson(decoded);
}

class _TestSettingsController extends SettingsController {
  final String _peerId;
  final List<String> _bootstrapPeers;
  final List<String> _relayServers;
  final List<TurnServerConfig> _turnServers;
  final Map<String, SettingsServerState> _bootstrapStates;
  final Map<String, SettingsServerState> _relayStates;
  final Map<String, SettingsServerState> _turnStates;
  final Map<String, dynamic> _settings;
  final AccountIdentity _accountIdentity;
  final List<ServerConfigImportMode> importedServerConfigModes =
      <ServerConfigImportMode>[];
  final List<String> sentControlKinds = <String>[];
  AccountIdentity? lastMergedAccountIdentity;
  AccountIdentity? lastAppliedApprovedPairingIdentity;
  AccountDeviceIdentity? lastIssuedRequestedDevice;
  String? lastIssuedSessionId;

  _TestSettingsController({
    String peerId = 'test-peer',
    AccountIdentity? accountIdentity,
    Map<String, dynamic>? seedSettings,
    required List<String> bootstrapPeers,
    required List<String> relayServers,
    required List<TurnServerConfig> turnServers,
    required Map<String, SettingsServerState> bootstrapStates,
    required Map<String, SettingsServerState> relayStates,
    required Map<String, SettingsServerState> turnStates,
  }) : _peerId = peerId,
       _bootstrapPeers = bootstrapPeers,
       _relayServers = relayServers,
       _turnServers = turnServers,
       _bootstrapStates = bootstrapStates,
       _relayStates = relayStates,
       _turnStates = turnStates,
       _settings = Map<String, dynamic>.from(
         seedSettings ?? const <String, dynamic>{},
       ),
       _accountIdentity =
           accountIdentity ??
           AccountIdentity(
             accountId: 'test-account',
             devices: <AccountDeviceIdentity>[
               AccountDeviceIdentity(
                 deviceId: peerId,
                 peerId: peerId,
                 signingPublicKey: 'signing-$peerId',
                 agreementPublicKey: 'agreement-$peerId',
                 createdAtMs: 10,
                 updatedAtMs: 20,
                 isCurrentDevice: true,
               ),
             ],
           ),
       super(facade: _FakeNodeFacade(), storage: StorageService());

  @override
  String get peerId => _peerId;

  @override
  String get accountId => _accountIdentity.accountId;

  @override
  String get activeAccountId => _accountIdentity.accountId;

  @override
  String get homeAccountId => _accountIdentity.accountId;

  @override
  String get deviceId => _peerId;

  @override
  AccountIdentity get accountIdentity => _accountIdentity;

  @override
  dynamic readSettingValue(String key) => _settings[key];

  @override
  Future<void> writeSettingValue(String key, dynamic value) async {
    _settings[key] = value;
  }

  @override
  Future<void> deleteSettingValue(String key) async {
    _settings.remove(key);
  }

  @override
  Future<void> importServerConfigPayload(
    ServerConfigPayload payload, {
    required ServerConfigImportMode mode,
  }) async {
    importedServerConfigModes.add(mode);
  }

  @override
  Future<AccountIdentity> mergeAccountIdentity(AccountIdentity identity) async {
    lastMergedAccountIdentity = identity;
    return identity;
  }

  @override
  Future<AccountIdentity> issueApprovedPairingAccountIdentity({
    required AccountDeviceIdentity requestedDevice,
    required String sessionId,
  }) async {
    lastIssuedRequestedDevice = requestedDevice;
    lastIssuedSessionId = sessionId;
    return _accountIdentity.upsertDevice(
      requestedDevice.copyWith(
        approvedByDeviceId: _peerId,
        approvedAtMs: 123,
        enrollmentSessionId: sessionId,
        membershipSignature: 'sig',
      ),
    );
  }

  @override
  Future<AccountIdentity> applyApprovedPairingAccountIdentity(
    AccountIdentity identity, {
    required String expectedSessionId,
    required String expectedAccountId,
  }) async {
    lastAppliedApprovedPairingIdentity = identity;
    return identity;
  }

  @override
  Future<void> sendAccountPairingControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) async {
    sentControlKinds.add(kind);
  }

  @override
  String? get endpointId => null;

  @override
  String? get fcmTokenHash => null;

  @override
  List<String> get bootstrapPeers => List<String>.from(_bootstrapPeers);

  @override
  List<String> get relayServers => List<String>.from(_relayServers);

  @override
  List<TurnServerConfig> get turnServers =>
      List<TurnServerConfig>.from(_turnServers);

  @override
  SettingsServerState bootstrapState(String endpoint) =>
      _bootstrapStates[endpoint] ?? SettingsServerState.connecting;

  @override
  SettingsServerState relayState(String endpoint) =>
      _relayStates[endpoint] ?? SettingsServerState.connecting;

  @override
  SettingsServerState turnState(String url) =>
      _turnStates[url] ?? SettingsServerState.connecting;
}

class _FakeNodeFacade implements NodeFacade {
  @override
  Map<String, dynamic> get identityBundleV3Json => <String, dynamic>{
    'type': 'peerlink_identity_bundle',
    'version': 3,
    'peerId': 'peer-self',
    'signingPublicKey': 'signing-peer-self',
    'agreementPublicKey': 'agreement-peer-self',
    'signature': 'signature-peer-self',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
