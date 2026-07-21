# README

Last updated: 2026-07-21

## Project

PeerLink is a cross-platform Flutter messenger with a decentralized networking core.

Current design combines:
- WebRTC direct transport for peer sessions used by overlay traffic.
- TURN-routed WebRTC media for audio/video calls (TURN-only policy).
- Relay-based store-and-forward message delivery over HTTP.
- Application-level cryptography for identity/signatures/sessions.

## Current Status

- `flutter analyze` passes for current codebase.
- UI: Contacts / Chats / Calls / Settings is working.
- Chat UI now supports emoji-only message presentation:
  - messages containing only `1-3` emoji are rendered in a dedicated large format,
  - emoji-only bubbles are shown without the normal message frame/background,
  - large emoji appearance uses a lightweight entrance animation.
- Persistent storage is active:
  - secure storage for settings/identity metadata,
  - Drift/SQLite for chat DB,
  - filesystem for media files.
  - storage cleanup only removes categories the user explicitly selects; heuristic orphan-media cleanup has been removed because it is unsafe for legacy media recovery paths.
- Bootstrap signaling over WebSocket is used for transport/call signaling.
- Runtime keeps multiple bootstrap WebSocket connections alive simultaneously.
- Outgoing signaling (`call_invite`, `offer`, `answer`, `ice`) is sent to every bootstrap channel where the target peer is visible; if the peer is not visible anywhere, fallback is all connected bootstrap channels.
- Bootstrap presence baseline is enabled: periodic peer snapshots drive online/offline state and local `last seen`.
- Personal avatars:
  - local avatar is set in `Settings` (tap avatar circle near `Peer ID`, choose camera/gallery, crop in circular viewport),
  - avatars are rendered in `Contacts`, `Chats`, and in `Chat` header,
  - cross-device sync uses control message `kind=profileAvatar` with relay blob payload reference (`blobId` in announce),
  - contact avatars keep a local embedded backup, so the last known avatar survives app restart until a fresher network update arrives.
- Group avatars:
  - group owner avatar updates are distributed as service `groupMembers` update (`action=avatar`) with relay blob reference,
  - avatar updates are not sent as normal chat/media messages (older clients should not render them as chat content),
  - group avatar local path is persisted in group meta and restored after app restart.
- Bootstrap server contract for presence:
  - supports `peers_request` and returns only currently online `peerId`s,
  - includes server-side `lastSeenMs` data in peers snapshot payload,
  - emits push `presence_update` frames for `online/offline` transitions.
- Self-hosted deployment from Settings:
  - deploy progress is stage-based (`1/14 ... 14/14`) with reduced noisy logs,
  - stage completion marker is `Deployment complete!`, then connection checks run,
  - before deploy, the dialog shows a preview of the final bootstrap/relay/turn endpoints that will be configured from the entered host,
  - checks report explicit statuses: `Test connection bootstrap (ok/fail)`, `relay (ok/fail)`, `turn (ok/fail)`,
  - checks now retry for a short warm-up window after container startup, so fresh installs do not fail on transient bootstrap/relay/turn readiness,
  - a single host contract is used for both domains and IPs: `wss://PUBLIC_HOST:443`, `https://PUBLIC_HOST:444`, `turn:PUBLIC_HOST:3478?transport=udp`, `turn:PUBLIC_HOST:3478?transport=tcp`,
  - legacy fallback endpoints (`/signal`, `:3000`, `:4000`) are no longer used,
  - bootstrap and relay runtime now accept host-matching self-signed certificates for self-hosted endpoints, not only IP-based ones,
  - working topology is `wss://PUBLIC_HOST:443` (signal via HAProxy), `https://PUBLIC_HOST:444` (relay via HAProxy), while TURN goes directly to `coturn`,
  - recommended TURN entries are `turn:PUBLIC_HOST:3478?transport=udp` and `turn:PUBLIC_HOST:3478?transport=tcp`.
