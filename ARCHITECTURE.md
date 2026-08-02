# ARCHITECTURE

Last updated: 2026-07-31

## 1. Purpose

PeerLink is a Flutter messenger with a decentralized core. In practice, the project uses a hybrid architecture:
- decentralized peer transport/overlay components,
- centralized bootstrap signaling for session setup,
- relay-backed message delivery.

## 2. AS-IS Snapshot

Working now:
- DI assembly via `NetworkDependencies.create()`.
- App startup orchestration via `AppBootstrapCoordinator`.
- `NodeFacade` as UI entrypoint to core.
- `MeshNode` as runtime orchestrator.
- `PushApiClient` for signed requests to `push.js` (`/devices/register`, `/devices/unregister`, `/events/push`), with higher-level event construction delegated to `PushEventFactory`, `PushRuntimeMetadataBuilder`, and `PushEventService`.
- The FCM runtime module in `lib/core/firebase` is decomposed into:
  - `FirebaseMessagingService` as the coordinator and external API,
  - `FirebasePushTokenLifecycle` for permission/token lifecycle and APNS/FCM sync,
  - `FirebasePushInboundService` for inbound orchestration,
  - `FirebasePushPayloadProcessor` for push payload processing, server-config merge, and account/group update handling,
  - `FirebasePushPayloadParsers`, `FirebasePushServerStorageMerger`, `FirebasePushServerUpdateParser`, and `FirebasePushLogFormatter` for payload normalization, server-config merge/update parsing, and diagnostics formatting,
  - `FirebasePushPresentationHandler` for foreground/open/native-fallback handling and local notifications,
  - `FirebasePushCallbackRegistry` / `firebase_push_models.dart` for callback registry and shared push models.
- The internal push/call payload model is unified through `FirebasePushPayload`: the UI open path, FCM foreground/open/native-fallback handling, and the iOS CallKit path should not keep parallel call-payload DTOs.
- `AppBadgeService` owns app icon badge state and combines unread messages with missed-call counts before syncing the platform badge.
- `AccountIdentity` above device identity: `accountId`, `displayName`, device list, and a `peerlink://pair` QR/deep link for pairing a second device without changing the current device-based routing.
- Overlay router + message dedup cache.
- HTTP relay client with live-relay preselection, bounded active pool, quorum write/quorum ack, and status tracking.
- Reliable messaging envelopes, relay poll loop, ack flow.
- Group chat delivery via relay group envelopes.
- Personal media delivery via relay blob + encrypted direct blob-reference metadata.
- Group media and group text blob transport path (single upload + metadata fan-out).
- Incoming relay-media restore uses persisted retry state and can continue on chat reopen, app resume, and connectivity restoration; Android foreground service is not used for this.
- Server-side group membership enforcement in relay write path.
- Group membership sync via `/relay/group/members/update`.
- Group key rotation on membership changes.
- Chunked blob upload support in relay protocol (`chunk` + `complete`) with client fallback.
- Group media encrypted bytes use compact binary `PLG2` payload format (legacy decode path remains).
- Group media crypto for large payloads is offloaded from UI isolate to background isolate.
- Relay fetch GET path includes transient retry/backoff on connection-drop errors, including premature connection close before HTTP headers.
- Relay runtime paths now prefer only live relay servers, capped at 3 selected servers for message/media operations.
- Relay control writes, fetch, and blob fetch are parallelized across selected relays to avoid cumulative timeout delays from dead servers.
- Blob fetch expands beyond the current live shortlist after all shortlist candidates return `404`, before declaring a blob missing.
- Call stack is decomposed into bounded controllers/orchestrators for peer bootstrap, connection, negotiation, media readiness, video signaling/transceivers/quality, remote control, terminal lifecycle, runtime tracking, epoch timers, and diagnostics.
- TURN allocator and TURN server configuration from settings.

Current constraints:
- Bootstrap signaling remains centralized by contract, but runtime now keeps multiple bootstrap WebSocket channels alive through an aggregator.
- DHT layer is skeletal (`KademliaProtocol` pass-through API).
- Runtime reliable-message encryption is enabled by config (`enableEncryption: true`).
- `PeerSession` currently manages only direct transport mode.

