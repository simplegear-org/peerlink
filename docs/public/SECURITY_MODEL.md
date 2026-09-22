# SECURITY_MODEL

Last updated: 2026-09-16

This file captures what PeerLink security can honestly claim today and where hardening still needs to happen.

## 1. Threat Model

Assume:
- network observers can see traffic metadata,
- TURN and relay infrastructure is untrusted,
- bootstrap signaling path is untrusted transport,
- replay and MITM attempts are possible.

## 2. AS-IS Security

### 2.1 Identity and Keys

- `IdentityService` manages node identity.
- Signing and key-agreement material is persisted through storage wrappers.
- `SignatureService` supports sign/verify for protocol payloads.
- Runtime identity uses stable `peerId` (v2) derived from signing key + installation id.
- Legacy peer id (hash of signing key only) is retained for compatibility metadata.
- For invisible v2 -> v3 migration, the client publishes a signed identity bundle v3: the old `peerId` remains the routing/id value, while `signingPublicKey` and `agreementPublicKey` are carried as a verifiable bundle signed by the signing key.
- `AccountIdentity` adds an account layer above device identity: `accountId`, `displayName`, device list, and the local `peerlink://pair` QR/deep link pairing flow.

### 2.2 Session Crypto

- `SessionManager` + `SessionCrypto` implement handshake and payload encryption APIs.
- Reliable messaging path is integrated with session APIs.
- Runtime `NetworkDependencies` config enables reliable messaging encryption (`enableEncryption: true`).
- A direct reliable envelope may carry `senderIdentityBundleV3`; the receiver verifies the bundle signature and stores peer keys before decrypt, so a new encrypted session can be established without an online handshake when the bundle was already received through invite/QR or an inbound reliable message.
- Group control distribution (`groupKey`, `groupInvite`, `groupMembers`) is sent through encrypted control messages (session E2E path), not plain envelopes.

### 2.3 Group Key Management

- Group keys are stored in per-group records:
  - `peerlink.group_key.v2.<groupId>`
  - `peerlink.group_key_version.v2.<groupId>`
- Legacy storage (`peerlink.group_keys.v1`, `peerlink.group_key_versions.v1`) is migrated on startup and then removed.
- Group key GC removes key material for non-active/deleted group chats.
- Group key rotation is triggered on membership changes (add/remove) and at group bootstrap.

### 2.4 Relay Envelope Integrity

- Relay envelopes are signed.
- Incoming relay envelopes are signature-verified before processing.
- Relay server validates Ed25519 signature on `/relay/store`.
- Relay server validates Ed25519 signature on `/relay/group/store`.
- Relay server validates Ed25519 signature on `/relay/group/members/update`.
- Relay server validates Ed25519 signature on `/relay/ack`.
- ACK is idempotent through a bounded durable tombstone and deletes only the
  matching message envelope, never an encrypted media blob.
- Relay server validates Ed25519 signatures on blob upload/finalize endpoints.
- Relay enforces server-side membership on group write endpoints.
- The client accepts incoming `groupMembers(action=add/remove)` mutations only
  from the owner already known in local group state or persisted group metadata;
  payload-declared owner/admin roles do not grant authority. Until signed admin
  roles exist, participant management is owner-only.
- Replay-window style checks are applied in reliable envelope handling.
- Direct fallback for group media carries only the encrypted blob reference and relay metadata; plaintext media is not sent through push or direct payloads.

### 2.5 Call/Signaling Security

- Bootstrap register can include signed auth proof.
- Signaling transport itself is not end-to-end encrypted at signaling layer.
- Media uses WebRTC transport security, currently forced to TURN routing policy in call setup.

### 2.6 Local Protection Against Unwanted Contacts

- The contacts-only privacy setting is enabled by default and is sent to the push server as part of the access-policy snapshot, so the server does not send push from Peer IDs outside local contacts.
- The local `blockedPeers` blacklist is synced to the push server through `/devices/access-policy`; the server drops push fanout from blocked Peer IDs before APNs/FCM, and outgoing calls to blocked Peer IDs do not start locally.
- Notification mute is separate durable local policy: schema-v2 access-policy
  carries independent direct/group message/call lists. It suppresses only the
  matching push fanout; it neither changes `blockedPeers` nor prevents encrypted
  relay message delivery.
- iOS Notification Service Extension and App Group are not part of the server-side push-blocking model.
- Blocking applies only to the specific `peerId`; because identity is decentralized, this is not a lifetime ban of a physical person.
- Push/relay/bootstrap servers do not receive private keys, session keys, or chat history for local blocking.

## 3. What We Can Claim Now

- Cryptographic primitives and verification hooks are present.
- Signed relay envelopes are enforced on receive path.
- Session-based encryption is enabled for reliable peer messaging in runtime config.
- Group control distribution for key/membership/invite runs over E2E session encryption.
- Group media payloads are encrypted before blob upload to relay.
- Group media direct fallback preserves the same E2E group-media payload; only metadata delivery changes after a server-side membership rejection.
- Contacts-only and local block are available as user-controlled protection against unsolicited push through server-side access-policy; local block also denies outgoing calls to blocked Peer IDs.
- New-client push registration binds `peerId` to `signingPub` through a verifiable v2 identity binding (`peerId = SHA-256(signingPub + identityNonce)`) without an extra request; push/moderation endpoints run soft migration by rejecting mismatches for already bound peer IDs while allowing legacy unbound clients.
- UGC reports are metadata-only: message text/media, chat history, contacts, private keys, and session keys are not sent to moderators. When a message is reported, the client immediately hides it locally for the reporter.
- The moderation HTTP contract is isolated in `ModerationApiClient`; regular push fanout/registration must not grow moderation endpoints, so the new service does not affect the push delivery path.
- Moderator UI shows aggregate lists for reported users and reporters, including total/direct/group counters; moderators manually set `warning` or `ban` without seeing message contents.
- The warning/ban model is ready for the App Store UGC flow: only moderators decide, push sends `moderation_policy` with `messageKey`, `reportCount`, and `reporterCount`, and the client renders fullscreen warning/ban text in the user's locale. Warning closes with `Continue`; banned peers first see an appeal screen, and after appeal submission the app is visible, but outgoing messages and calls stay locally blocked until `unban`. Settings shows the current warning/ban below Peer ID/QR in red. Push also directly blocks device registration, report creation, and signed fanout from a `banned` peer; relay/bootstrap do not need moderation DB access. `/moderation/status` returns `signedStatus` when `MODERATION_STATUS_SIGNING_PRIVATE_KEY` is configured; the client verifies it when `MODERATION_STATUS_SIGNING_PUBLIC_KEY` is set.

## 4. What We Cannot Claim Yet

- Complete anti-replay coverage across all control/signaling flows.
- Full ratcheting/session-key rotation strategy across all message classes.
- Strong formal guarantees around metadata privacy (server still sees routing metadata).
- Cryptographically confirmed cross-device enrollment: pairing no longer applies immediately and now requires a local approval step on the receiving device, but it still trusts possession of the QR/deep link and must be hardened with signed approval/handshake before production key sync across devices.

## 5. Required Next Steps

1. Extend replay protection to signaling/control envelopes where appropriate.
2. Add integration tests for invalid signature/replay/tampered payload cases.
3. Extend current group-key rotation to stronger ratcheting/session-key policy.
4. Reduce trust in centralized bootstrap path over time.