- iOS ATS baseline:
  - global bypass `NSAllowsArbitraryLoads` in `ios/Runner/Info.plist` is disabled,
  - manual verification confirmed working self-hosted connectivity and message/call flows over both domain-based and IP-based server endpoints without enabling `NSAllowsArbitraryLoads`.
- Settings now use aggregated bootstrap/relay/turn cards:
  - the main screen shows compact available/unavailable summaries,
  - tapping a card opens a dedicated list screen for that server group,
  - add actions for bootstrap/relay/turn were moved to those dedicated list screens,
  - server rows remain health-sorted and support swipe-to-delete with confirmation.
- Invite and server-configuration links:
  - invites use `peerlink://invite?payload=...` for QR/direct-open and `https://simplegear.org/invite?payload=...` for sharing,
  - server configuration sharing uses `https://simplegear.org/config?payload=...`,
  - both link types include only currently available server configuration,
  - app-side deep links merge imported servers into existing settings; config links merge directly, while QR/manual config import still offers merge/replace.
- Android/macOS native runners forward `peerlink://invite|pair|config|call` and supported `https://simplegear.org/...` links into Flutter; macOS keeps pending links during cold start so website-to-app transitions are not lost.
- Settings now include a `Storage` section:
  - top-level block shows `Total app storage`,
  - the whole card now opens per-category storage breakdown with a chevron, matching the server-card navigation pattern,
  - each category supports swipe-to-delete with confirmation and an inline warning about what will be erased,
  - the `Logs` category includes the current `app.log` and rotated log archives,
  - the log file now supports two modes from Settings: `Errors only` and `Verbose`,
  - verbose mode is intended for diagnostics and now includes detailed incoming group/message relay traces and relay-media restore timing,
  - noisy UI rebuild spam was removed from the file log; `UiApp.build` is no longer written on every rebuild,
  - `Clear logs` removes both the current log file and rotated archives.
- Reply-to-message navigation in chat is more stable:
  - tapping a reply now resolves the target message position from local chat history,
  - older pages are loaded until the referenced message is present in memory,
  - the chat list now probes and settles layout more reliably before scrolling/highlighting the original message.
- Relay delivery now prefers live relay servers:
  - fast health probes are used before runtime operations,
  - text/media paths use only a small live working set (up to 3 relays),
  - unavailable relays are skipped when healthy ones are available, helping reduce visible delivery delays.
- Personal media delivery now also uses relay blob transport:
  - direct chat media is uploaded once into relay blob storage,
  - chat delivery uses encrypted `direct_blob_ref` metadata instead of the legacy direct `fileMeta/fileChunk` send path,
  - direct media receive now also resolves only through `direct_blob_ref` and relay blob download,
  - direct blob restore now uses retry/timeout protection during download,
  - failed incoming media downloads schedule a bounded delayed auto-retry after transient network switches.
- Relay polling and push/local notifications are integrated.
  - recovery of group/direct events does not depend only on opening the app from a push notification: runtime also calls `pollRelay()` on startup, on app resume, and after connectivity restoration.
  - foreground message/group push events now also trigger `pollRelay()` without forcing navigation to the chats tab.
  - opened push handling can poll relay hints from the push payload before running a full relay poll.
  - incoming relay group envelopes preserve `groupId` up to `ChatService`, so group payload is routed into the group chat instead of the sender's direct chat.
  - incoming group messages now also preserve the real sender separately as `senderPeerId`, so group inbound handling does not confuse the group target with the sender peer.
- Client-side push API is restricted to `/devices/register`, `/devices/unregister`, and `/events/push`; other paths are rejected in `PushApiClient`.
- Push event construction is split between `PushEventFactory`, `PushRuntimeMetadataBuilder`, and `PushEventService`; `PushApiClient` stays the low-level signed HTTP transport.
- App badge state is synchronized through `AppBadgeService`, which persists unread-message and missed-call counts.
- `push.js` bearer token is read only from `--dart-define=PUSH_API_TOKEN=...` (not from UI/settings).
- `PUSH_API_TOKEN` cannot be changed for an already built app; a rebuild with a new `--dart-define` is required.