## 3. Current Dependency Graph

```text
UI
  -> NodeFacade
    -> MeshNode
      -> Identity / Session / Signature
      -> TransportManager
        -> PeerSession
          -> WebRtcTransport (direct)
      -> OverlayRouter
      -> RelayClient (HTTP)
      -> PushApiClient (HTTP)
      -> FirebaseMessagingService
      -> ReliableMessagingService
      -> ChatService
      -> CallService
      -> BootstrapSignalingService
      -> TurnAllocator
      -> RoutingTable / RecordStore / DhtTransport / KademliaProtocol
      -> NetworkEventBus
```

## 4. Layer Boundaries

### 4.1 UI (`lib/ui`)

- Screens, widgets, state controllers.
- Uses `NodeFacade` only.
- Runtime localization lives in `lib/ui/localization`: `AppLocaleController` persists the selected language in settings storage, `AppStrings` provides the lookup/formatting API and Flutter localization delegates for `MaterialApp`, and per-language dictionaries live in `lib/ui/localization/dictionaries`.
- Screen composition pattern is standardized:
  - `*_screen.dart` for orchestration/state wiring,
  - `*_view.dart` for layout widgets,
  - `*_styles.dart` for design constants.
- Chat modules are split into focused units (`chat_screen_view`, `chat_screen_helpers`, `chat_screen_unread_divider`, `chat_screen_media_actions`, `chat_screen_app_bar`, `chat_screen_message_list`, `chat_screen_audio_actions`, `chat_screen_actions`, `chat_screen_mime_type`, `chat_screen_scroll_coordinator`, `chat_screen_unread_target_resolver`, `chat_screen_lifecycle`, `chat_screen_viewport_state`, `chat_screen_presenter`, `chat_screen_back_swipe_coordinator`, `chat_screen_composer_coordinator`, `chat_controller_parts`, `chat_controller_media`).
- `ChatScreen` now keeps only orchestration/state wiring; the AppBar, message-list overlays, voice-recording flow, dialog/action flow, lifecycle wiring, viewport state, presentation logic, composer/send/reply flow, and back-swipe gesture are moved into dedicated screen modules.
- Message forwarding lives in `ChatForwardService`; `ChatScreen` only opens the target sheet and calls the service through `sendMessage`/`sendFile` callbacks.
- `ChatController` decomposition is extended through dedicated services and bounded coordinators/handlers for repository access, summary, file queue/send/progress/transfer, direct lifecycle, direct/group inbound/outbound, group control/content/crypto, cleanup, history load, message mutation/send, incoming media restore, outgoing relay-media resume, account payloads, reply metadata, contacts, read state, and group flow; the controller should stay an orchestration/facade layer.
- Base chat-state dependency assembly lives in `chat_controller_dependencies.dart`; new controller-adjacent coordinators should be created through `chat_controller_coordinator_factory.dart`, while callback-heavy wiring remains explicit.
- Account pairing/membership payload decoding lives in `chat_account_payload_decoder.dart`, and reply metadata creation lives in `chat_reply_metadata_resolver.dart`; `ChatController` must not absorb these responsibilities back into its body.
- Group crypto is moved out of `ChatController` into `lib/core/security/group_message_crypto_service.dart` next to `group_key_service.dart`; UI/state code must not keep its own pack/unpack or encrypt/decrypt implementation for group payloads.
- Group `memberPeerIds` must be kept in canonical form (`trim + unique + sort`) in both runtime state and persisted group meta, so equivalent membership sets do not create fake persistence churn due only to ordering.
- Local group avatar path should be committed only after successful `groupMembers(action=avatar)` broadcast; a failed fan-out must not leave the local group state partially updated with a new avatar path.
- Top-level Contacts/Chats/Settings pages use compact AppBar-led layouts without descriptive page-copy headers; contact, chat, and call-history rows share the same tight spacing/internal-padding constants via `CompactCardTileStyles`.
- Contact rows show avatar, one display label (contact name or short peer id), and last-seen text; chat rows show avatar, chat title, last message, and unread badge without last-seen text.
- Contact rows expose a long-press action menu for renaming the saved display name while preserving the peer ID.
- The Contacts invite action produces a `peerlink://invite?payload=...` QR/direct-open link; shared text includes the direct app link `peerlink://invite?payload=...` plus fallback `https://simplegear.org/invite?payload=...`. Both include the local Peer ID plus available server configuration, and incoming invite links merge server settings before adding/updating the contact. Self-invite links still merge server config, then skip contact creation.
- The Settings `Share configuration` action produces text with direct app link `peerlink://config?payload=...` plus fallback `https://simplegear.org/config?payload=...`, containing only currently available server config. App-side config deep links merge `bootstrap/relay/turn/push` directly, while QR scan/import still uses the explicit import-mode dialog.
- macOS deep-link delivery is native: `MainFlutterWindow` configures `DeepLinkChannel` with the created `FlutterViewController`, `AppDelegate` registers URL handlers early, and both custom scheme (`peerlink://invite|pair|config|call`) and supported web links are forwarded to Flutter. Android handles the same custom/web link families through the native runner and app links.
- The Settings `Account and devices` block shows the current `accountId`, known device count, a `peerlink://pair` QR for pairing another owned device, and a scan flow for importing a pairing payload.
- Call history rows use compact internal padding, smaller status-icon blocks, and tight separators between rows.
- Shared typography is centralized through `AppTheme.fontFamily` and applied to app text styles, AppBar, NavigationBar, inputs, dialogs, and snackbars.
- Chat opening scroll positioning is single-flight: `ChatScreen` schedules only one initial bottom/unread viewport pass at a time to avoid duplicate startup jumps, and initial bottom mode keeps settling across several frames while restored media can still change list height.
- First-unread positioning probes the lazy list until the divider or message key is mounted, avoiding index-ratio fallback errors caused by tall failed media placeholders.
- Reply navigation uses a monotonic smooth scan to mount the target message before final `ensureVisible`, instead of alternating visible probe jumps.
- Open-chat read marking is bottom-aware: incoming updates are auto-read only while the user is already near the bottom, otherwise unread state is preserved.
- Chat opening initial history selection and unread anchoring skip failed incoming media placeholders, so old `Ошибка загрузки` items do not pull the loaded window or viewport away from newer content.
- Video-file bubbles use the existing `video_player` runtime to show a paused local frame preview with a play overlay, falling back to the dark placeholder if preview initialization is not possible.
- Media viewer shows a user-friendly fallback for Android codec errors such as `video/dolby-vision` / HDR 10-bit and lets the user open the original file in another app.
- Settings uses aggregated bootstrap/relay/turn cards on the main screen and dedicated list screens for managing each server group.
- `SettingsController` in `lib/ui/state` is now decomposed: server-status presentation is in `settings_server_status_presenter.dart`, invite encode/parse is in `settings_invite_codec.dart`, and pairing flow logic is in `settings_pairing_flow_service.dart`.

