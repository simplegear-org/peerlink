# SECURITY_MODEL

Last updated: 2026-04-12

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

### 2.2 Session Crypto

- `SessionManager` + `SessionCrypto` implement handshake and payload encryption APIs.
- Reliable messaging path is integrated with session APIs.
- Runtime `NetworkDependencies` config enables reliable messaging encryption (`enableEncryption: true`).
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
- Relay server validates Ed25519 signatures on blob upload/finalize endpoints.
- Relay enforces server-side membership on group write endpoints.
- Replay-window style checks are applied in reliable envelope handling.

### 2.5 Call/Signaling Security

- Bootstrap register can include signed auth proof.
- Signaling transport itself is not end-to-end encrypted at signaling layer.
- Media uses WebRTC transport security, currently forced to TURN routing policy in call setup.

## 3. What We Can Claim Now

- Cryptographic primitives and verification hooks are present.
- Signed relay envelopes are enforced on receive path.
- Session-based encryption is enabled for reliable peer messaging in runtime config.
- Group control distribution for key/membership/invite runs over E2E session encryption.
- Group media payloads are encrypted before blob upload to relay.

## 4. What We Cannot Claim Yet

- Complete anti-replay coverage across all control/signaling flows.
- Full ratcheting/session-key rotation strategy across all message classes.
- Strong formal guarantees around metadata privacy (server still sees routing metadata).

## 5. Required Next Steps

1. Extend replay protection to signaling/control envelopes where appropriate.
2. Add integration tests for invalid signature/replay/tampered payload cases.
3. Extend current group-key rotation to stronger ratcheting/session-key policy.
4. Reduce trust in centralized bootstrap path over time.