### Push API Contract

- Base URL is configured via `PUSH_SERVER_URL`.
- Authorization: `Authorization: Bearer <PUSH_API_TOKEN>`.
- All write requests are Ed25519-signed and include:
  - `id` (unique request id),
  - `from` (sender id),
  - `ts` (unix ms),
  - `sig` (base64 signature),
  - `signingPub` (base64 signing public key).
- Server uses anti-replay by `id` (TTL-based), so duplicate request ids are rejected.

#### `push.js` Server ENV (VoIP + FCM)

```env
PORT=4500
PUSH_API_TOKEN=__SET_STRONG_TOKEN__

FCM_PROJECT_ID=__YOUR_FIREBASE_PROJECT_ID__
FCM_CREDENTIALS_JSON=__ONE_LINE_SERVICE_ACCOUNT_JSON__

APNS_TEAM_ID=__APPLE_TEAM_ID__
APNS_KEY_ID=__APPLE_KEY_ID__
APNS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
APNS_VOIP_TOPIC=<bundle_id>.voip
APNS_USE_SANDBOX=true
```

- `APNS_VOIP_TOPIC` must be a full topic and must end with `.voip`.
- For production/TestFlight builds, set `APNS_USE_SANDBOX=false`.

#### `POST /devices/register`

- Purpose: register (or refresh) a device push token.
- Payload:
  - `id`, `from`, `ts`, `sig`, `signingPub`,
  - `userId`, `deviceId`, `messageToken`, `messageProvider`, `platform`, `appVersion`.
  - Optional `voipToken` for iOS/macOS.
- Response: `{ ok: true, device: ... }`.

#### `POST /devices/unregister`

- Purpose: deactivate a device push token.
- Payload:
  - `id`, `from`, `ts`, `sig`, `signingPub`,
  - `userId`, `deviceId`, `token`.
- Response: `{ ok: true|false }`.

#### `POST /events/push`

- Purpose: universal fanout endpoint for all app push events.
- Payload:
  - `id`, `from`, `ts`, `sig`, `signingPub`,
  - `senderUserId`,
  - `recipientUserIds` (`string[]`, required routing field),
  - `payload` (`object`, arbitrary app-defined JSON passed through unchanged),
  - `notification` (optional): `title`, `body`,
  - `delivery` (optional): `standard`, `voip`.
- The server does not interpret business semantics inside `payload`; it uses only `recipientUserIds` to find devices and `delivery` to choose the transport channel.
- Runtime metadata such as `servers`, `priority_servers`, `relay`, `accountMembershipUpdate`, or `groupMembers` must live inside `payload`.
- Response: `{ ok, deduped, recipients, devices, sent, failed }`.

#### FCM Payload Recommendation

- For reliable iOS UX, send both:
  - `notification.title`,
  - `notification.body`,
  - `payload` (technical app fields such as `type`, `groupId`, `directPeerId`, `senderUserId`, `relay`, `servers`).
- In `background/killed` states the message is displayed as a system `alert`; the client cannot rewrite the text before display, so the OS renders exactly `notification.title/body` as composed by the sender and relay-forwarded by the server.
- Payload-only sends may not produce a visible local notification in background flows.
- Exception: `payload.type=account_membership_update` is handled silently (no visible notification). The client applies the update immediately and falls back to pending queue `account_membership_updates.v1` on failure.
- `payload.type=group_members_update` is also handled silently (no visible notification) and is applied immediately as a `groupMembers` control update.

#### API Errors

