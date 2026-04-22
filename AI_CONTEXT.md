# AI_CONTEXT

Last updated: 2026-04-22

This file defines the guardrails for AI-assisted development in PeerLink.

## 1. Project Goal

Build a production-grade decentralized messenger while preserving current working behavior.

## 2. Truth Rule

Always separate:
- AS-IS (what code does now),
- NEXT (what is planned).

Do not describe planned architecture as already shipped.

## 3. Current Runtime Truth

- Bootstrap signaling is still centralized and required.
- Runtime bootstrap is multi-channel: multiple WebSocket bootstrap connections are kept alive simultaneously.
- Outgoing signaling should target every bootstrap channel where the peer is visible, with fallback to all connected bootstrap channels.
- Relay-based message delivery is active.
- Core entrypoints for runtime messaging/blob operations are unified: `sendPayload(...)`, `uploadBlob(...)`, `downloadBlob(...)`.
- Personal media delivery uses relay blob storage plus encrypted direct blob-reference metadata.
- Group text/media delivery uses relay group path with blob indirection for payloads.
- Direct personal media receive now uses only encrypted `direct_blob_ref` plus relay blob download. Legacy `fileMeta/fileChunk` receive has been removed.
- Large group payload upload supports chunked relay blob upload with fallback to single-shot upload.
- Group media encrypted bytes use compact binary `PLG2` format with legacy decode fallback.
- Large group media crypto is moved to background isolate to avoid UI stalls.
- Relay fetch GET path uses transient retry/backoff on connection-drop errors.
- Relay server enforces membership for group write endpoints; owner syncs membership via `/relay/group/members/update`.
- Group key rotates on membership changes (add/remove participants).
- Relay runtime uses a bounded active pool + quorum instead of fan-out to every configured relay.
- Relay runtime preselects only live relay servers for runtime operations, with a hard cap of 3 selected relays.
- If at least one healthy relay is available, unhealthy relays must not remain in the active runtime path for text/media delivery.
- Relay control writes, fetch, and blob fetch are parallelized across the selected relays to reduce latency when part of the relay list is unavailable.
- Runtime reliable-message encryption is enabled by config (`enableEncryption: true`).
- Calls are currently TURN-only for all network types.
- Self-hosted deployment flow exists in Settings with staged progress (`1/14 ... 14/14`) and post-deploy service checks.
- Self-hosted endpoints are fixed TLS addresses: `wss://<ip>:443` for bootstrap and `https://<ip>:444` for relay.
- Runtime allows self-signed certs for IP-hosted bootstrap/relay TLS endpoints.
- In self-hosted topology, HAProxy is used only for `signal`/`relay`; TURN/TURNS must be served directly by `coturn`, not proxied through HAProxy.
- Self-hosted TURN configuration must accept both `turn:` and `turns:` URLs.
- Settings server lists now expose availability state, sort by state, and use swipe-to-delete with confirmation.
- On the main Settings screen, bootstrap/relay/turn are represented as aggregated cards; add actions live on the dedicated list screens for each server group.
- The `Storage` block in Settings opens by tapping the whole card with a chevron, without a separate `Details` button.
- Contact avatars must survive app restart via local backup restoration before fresh network avatar sync arrives.
- Incoming media restore must tolerate short network switches: direct blob download uses retry/timeout, and failed downloads schedule a bounded automatic retry.
- Server-health probing remains type-specific per service, but runtime now has a shared `ServerAvailabilityProvider` contract for bootstrap/relay/turn providers.
- `ServerHealthCoordinator` is the shared runtime orchestration layer for these providers; Settings should consume coordinator-backed availability instead of creating duplicate probe loops.
- Relay and TURN runtime consumers now prefer coordinator-backed health snapshots too, so server selection and Settings derive from the same shared availability picture.
- The shared health coordinator also refreshes on app resume and on connectivity changes, so runtime server state is not stale after foreground return or network switching.
- Relay runtime now performs a selective shared-health refresh for only the current relay shortlist before critical send/blob/fetch work when the shared relay snapshot is stale.
- TURN runtime now also performs a selective shared-health refresh for only the current TURN shortlist before assembling TURN-based `rtcConfig`, so call setup uses fresher TURN candidates.
- DHT is present but still minimal.

## 4. Change Rules

When changing code:
1. Keep UI boundary through `NodeFacade`.
2. Keep dependency composition inside runtime wiring (`NetworkDependencies`).
3. Preserve lifecycle correctness (timers/subscriptions/dispose paths).
4. Keep call logic modular (prefer controller/state extraction from large classes).
5. Update docs in the same change when behavior changes.
6. Add/adjust tests for critical networking/security flows.
7. Treat `pubspec.yaml` as the single source of truth for app versioning; do not manually diverge Android/iOS version metadata.

## 5. Non-Functional Baseline

- No silent crash loops on network instability.
- No leaked timers/stream subscriptions.
- No silent crypto downgrade in production paths.

## 6. Under Uncertainty

- Prefer minimal safe changes.
- Validate assumptions against code before writing docs.
- If docs conflict with code, code is source of truth and docs must be updated.