### 4.2 Core Entry (`lib/core/node`)

- `NodeFacade`: stable API for UI.
- Unified messaging/blob entrypoints live here: `sendPayload(...)`, `uploadBlob(...)`, `downloadBlob(...)`.
- `MeshNode`: composition/lifecycle/signaling routing.
- `MeshSignalRouter`: the extracted routing seam for the signaling -> `CallService` / peer-transport boundary inside `MeshNode`.

### 4.3 Runtime (`lib/core/runtime`)

- `NetworkDependencies`: dependency graph builder.
- `AppBootstrapCoordinator`: post-bootstrap wiring (servers, background tasks).
- Storage and repositories (`StorageService` as facade, `storage_service_paths`, `storage_service_migrations`, `storage_service_media`, contact/call repositories).
- SQLite chat storage keeps message uniqueness scoped to a chat through `(peerId, messageId)`, so the same message id in different chats cannot overwrite another chat's row.
- Real SQLite `StorageService` write/read coverage exists in `test/core/runtime/storage_service_chat_messages_test.dart` and should be kept for chat-message persistence changes.
- `StorageService` now acts as an orchestration/facade layer over storage helper modules and should not grow back into a monolith.
- Storage runtime is decomposed into:
  - `storage_service_paths.dart` for root/media path resolution and shared path helpers,
  - `storage_service_migrations.dart` for secure-storage load, legacy migrations, summary repair, and embedded-media pruning,
  - `storage_service_media.dart` for file/media persistence, legacy media restore, cleanup, and storage size helpers.