- `401 unauthorized` — bearer token mismatch.
- `401 invalid signature` — payload signature invalid.
- `401 signature_timestamp_skew` — request timestamp outside allowed skew.
- `409 duplicate request id` — anti-replay duplicate.
- `400 invalid_payload` / `missing ...` — schema validation error.
- `502 push_send_failed` — upstream FCM send failure.
- Unified messaging/blob API is active in the core entry layer:
  - `NodeFacade.sendPayload(...)` for direct/group chat delivery,
  - `NodeFacade.uploadBlob(...)` for direct/group relay blob upload,
  - `NodeFacade.downloadBlob(...)` for blob restore regardless of source scope.
- Identity model uses stable `peerId` (v2). Legacy peer id is preserved for compatibility metadata.
- Group text/media delivery is unified through relay group flow.
- Group blob transport is active, including chunked upload for large payloads.
- Group media encryption payload switched to compact binary format (`PLG2`) with legacy decode fallback.
- Heavy group media crypto (large payloads) runs in background isolate to avoid UI freezes.
- Target account/device model is fixed as follows:
  - other users should identify a person by `Account ID`, not by `deviceId` / `peerId`,
  - every freshly installed device generates its own stable `deviceId` and its own standalone local account on first launch,
  - device pairing does not migrate the user account; it switches the device from its local standalone account into an existing trusted account after explicit approval,
  - on pairing confirmation, the UI must warn that the current local `Account ID` will be replaced by the target account,
  - on revoke, the device must leave the shared account and return to its original first-launch standalone account,
  - `deviceId` must remain stable across pairing and revoke; only the active account membership changes.

> This project is authored by AI agents; I act only as a coordinator and development lead. No character of code was written by hand.

> Russian documentation is available in `README_RU.md`.

## What Is Implemented

- Dependency composition via `NetworkDependencies`.
- Identity derivation:
  - stable `peerId` (v2) = hash(signing public key + installation id).
- Post-start coordination via `AppBootstrapCoordinator`.
- Public core API via `NodeFacade`.
- UI decomposition completed for chat flow (`ChatScreen*` and `ChatController*` split into focused files).
- Screen layout template standardized to `*_screen.dart` + `*_view.dart` + `*_styles.dart`.
- Chat UI helpers extracted to dedicated modules (`chat_screen_helpers`, `chat_screen_unread_divider`).
- Reply navigation now uses local history-aware message lookup plus targeted page loading, improving jumps to much older referenced messages.
- Added `AvatarService` as a single avatar source for UI, including local cache and sync via relay blob + control announce.
- Added self-hosted deployment runtime service (`SelfHostedDeployService`) with staged progress parsing and endpoint verification.
- Added shared `ServerAvailabilityProvider` contract for server-health services, so bootstrap/relay/turn probing can be orchestrated uniformly in runtime.
- Added shared `ServerHealthCoordinator`, which starts the bootstrap/relay/turn health layer after app bootstrap and exposes one runtime source of availability data to Settings.
- `HttpRelayClient` and `TurnAllocator` now consult the coordinator-backed relay/turn health snapshots first, while keeping runtime-local fallback behavior when shared health is still unknown.
- The shared health layer now refreshes on app resume and on connectivity changes, so relay/turn/bootstrap availability recovers faster after foreground return or network switches.
- Before critical relay operations, the client now selectively refreshes only the current relay shortlist when shared health is stale, instead of reprobeing the whole configured relay set.
- Before building TURN-based call configs, the runtime now selectively refreshes only the current TURN shortlist when shared TURN health is stale, so `rtcConfig` uses fresher TURN candidates without reprobeing the full TURN list.
- `MeshNode` orchestration for signaling, peer sessions, relay configuration.
- Overlay routing + dedup cache.
- Relay client uses a bounded, health-aware pool plus quorum strategy:
  - active relay usage is capped,
  - runtime operations choose only live relays first and use at most 3 servers,
  - writes and ack use quorum,
  - fetch aggregates across the working relay set with per-relay cursors,
  - selected relay operations run in parallel to avoid cumulative delays when some configured servers are unavailable.
- Reliable envelope parsing/validation and relay polling pipeline.
- Relay signatures are validated both client-side (receive path) and server-side (`/relay/store`, `/relay/group/store`, `/relay/group/members/update`, `/relay/ack`, blob upload/finalize endpoints).
- Relay enforces server-side group membership for group fan-out and group blob upload paths.
- Group membership changes are synchronized to relay through `/relay/group/members/update`.
- Group key rotation is active on membership changes (add/remove participants).
- Relay blob APIs are integrated:
  - `/relay/blob/upload`,
  - `/relay/blob/:blobId`,
  - `/relay/blob/upload/chunk`,
  - `/relay/blob/upload/complete`,
  - `/relay/group/members/update`.
- Large blob uploads use chunked mode first, then fallback to single upload when chunk endpoints are unavailable.
- Relay fetch path includes transient GET retry/backoff for unstable connections (`Connection closed ...` cases).
- Media/blob receive path is optimized to avoid stalling behind dead relays when at least one live relay is available.
- Call stack:
  - dedicated `CallService`,
  - `AudioCallPeer`,
  - extracted `CallNegotiationController`,
  - extracted `CallVideoController` + `CallVideoState`.
- Calls currently force TURN mode for stability (all network types).
- In self-hosted mode, `signal/relay` terminate on HAProxy, while TURN traffic is handled directly by `coturn` without HAProxy TCP proxying.

## Current Limits

- Signaling is still centralized by bootstrap server contract, although runtime now keeps multiple bootstrap WebSocket channels alive simultaneously.
- DHT layer is minimal (`KademliaProtocol` pass-through, no full lookup workflow).
- Messaging encryption is wired, but runtime is currently configured with `enableEncryption: false` in `NetworkDependencies` for compatibility/debugging.
- Message transport failover `Direct -> TURN -> Relay` is not active in `PeerSession` now; current `PeerSession` is direct-only.
- Contact and delivery model is still partially device-centric:
  - parts of messaging/call/contact flow still resolve peers by device-level ids,
  - the final target model is `Account ID`-first routing, where account membership resolves to currently active devices internally.

## Tech Stack

- Flutter / Dart (`^3.11.0`)
- `flutter_webrtc`
- `cryptography`, `crypto`
- `drift`, `sqlite3_flutter_libs`
- `flutter_secure_storage`
- `provider`
- `connectivity_plus`
- `firebase_core`, `firebase_messaging`, `flutter_local_notifications`, `flutter_app_badger`

## High-Level Structure

```text
lib/
  main.dart
  core/
    calls/
    dht/
    discovery/
    firebase/
    messaging/
    node/
    notification/
    overlay/
    relay/
    runtime/
    security/
    signaling/
    transport/
    turn/
  ui/
    models/
    screens/
    state/
    theme/
    widgets/
```

- `lib/core/signaling/`:
  - `bootstrap_signaling_service.dart` — bootstrap signaling runtime facade
  - `bootstrap_signaling_runtime_state.dart` — shared mutable signaling runtime state
  - `bootstrap_signaling_session_controller.dart` — `setServer`/connect/register flow
  - `bootstrap_signaling_connectivity_controller.dart` — connectivity watch and fast-reconnect policy
  - `bootstrap_signaling_reconnect_controller.dart` — retry/backoff/circuit-breaker and reconnect trace
  - `bootstrap_signaling_protocol_controller.dart` — register/signal/ping/peers flow, retry queue, inbound frame handling
  - `bootstrap_signaling_models.dart` — shared signaling value objects
  - `multi_bootstrap_signaling_service.dart` — multi-bootstrap channel aggregator

## Setup

### Prerequisites

1. **Flutter SDK**:
   - Install from https://flutter.dev/docs/get-started/install

2. **Firebase Configuration** (for Android):
   - Obtain `google-services.json` from your Firebase project
   - Place in `android/app/` directory