- Runtime storage cleanup is explicit-only:
  - users can clear concrete categories (`Media files`, `Messages database`, `Logs`, `Settings and service data`) from Settings,
  - heuristic orphan-media cleanup is intentionally removed because it is unsafe with legacy media recovery paths.
- The `Storage` block in Settings now follows the same navigation pattern as the server cards: tap the whole card and use the chevron to open details.
- `IdentityService` provides stable `peerId` (v2) plus legacy id metadata for compatibility.
- The identity/security layer is decomposed: `IdentityService` should remain an orchestration/facade layer, `identity_key_store.dart` owns the key-store abstraction and secure-storage bridge, `identity_storage_support.dart` owns storage/keypair/install-id helpers, and `identity_membership_crypto.dart` owns membership/update signing and verification payload logic.
- `SelfHostedDeployService`: SSH deployment orchestration for personal server stack, staged progress (`1/14 ... 14/14`), post-deploy connectivity checks, and fixed self-hosted endpoints `wss://<ip>:443` / `https://<ip>:444`.
- `AvatarService` now lives in `lib/core/runtime`: it owns local avatar cache, embedded backup/restore, blob download, and best-effort avatar announce/remove/query flow.
- Server-health services share the `ServerAvailabilityProvider` contract so future runtime orchestration can work with bootstrap/relay/turn probing through one interface.
- `ServerHealthCoordinator` owns the shared bootstrap/relay/turn health services and starts them after app bootstrap, so runtime and Settings use the same availability state instead of duplicate probe loops.
- Those health services also share a common polling/backoff engine, so retry cadence is unified across bootstrap/relay/turn and repeated failures automatically widen the probe interval.
- Bootstrap health refresh is single-flight and converts WebSocket connect timeouts into `unavailable` availability snapshots instead of bubbling timeout exceptions from periodic probes.
- `HttpRelayClient` and `TurnAllocator` are wired to coordinator-backed relay/turn availability lookups, so runtime routing decisions can reuse the same shared health snapshots that drive Settings.
- The coordinator also reacts to app resume and connectivity changes, triggering shared health refreshes without requiring Settings to be opened.
- Relay critical paths can request a selective coordinator-backed refresh for just the current relay shortlist when the shared relay snapshot is stale, keeping send/blob decisions fresh without refreshing the whole relay set.
- TURN call setup can request a selective coordinator-backed refresh for just the current TURN shortlist when shared TURN health is stale, so TURN-backed `rtcConfig` stays fresh without reprobeing the full TURN set.
- Application versioning is sourced from `pubspec.yaml` (`version: x.y.z+n`) and propagated to Android/iOS through Flutter build variables.

### 4.4 Messaging (`lib/core/messaging`, `lib/core/relay`)

- `ReliableMessagingService`: envelope encode/decode, replay checks, relay polling.
- Relay ack is tied to durable delivery: direct/group chat envelopes are acknowledged only after the awaitable `NetworkEventBus` path lets `ChatController` persist the local message or media placeholder.
- `HttpRelayClient`: `/relay/store`, `/relay/group/store`, `/relay/group/members/update`, `/relay/fetch`, `/relay/ack`, blob APIs.
- `RelayMediaTransferService` and `RelayMediaRetryCoordinator` now live in `lib/core/relay`: relay media upload/download, restore result models, and persisted retry orchestration no longer live in `ui/state`.
- Relay strategy:
  - active relay pool is capped,
  - runtime operations preselect only live relays and use at most 3 servers,
  - writes and ack use quorum,
  - fetch aggregates across the active pool with per-relay cursors,
  - dead relays are excluded from the active path whenever healthy relays are available.
- Push fanout path:
  - all app push events are emitted as signed `/events/push` requests,
  - the app defines the full `payload` (`type`, `relay`, `servers`, `priority_servers`, and other fields), while `push.js` only validates the signature and fans out to recipient devices,
  - `push.js` sends both `notification` and `data/payload` for iOS-friendly background visibility.
  - in `background/killed` states, system push-alert text is not rewritten by the client: the OS shows exactly `notification.title/body` as authored by the sender and transit-forwarded by `push.js` through the push provider.
- Personal media/blob strategy:
  - upload once to relay blob storage using deterministic direct scope,
  - deliver encrypted `direct_blob_ref` over the normal personal reliable-message path,
  - receive personal media only through `direct_blob_ref` plus relay blob download,
  - direct blob restore now wraps download with retry/timeout protection,
  - if the current live relay shortlist returns only `404` for a blob, the client retries against the remaining configured relays before declaring the blob missing,
  - after transient network errors or temporary relay unavailability, incoming media restore keeps retrying later while the app is active, on chat open, app resume, or connectivity restoration,
  - `blob not found` remains a terminal stop to prevent infinite restore loops,
  - interrupted incoming relay-media placeholders can resume on chat load, app resume, or connectivity return through persisted retry metadata,
  - Android foreground service is not used for media restore, so `FOREGROUND_SERVICE_DATA_SYNC` is not needed,
  - incoming relay-media restore is single-flight per `peerId::messageId`, so manual taps and background retry do not launch competing blob downloads or conflicting progress updates,
  - incoming relay-media progress is monotonic to hide parallel relay-candidate progress races,
  - relay media upload/download mechanics and incoming retry state/timers are isolated in `lib/core/relay/relay_media_transfer_service.dart`; `ChatController` owns message state and UI orchestration.
- Group media/text blob strategy:
  - preferred for large payloads: chunked upload (`/relay/blob/upload/chunk`, `/relay/blob/upload/complete`),
  - fallback: single-shot upload (`/relay/blob/upload`),
  - receive path fetches `/relay/blob/:blobId`,
  - media/blob receive path should not stall on sequential waits for unavailable relays when live relay candidates exist.
- Group chat deletion for everyone is owner-only: the owner uses direct service-control fan-out (`groupChatDelete`) to known members and stores a local group tombstone after cleanup so stale group messages/invites cannot recreate the chat; non-owners send a `groupMembers` leave event, are removed from membership by the owner path, and then delete the local copy.

### 4.5 Calls (`lib/core/calls`)

- `CallService` should remain a thin orchestration/facade layer over call helper modules and peer/runtime callback wiring.
- `CallCommandHelper`, control-signal helpers/routers, connect orchestration, network policy, peer binding/lifecycle, lifecycle reset, media readiness/timeout, state update, and pending remote-end helpers own bounded call-flow responsibilities outside `CallService`.
- `AudioCallPeer` is now a thin orchestration/facade layer over call controllers and should not grow back into a god object.
- `CallPeerSessionController` owns peer bootstrap, incoming/outgoing session flow, and cleanup/reset.
- `CallPeerSessionController.disposePeerConnection()` is the single terminal cleanup path for peer-runtime timers/pollers; timer cancellation must not be duplicated higher in the call stack.
- `CallNegotiationController` owns `rtcConfig`, renegotiation, ICE restart, and recovery policy.
- `CallVideoController` owns the video state machine, transceiver/video-handle sync, and quality policy.
- `CallMediaFlowController` owns audio/video flow detection, stats polling, and media-flow fallback logic.
- `CallMediaReadinessController`, `CallLiveMediaStallDetector`, `CallPostIceRecoveryFlowWatch`, stats/recovery trackers, and diagnostics formatter own media readiness/recovery observation outside the core facade.
- Remote control, renegotiation, video signaling/transceiver/quality, camera flip, runtime snapshot/tracking, signal transition serialization, terminal lifecycle, and epoch-safe timer logic live in dedicated `call_*` modules.
- `CallPeerEventController` owns WebRTC peer-event binding into runtime state updates.
- `CallLocalMediaController` owns local mute/speaker/camera/media-type toggles.
- `CallConnectionStateController` owns connected-state policy and the transition point to connected transport.
- `IosCallkitService` should remain a native bridge layer and must not absorb server-merge orchestration or payload normalization back into itself.
- Current call policy: TURN-only for all network types.