3. **Firebase Configuration** (for iOS):
   - Obtain `GoogleService-Info.plist` from your Firebase project
   - Place in `ios/Runner/` directory

### Run

```bash
flutter pub get
flutter analyze
flutter run
```

For push integration, pass build-time defines:

```bash
flutter run \
  --dart-define=PUSH_SERVER_URL=https://your-push-host:4500 \
  --dart-define=PUSH_API_TOKEN=your_secret_token
```

`.vscode/launch.json` already includes `toolArgs` templates with placeholders:
- `__SET_PUSH_SERVER_URL__`
- `__SET_PUSH_API_TOKEN__`

## Documentation

### English
- `RELEASE_FLOW.md`
- `RELEASE_CHECKLIST.md`
- `CHANGELOG.md`
- `VERSIONING.md`
- `ARCHITECTURE.md`
- `NETWORK_FLOW.md`
- `SECURITY_MODEL.md`
- `BOOTSTRAP_SIGNALING_PROTOCOL.md`
- `RELAY_PROTOCOL.md`
- `GROUP_BLOB_V1_SPEC.md`
- `TASKS.md`
- `AI_CONTEXT.md`

### Русский / Russian
- `RELEASE_CHECKLIST_RU.md`
- `CHANGELOG_RU.md`
- `VERSIONING_RU.md`
- `ARCHITECTURE_RU.md`
- `NETWORK_FLOW_RU.md`
- `SECURITY_MODEL_RU.md`
- `BOOTSTRAP_SIGNALING_PROTOCOL_RU.md`
- `RELAY_PROTOCOL_RU.md`
- `GROUP_BLOB_V1_SPEC_RU.md`
- `TASKS_RU.md`
- `AI_CONTEXT_RU.md`
- `README_RU.md`

## Publication
- `PUBLICATION_CHECKLIST.md` - Status for public release
- `LICENSE` - MIT License

## Versioning

- App versioning is managed only from `pubspec.yaml`.
- Use `dart run tool/bump_version.dart <patch|minor|major|build>` for standard version bumps.
- For routine commits on `dev`, use `tool/dev_commit.sh "<message>"`.
- If the commit message contains `[patch]`, `[minor]`, `[major]`, or `[build]`, `tool/dev_commit.sh` bumps the version locally in `dev`, updates `CHANGELOG.md` and `CHANGELOG_RU.md`, and commits the prepared versioned state together with the code changes.
- If you intentionally need a temporary development build bump on `dev` without changing the semantic version, use `tool/dev_commit.sh --bump-build "<message>"`.
- Use `tool/prepare_release.sh <patch|minor|major|build>` to bump version and create changelog stubs together.
- `tool/prepare_release.sh` now pre-fills new changelog entries with an automatic draft from git history, so release prep starts from a meaningful summary instead of empty `TODO` sections.
- GitHub Actions workflow `.github/workflows/release-version.yml` can prepare the same release flow through `workflow_dispatch`.
- GitHub Actions workflow `.github/workflows/app-release-build.yml` builds Android/iOS artifacts and publishes GitHub Release notes after pushing tag `app-v<version>`.
- GitHub Actions workflow `.github/workflows/branch-release.yml` is the branch-driven automatic path:
  - push to `main` after PR merge: use the already prepared version from `dev`, render release notes, analyze, mirror
  - push to `app` after PR merge: same flow plus Android internal deploy and iOS TestFlight upload
- `tool/render_release_notes.sh <version> --lang en|ru` now supports both English and Russian release notes, prefers the matching changelog section, and automatically falls back to a git-history draft when the changelog entry is still a placeholder.
- Release workflows render the final files into `build/release_notes/`, upload both rendered variants as artifacts, and append both to the GitHub Actions job summary with explicit `template source -> rendered output` hints.
- Tag-based GitHub Releases also attach `build/release_notes/release_notes_ru.md` as a release asset and include a link to it directly in the published release body.
- Details are documented in `VERSIONING.md`.