### 4.6 Signaling (`lib/core/signaling`)

- `BootstrapSignalingService` over WebSocket.
- `BootstrapSignalingRuntimeState` stores the shared mutable runtime state of the signaling module.
- `BootstrapSignalingSessionController` owns the `setServer`/connect/register flow.
- `BootstrapSignalingConnectivityController` owns connectivity watch logic and fast-reconnect policy.
- `BootstrapSignalingReconnectController` owns retry/backoff/circuit-breaker policy and reconnect trace.
- `BootstrapSignalingProtocolController` owns register/signal/ping/peers protocol flow, retry queue, and inbound frame handling.
- `BootstrapSignalingModels` contains shared signaling value objects (`BootstrapPendingSignal`, `BootstrapReadyTimeout`, `BootstrapRegisterProof`).
- `MultiBootstrapSignalingService` aggregates multiple bootstrap connections into a single runtime signaling surface.
- Handles reconnect, registration, signal frames, optional peer discovery.
- Outgoing signaling (`call_invite`, `offer`, `answer`, `ice`) is sent to every bootstrap channel where the target peer is visible through `peers` snapshots; if there is no match, fallback is all connected bootstrap channels.
- Registration uses stable `peerId` (v2); auth proof includes `identityProfile`.
- For self-hosted IP endpoints, runtime accepts self-signed TLS certs in bootstrap and relay clients (IP-host only).
- In self-hosted topology, HAProxy terminates only `signal` (`:443`) and `relay` (`:444`); TURN/TURNS is served directly by `coturn` on `3478/5349`.
- Inside signaling, the target decomposition has already been moved away from `part` into separate import-based controller/model modules with explicit dependencies.

### 4.7 Transport + Overlay + DHT

- `TransportManager` routes bytes through registered `PeerSession`.
- `PeerSession` currently direct-only.
- Overlay and DHT components exist, with DHT still minimal.
- `AvatarService` stores an embedded backup for contact avatars, so restart recovery does not depend on immediate network avatar re-sync.

## 5. Architectural Rules

- UI must not directly depend on transport/security internals.
- `NodeFacade` remains the only UI boundary.
- Runtime composition belongs to `NetworkDependencies`.
- Any new call/media logic should be extracted from `AudioCallPeer` (controller/state style).
- Inside `lib/core/calls`, prefer extending existing `Call*Controller` modules first; introduce a new controller only when the responsibility is genuinely new.
- Documentation must track runtime truth (not target-only intent).
- Large files must not grow unchecked: for files above `~800` lines in UI/state and `~500` lines in runtime, new features should be implemented via extracted modules (service/controller/helper) or at minimum dedicated domain parts.
- Before creating a new service, always inspect the existing services in the same bounded context; duplicated service responsibilities are not allowed.
- If a suitable service already exists but lacks some required behavior, extend that service instead of introducing a parallel duplicate.
- Before adding functionality to a large file, an explicit decomposition plan is required (responsibility boundaries + test seams).
- For god-object-like modules, decomposition is the priority; adding more logic without extraction is treated as architecture debt and should be blocked in code review.

## 6. Near-Term Architectural Priorities

1. Re-enable and harden encrypted messaging path end-to-end.
2. Decide and implement transport strategy for message sessions (direct-only vs failover stack).
3. Expand group transport from recipient fan-out to server-side sequence log (topic style).
4. Expand DHT from skeleton to working lookup/RPC workflows.
5. Reduce bootstrap centrality (move signaling toward overlay/DHT).
6. Add integration tests for signaling/reconnect/call stability.
