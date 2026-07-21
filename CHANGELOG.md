# CHANGELOG

All notable PeerLink application changes should be recorded in this file.

## [3.6.0] - 2026-07-21

### Changed

- Android/macOS app-link and custom-scheme handling was hardened for `peerlink://invite`, `peerlink://pair`, `peerlink://config`, `peerlink://call`, and supported `https://simplegear.org/...` links; macOS now configures the deep-link channel from `MainFlutterWindow`, registers URL handlers early, and keeps pending links for Flutter startup.
- Server-config deep links now merge the embedded `bootstrap/relay/turn/push` payload directly, while QR/manual imports keep the explicit import-mode dialog.
- Invite handling now merges the embedded available server configuration before skipping self-contact creation, so self-invite links can still import server settings.
- The FCM runtime layer was split further into inbound orchestration, payload processing, and presentation modules: `FirebasePushInboundService`, `FirebasePushPayloadProcessor`, and `FirebasePushPresentationHandler`.
- Push fanout construction was moved into `PushEventFactory`, `PushRuntimeMetadataBuilder`, and `PushEventService`, leaving `PushApiClient` as the low-level signed HTTP client.
- App icon badge handling now goes through `AppBadgeService`, which persists unread/missed-call counts and syncs the platform badge.
- Opened push handling can poll hinted relay servers before the full relay poll, improving recovery when the receiver does not yet have the sender's current relay set.
- Incoming call pushes can present the incoming call immediately from the UI open path, while call/video controllers gained additional guards for local media state, renderer reuse, and stale call events.
- Android App Links now include `web/.well-known/assetlinks.json` support for the public site link flow.

## [3.4.4] - 2026-06-12

### Changed

- Continued the call-path hardening work: introduced an explicit `IncomingCallBootstrapPolicy` helper for bounded accept-time runtime enrichment instead of keeping that policy implicit inside `CallService`.
- Introduced a typed `CallSessionEpoch` model and moved active call/runtime epoch ownership away from raw integers in `CallService` and `AudioCallPeer`.
- Standardized structured call logging further: shared call log context now includes `callId`, `peerId`, `epoch`, role, transport mode, and media type across `CallService` and `AudioCallPeer`, while peer-level logs now also carry the latest observed WebRTC signaling state.
- Added an explicit call-peer invariant helper and guards so one active peer owns a given `callId`; foreign media signaling with the same `callId` can no longer reuse or rebind another active peer.
- Finished consolidating push/call payload normalization around one internal model object, `FirebasePushPayload`: the UI open path, FCM foreground/open/native-fallback handling, and the iOS CallKit path no longer keep separate call-payload models.
- Decoupled `IosCallkitService` from direct server-merge orchestration so it remains a native bridge layer with an external callback seam for push payload/runtime metadata handling.
- Centralized terminal peer-runtime cleanup: `audio stats`, `video flow`, `ICE grace`, and `quality upgrade` timers are now cancelled through the shared `CallPeerSessionController.disposePeerConnection()` path instead of being duplicated locally in `AudioCallPeer`.
- Added orchestration smoke coverage: `CallService` now has a stable control-cycle smoke test, and `MeshSignalRouter` now has routing smoke tests as the extracted seam around `MeshNode`.
- Added focused call tests covering `IncomingCallBootstrapPolicy`, `CallSessionEpoch`, structured call log context, one-active-peer-per-callId invariant helper behavior, same-`callId` foreign-peer media routing, bootstrap reconnect signaling wait, video-upgrade state updates, and stale timer suppression after peer dispose.

## [3.4.3] - 2026-06-10

### Changed

- The app push contract and `push.js` were migrated to a single universal `POST /events/push` endpoint: the client now sends `recipientUserIds`, arbitrary `payload`, optional `notification`, and optional `delivery`, while the server acts as a transport-only fanout layer without dedicated `/events/message`, `/events/call`, or `/events/call-voip` wrappers.
- `PushApiClient`, `MeshNode`, and `MeshCallPushHelper` were updated to the universal contract so call/message/group/account push flows no longer depend on server-side thin wrappers per event type.
- Updated `README.md`, `ARCHITECTURE.md`, and `NETWORK_FLOW.md` to document the new transport-only `push.js` model and `/events/push` contract.

## [3.4.2] - 2026-06-09

### Changed

- Continued the call-layer decomposition: connect/timeout/TURN fallback orchestration, control-signal routing, media readiness/recovery, and state-transition helper logic were moved out of `CallService` into dedicated helper modules, reducing `CallService` further to an orchestration/facade role.
- To reduce the long-standing first-call crash risk after cold start/update, audio-call bootstrap now performs a one-time `audio-only` warm-up before the first real local media capture; speaker routing is also applied only after the local stream is ready.
- Moved the call-push layer out of `MeshNode` into `lib/core/node/mesh_call_push_helper.dart`, so device-token registration and `/events/call` fanout are no longer mixed into signaling/peer-session orchestration.
- Updated `ARCHITECTURE_RU.md` and `BACKLOG_RU.md` to record the new `MeshCallPushHelper` boundary and the current decomposition status of the `mesh_node` / call-runtime layer.

## [3.4.1] - 2026-06-08

### Changed

- Added configurable app file-log level in Settings: users can now switch between `Errors only` and `Verbose`, and the choice is persisted across restarts.
- Removed noisy `UiApp.build` file logging from the UI hot path, so verbose diagnostics no longer flood `app.log` with rebuild spam.
- Added detailed diagnostics for incoming group-message handling and relay-media restore: logs now include group inbound path markers plus media download/transform/save timings and retry attempts.
- Foreground push handling for `message` / `direct_update` / `group_update` now also triggers `pollRelay()` and merges server metadata without forcing a tab switch.
- Fixed incoming group-chat routing context: group messages now preserve the real sender separately from the chat target via `senderPeerId`, so inbound group handling no longer confuses `groupId` with the sender peer.
- Added a dedicated emoji-only chat presentation: messages containing only `1-3` emoji are shown larger, without the normal bubble frame, with a lightweight entrance animation.
- Updated `README.md` and `README_RU.md` to document the new log-level switch, foreground push-triggered relay polling, and the current diagnostic logging behavior.

## [3.4.0] - 2026-06-08

### Changed

- Removed legacy peer-id compatibility metadata from the app runtime and payload contracts: `legacyPeerId` / `legacyUserId` are no longer exported in identity profile, bootstrap auth proof, invite payloads, or account-pairing payloads, and account-device identity no longer stores legacy peer id fields.
- Updated identity/pairing/invite flows and related tests to use only the stable runtime `peerId` / `deviceId` model.
- Restored app file logging with filtering: runtime logs now keep only warning/error-level diagnostics, while noisy info/debug messages are no longer written to the log file.
- Kept log rotation behavior unchanged: active `app.log` still rotates at `1 MB`, archives still use `app_<timestamp>.log`, and only the latest `5` rotated files are retained.
- Aligned log cleanup behavior across Settings and Storage: the `Clear logs` action now removes both the current log file and rotated log archives, so the `Logs` size on the `Storage` screen matches the cleanup result.
- Updated `README.md`, `README_RU.md`, and in-app localization strings to reflect the current logging behavior and the new `Clear logs` wording.

## [3.3.4] - 2026-06-08

### Changed

- Fixed group/direct event recovery after cold start and reinstall: runtime now also calls `pollRelay()` on startup, on `AppLifecycleState.resumed`, and when connectivity returns, so message recovery no longer depends only on opening the app from a push notification.
- Fixed incoming relay group envelope routing: `groupId` is no longer lost between `ReliableRelayPollController`, `ReliableInboundProcessor`, and `ChatService`, so group payload is published to the group target instead of the sender peer target.
- Decomposed `lib/core/security/identity_service.dart`: `IdentityService` is now reduced to an orchestration/facade layer, key-store code moved to `identity_key_store.dart`, membership/update signing moved to `identity_membership_crypto.dart`, and storage/keypair/install-id helpers moved to `identity_storage_support.dart`.
- Updated `ARCHITECTURE*.md`, `PROJECT_STRUCTURE_RU.md`, and `AI_CONTEXT*.md` to document the current identity/security module split and the rule that storage/signature helper responsibilities must not be collapsed back into `IdentityService`.
- Decomposed `lib/core/runtime/storage_service.dart`: the `StorageService` facade is now reduced to an orchestration layer, while path resolution, migration flow, and media/storage cleanup were moved into `storage_service_paths.dart`, `storage_service_migrations.dart`, and `storage_service_media.dart`.
- Fully decomposed `lib/core/messaging/reliable_messaging_service.dart`: the reliable messaging layer is now split into the facade `ReliableMessagingService`, `ReliableInboundProcessor`, `ReliableSessionController`, `ReliableRelayPollController`, `ReliablePendingOperationStore`, `ReliableRetryScheduler`, and `ReliableCodec`.
- Reduced `ReliableMessagingService` to an orchestration/facade layer: poll loop, replay/decode, session/handshake lifecycle, pending persistence/retry, and signature/header builders no longer live in one file.
- Updated `ARCHITECTURE_RU.md` and `PROJECT_STRUCTURE_RU.md` to document the current modular reliable messaging structure and the responsibilities of the new submodules.
- Disabled global ATS bypass `NSAllowsArbitraryLoads` in `ios/Runner/Info.plist`; manual verification on the current self-hosted stack confirmed working bootstrap/relay/turn connectivity over both domain names and IP endpoints, with correct messaging and call delivery even without that flag.
- Added missed-call indication in app navigation: the `Calls` tab now shows a badge for new incoming missed calls and clears it after opening the calls screen.
- Updated app icon badge calculation: it now includes the sum of unread messages and new missed calls (`messages + missed calls`) instead of unread messages only.
- `Share configuration` now sends an HTTPS payload link, in the same style as invite sharing, instead of raw JSON; server-config import from QR/link now accepts `peerlink://config?...` and web links with `payload`, decodes them, and merges `bootstrap/relay/turn/push`.
- Landing/web payload routing is now strictly split by type: pairing opens `peerlink://pair?...`, invites open `peerlink://invite?...`, and server configuration opens `peerlink://config?...` without invite/config mixing.
- Shared server configuration text now includes the prefix `PeerLink server configuration: <link>`.
- iOS deep-link routing now explicitly supports server configuration links (`peerlink://config` and `https://.../config`), so config payload correctly reaches Flutter on launch/open.
- Server-config QR/manual import keeps the import mode dialog (`Merge` / `Replace`), while current app-side config deep links merge directly.
- Deep-link input normalization now extracts URLs from prefixed share text, for example `PeerLink server configuration: https://...`, so payload links are still recognized correctly.
- The `servers` contract in push payloads now includes `push`: the client sends available `bootstrap/relay/push/turn` endpoints to `/events/message`, `/events/call`, and `/events/call-voip`.
- On push receive, the client now merges and applies `push_servers` together with `bootstrap/relay/turn` through the shared runtime layer `ServerHealthCoordinator`, without duplicates.
- Added push fallback for `accountMembershipUpdate`: revoke/add membership updates are now sent as `data.type=account_membership_update` via `/events/message`; the client handles them silently, applies them immediately, and stores them in pending `account_membership_updates.v1` on failure.
- Added the same kind of push fallback for group member removal: the owner/initiator now sends `data.type=group_members_update` (`groupMembers` payload), and the client applies it silently as a normal `groupMembers` control update without showing a notification.
- Decomposed the chat state layer: storage/read-model, summary/group-meta persistence, file queue, outbound flow, inbound flow, read-state, contacts, and group use-cases now live in dedicated services (`chat_repository`, `chat_summary_service`, `chat_file_queue_service`, `chat_outbound_service`, `chat_inbound_service`, `chat_read_state_service`, `chat_contacts_service`, `chat_group_service`).
- Moved group crypto out of `ChatController` into `lib/core/security/group_message_crypto_service.dart` next to `group_key_service.dart`; binary `PLG2` pack/unpack and encrypt/decrypt no longer live in UI/state.
- Fixed message deletion for unloaded chats: persisted message/summary state is now updated correctly even when the chat is not loaded in in-memory `chats`.
- Made group avatar updates safer: local `avatarPath` is committed only after successful `groupMembers(action=avatar)` broadcast, and the staging file is deleted on fan-out failure.
- `memberPeerIds` are now canonicalized (`trim + unique + sort`) before persistence/compare so identical membership sets no longer trigger unnecessary group-meta writes due only to ordering.
- Added the native iOS bridge `peerlink/push_payload/methods` (`consumeLatestPushPayload`): if `FirebaseMessaging.getInitialMessage()` returns `null` after tapping a push, Flutter consumes the latest payload from `AppDelegate` and still applies `servers`.
- In iOS `AppDelegate`, the `didReceiveResponse` handler now forwards the event to `super.userNotificationCenter(...)` so Firebase Messaging plugin delivery is not lost.
- `FirebaseMessaging.onBackgroundMessage(...)` registration was moved to an early stage in `main()` before app bootstrap.
- In `AudioCallPeer`, outgoing audio-call bootstrap no longer binds the local audio-only `MediaStream` to the video `SendOnly` transceiver, and extended step-by-step `startOutgoing` diagnostics were added (`prepare/createOffer/setLocalDescription/sendOffer`) to localize native iOS crashes during call setup.
- For iOS CallKit incoming calls, caller updates now synchronously update both `localizedCallerName` and `remoteHandle`: when a contact is known, the lock screen shows the contact name; otherwise it keeps `PeerID`.
- Added a VoIP push end signal (`callAction=end`) to the call runtime for outgoing hangup, and the iOS bridge now terminates the active CallKit call by `callId`, so the receiving side no longer gets stuck on the incoming-call screen.
- Local message/call notifications are now suppressed while the app is active (`AppLifecycleState.resumed`) to remove duplicates over the open chat/call screen.
- Added deferred iOS VoIP/CallKit bridge events (`call_incoming`/`call_action`): if the Flutter event stream is not yet attached while the app is in background, events are queued and delivered on `onListen`, so accepting a call from the system screen still starts the PeerLink call correctly.
- Answering a call from system CallKit on iOS now brings the app to foreground via `peerlink://call`, so the user is moved into the PeerLink call screen and WebRTC setup reaches active state faster.
- Added explicit VoIP push contract documentation in `README_RU.md`: `/devices/register-voip`, `/devices/unregister-voip`, `/events/call-voip`, required APNs headers, and a ready `.env` template for `push.js`.
- In `push.js` (`/Users/vladimir/peerlink_servers/push.js`), added strict APNs topic validation for `*.voip`, support for request override via `apns.topic`, a clear `invalid_apns_topic` error, and extended `/health` diagnostics (`apnsVoipTopicConfigured`, `apnsUseSandbox`).
- VoIP delivery in `push.js` was switched from `fetch` to a native `http2` client to eliminate protocol errors (`Expected HTTP/`, `HPE_INVALID_CONSTANT`); `/events/call` and `/events/call-voip` now return `502 push_send_failed` when all call deliveries fail (`sent=0`, `failed>0`).
- Increased APNs token wait in `lib/core/firebase/firebase_messaging_service.dart` for iOS/macOS: `_waitForApnsTokenIfNeeded()` now retries `20` times instead of `10`.
- FCM is now initialized by default on all platforms, including Android and Windows, because the platform gate was removed, so a token is always requested and sent into the push runtime.
- Push servers now use the same centralized health-check scheme as bootstrap/relay/TURN: added the runtime provider `PushServersService` with polling `GET /health`, integration into `ServerHealthCoordinator`, and shared `availability` streams/snapshots.
- The `Push servers` screen now shows real endpoint availability state (`available/error/waiting for probe`) instead of a static `configured`.
- In `SettingsController`, push-server list management was moved out of local helper methods into the runtime coordinator, so configuration and availability go through one shared layer.
- Added aggregated `available/unavailable` counters on the push-server card in Settings based on live health state.
- Added runtime logging for the push provider (`[push_service]`): initialization, add/remove endpoint actions, refresh, and poller/probe events for availability diagnostics.
- Decomposed `SettingsController`: server-status presentation moved to `settings_server_status_presenter.dart`, invite encode/parse moved to `settings_invite_codec.dart`, and pairing request/approve/reject flow moved to `settings_pairing_flow_service.dart` without changing user-visible behavior.
- Push endpoint format is now aligned with the external HAProxy setup: in Settings, users enter only `domain/IP`, and runtime normalizes it to `https://<host>:445` instead of `http://<host>:4500`.
- The `Peer ID` card in Settings now also shows the current `FCM token` using `SelectableText` for easier device push-registration diagnostics.
- FCM is now enabled by default for iOS/macOS (`ENABLE_IOS_FCM=true` as default), so the token is requested and synced with push runtime without requiring `--dart-define`.
- Added a 12-second timeout around FCM initialization during app startup: if Firebase Messaging hangs, including on macOS, bootstrap continues and the UI no longer stalls at the `Initializing FCM` step.
- In `lib/core/push/push_api_client.dart`, the client push-endpoint whitelist is now fixed: only `/devices/register`, `/devices/unregister`, and `/events/message` are allowed; any other path is rejected client-side.
- The bearer token for `push.js` is now sourced only from `--dart-define=PUSH_API_TOKEN=...` with no UI/settings storage; `.vscode/launch.json` now includes `toolArgs` templates with `__SET_PUSH_SERVER_URL__` and `__SET_PUSH_API_TOKEN__` placeholders.
- The push message event contract was extended to `push-v1.1`: signed `schemaVersion` and relay metadata (`relay.serverId`, `relay.scopeKind`, optional `relay.blobId`, `relay.relayMessageId`) were added to `/events/message` in both the client (`PushApiClient`) and `push.js`.
- `push.js` now includes backward-compatible signature verification for legacy `/events/message` payloads without `schemaVersion`, while also validating relay metadata for `push-v1.1`.
- `push.js` group-update fanout now sends both `notification` and `data` to improve iOS background-notification visibility.
- In `PushApiClient`, signatures for `/events/message`, `/events/call`, and `/events/call-voip` are now aligned with the current `push.js` contract: the signature includes event fields plus `relay`/`schemaVersion` for `push-v1.1`, while the `servers` block is sent as separate payload metadata and does not participate in `sig`.

### Fixed

- Preserved existing direct/group send flow, relay ack behavior, replay protection, handshake retry, and persisted retry semantics during the reliable messaging decomposition; `dart analyze` now passes cleanly across the new messaging modules.

## [3.1.1] - 2026-05-03

### Added

- Contacts now include an Invite sheet with a `peerlink://invite` QR/deep link; opening it imports the inviter as a contact and merges the included available server configuration.
- Shared invite text now uses a clickable HTTPS landing URL while keeping the `peerlink://invite` app link for QR/direct opening; invite import accepts both formats.
- Added the public `https://simplegear.org` landing/invite page with a full-page language switcher for supported languages, open-source repository links, placeholder App Store / Google Play links, and real PeerLink web icons instead of Flutter defaults.
- Contact rows now open a long-press action menu with `Rename`, allowing saved display names to be updated without changing the peer ID.
- Direct chats with unknown peers now show `Add contact` in the top-right chat menu.
- Chat screens now show a floating down-arrow button after scrolling upward; tapping it jumps to the first unread message when present, otherwise back to the bottom.
- Added the foundational `AccountIdentity` model with a separate `accountId`, `displayName`, and account `devices`; the current `peerId/nodeId` is preserved as the device identity without changing routing.
- Settings now include an `Account and devices` block: users can show a `peerlink://pair` QR/deep link and pair a second device with the same `accountId`; import also merges the available server configuration.
- Second-device pairing now includes an explicit approval step: scanning `peerlink://pair` no longer imports immediately and is first stored as a pending pairing request until the receiving device confirms it.
- Second-device pairing now uses the flow `scan -> request -> approve`: the second device sends a request to an already trusted account device, and the final merge of `accountId` and server config happens only after an incoming approval message.

### Changed

- Simplified the Bootstrap, Relay, TURN, and Storage detail screens: technical server titles stay language-neutral, explanatory copy is shown as plain text, and rows are displayed as compact direct lists without extra section wrappers.
- Removed duplicate red inline warnings from Storage category rows; destructive details remain in the delete confirmation dialog.
- Server configuration QR export now includes only currently available bootstrap, relay, and TURN servers; pending/unavailable servers are omitted while empty lists remain valid.
- Startup and background relay polling now treat an empty relay server list as a disabled/empty state instead of throwing `No message relay servers configured`.
- Shared invite links now point to `https://simplegear.org/invite`; mobile deep-link routing still accepts the previous GitHub Pages invite host for compatibility.
- macOS secure storage now uses shared safe options for the regular macOS Keychain instead of Data Protection Keychain, and identity/session keys now go through the shared `SecureStorageWrapper` file fallback so local release builds without Keychain Sharing do not crash with `-34018`.
- Local notification initialization now supplies `macOS` settings to `flutter_local_notifications`, preventing macOS startup crashes with `macOS settings must be set`.
- The macOS AppIcon asset catalog has been regenerated from the current PeerLink primary icon.
- macOS entitlements now include outgoing network access via `com.apple.security.network.client`, allowing sandboxed release/debug builds to connect to bootstrap, relay, and TURN servers.
- macOS now mirrors the required iOS-style permissions for calls and media: camera/microphone/local-network/contacts/notifications usage descriptions, microphone/camera/incoming-network/user-selected-file/address-book entitlements, and desktop speakerphone toggles are safely ignored instead of crashing.
- Chat screens now support a right-swipe gesture across the message area, including text and media bubbles, to return to the chats list.
- Bootstrap, Relay, TURN, and Storage detail screens now support the same right-swipe back gesture across their full content area.
- Owner deletion of a group chat now propagates to all known members and stores a local tombstone so old relay/invite events cannot restore the removed group; non-owner deletion now sends a group leave event before local cleanup.
- Group chat creation is now guarded against rapid repeated taps: the sheet disables creation while pending and the controller joins duplicate in-flight create requests.

### Fixed

- Reliable outbound relay operations now persist direct messages, group messages, and group membership updates before send attempts, so app restarts no longer drop those sends while handshake/retry is in progress.
- Relay polling now distinguishes `all selected relays unavailable` from a normal empty inbox, avoiding false idle backoff growth during relay outages.
- Relay POST and blob-upload HTTP paths now use transient retry/timeout containment comparable to GET, so late socket connect/open/close/body-read failures degrade into per-relay send failure instead of bubbling raw `dart:io` errors.
- Bootstrap WebSocket `ready` timeout is now handled as a normal connection error with reconnect, without throwing `TimeoutException` from `setServer`; half-open socket close is bounded so startup does not hang on a dead endpoint.
- Relay HTTP connect/header/body-read failures are now converted into transient relay failures instead of surfacing raw `dart:io` exceptions; quorum writes use the bounded active relay pool so one write-time relay failure can be tolerated when enough live relays remain.
- Bootstrap, relay, and TURN availability services now share one polling/backoff engine: Settings and runtime use the same status snapshots, failed servers back off exponentially instead of being probed at a fixed spammy cadence, and coordinator-wide refreshes no longer fail the whole health pass if one provider errors.

## [2.9.1] - 2026-04-30

### Added

- Added runtime interface language switching in Settings:
  - supported languages start with `EN`, `RU`, `ES`, `ZH`, and `FR`,
  - the selected language is persisted locally and applied immediately,
  - top-level navigation, Settings, Contacts, Chats, Calls, chat actions, media status labels, and call overlays now use the shared localization layer,
  - localization text is stored in per-language dictionaries under `lib/ui/localization/dictionaries`.

### Fixed

- Bootstrap, relay, and TURN server availability probes now use controlled timers instead of socket/client-level timeout helpers, so long-running checks mark endpoints unavailable without surfacing internal `TimeoutException`s; relay/TURN refreshes are also single-flight.

## [2.8.8] - 2026-04-28

### Changed

- Rethemed the application UI to match the new app icon:
  - moved the global palette to a dark navy / electric blue security style,
  - updated shared surfaces, navigation, dialogs, buttons, inputs, and progress indicators,
  - aligned call and QR overlay surfaces with the new dark visual system.
- Added runtime appearance switching in Settings:
  - users can now choose between `blue`, `black`, `turquoise`, and `violet`,
  - the selected palette is persisted locally and applied immediately,
  - launcher app icon switching is wired for both iOS alternate icons and Android launcher aliases.
- Reworked `Settings` server management UX:
  - bootstrap/relay/turn are now shown as aggregated cards on the main Settings screen,
  - each server group is managed on its own dedicated list screen,
  - add actions for bootstrap/relay/turn were moved to those dedicated list screens,
  - server list headers/descriptions were unified across bootstrap/relay/turn screens.
- Updated the `Storage` block in Settings to use the same navigation pattern as server cards:
  - removed the standalone `Details` button,
  - opening storage details now happens by tapping the whole card,
  - added right-side chevron navigation affordance.
- Simplified the Contacts screen:
  - removed the descriptive header copy,
  - added a placeholder `Invite` link under the screen title,
  - contact rows now show only avatar, display name or short peer id, and last-seen text.
- Simplified the Chats and Settings top-level pages:
  - removed descriptive page copy from Chats and Settings,
  - chat rows no longer show last-seen text,
  - top-level app typography now uses one shared font family through `AppTheme`.
- Unified the compact card rhythm across Contacts, Chats, and Settings:
  - contact/chat rows now use tighter padding, smaller avatars, and explicit small separators,
  - Settings cards and server-list rows use smaller internal padding, radii, and gaps.
- Made call history rows more compact and wired their shared spacing/radius/separator values to `CompactCardTileStyles`.

### Fixed

- Bootstrap server availability checks no longer surface WebSocket probe timeouts as app-breaking `TimeoutException`s; a timed-out probe now marks that endpoint unavailable and overlapping refreshes are skipped.
- Contact avatars should no longer disappear after app restart:
  - `AvatarService` now keeps an embedded backup for contact avatars,
  - startup restores the last local avatar first and only then performs network avatar sync.
- Improved incoming media download resilience across network switches:
  - direct blob download now uses retry/timeout protection,
  - if an incoming file breaks during `Wi‑Fi -> mobile` transition, the client schedules a bounded delayed auto-retry,
  - `Failed to download` UI state no longer looks like an infinite loading spinner.
- Prevented incoming relay-media metadata loss when the app is closed mid-download:
  - relay message ack now waits until `ChatController` durably stores the local message/placeholder,
  - unpersisted media references remain on relay and can be delivered again after restart.
- Stabilized chat opening scroll positioning:
  - the first bottom/unread viewport pass is now single-flight,
  - duplicate startup `initialViewport` / `jumpToBottom` scheduling is suppressed while the first pass waits for layout,
  - initial bottom positioning keeps settling across several frames, so recovered media height changes do not leave the viewport above the actual bottom,
  - first-unread positioning now probes real divider/message keys instead of relying on index-ratio fallback around tall failed media placeholders,
  - reply-to-message navigation now uses monotonic smooth scanning instead of visible zig-zag probe jumps,
  - incoming updates in an open chat are auto-read only when the user was already near the bottom.
- Opening a chat no longer anchors the initial loaded history window or scroll position on old incoming media placeholders that are already in `Ошибка загрузки`.
- Relay polling now treats `Connection closed before full header was received` as a transient relay failure instead of surfacing the HTTP exception from the fetch path.

## [2.2.1+1] - 2026-04-21

### Changed

- Unified runtime messaging/blob API in the core entry layer:
  - `NodeFacade.sendPayload(...)`
  - `NodeFacade.uploadBlob(...)`
  - `NodeFacade.downloadBlob(...)`
- Added file log rotation for mobile runtime logs:
  - active `app.log` is capped at `1 MB`,
  - oversized logs rotate into timestamped `app_<ts>.log` archives,
  - only the latest `5` archived log files are retained,
  - startup now also rotates an already oversized active log file immediately.
- Refactored messaging internals so direct/group delivery now use shared target-based contracts instead of parallel API pairs in `NodeFacade`, `ChatService`, and `ReliableMessagingService`.
- Unified relay media restore flow in chat state:
  - shared blob download/save pipeline for direct and group media,
  - group-specific retry and decrypt steps are now thin adapters over the common restore path,
  - group blob text/avatar decode now reuse the same helper logic.
- Brought runtime/documentation terminology in line with the shipped architecture:
  - personal media receive is documented as `direct_blob_ref` + relay blob download only,
  - removed outdated references that still described legacy direct chunk receive as an active compatibility path,
  - updated architecture/network/AI-context docs to describe the unified API layer.
- Standardized target-based logging in messaging services (`target=peer:...` / `target=group:...`) for easier debugging.

### Fixed

- Reduced drift between direct and group media restore implementations by removing duplicated restore logic.
- Removed stale documentation references to deprecated direct media receive behavior.
- Hardened local media cleanup:
  - internal message removal paths now delete managed media files before dropping message state,
  - incoming delete-for-everyone and cancelled transfer cleanup no longer leave orphaned media behind.
- Added a bootstrap endpoint circuit breaker:
  - repeated `connect failed` events now open per-endpoint cooldown,
  - bad bootstrap endpoints stop hammering reconnect attempts for the cooldown window,
  - overlapping `setServer()` calls for the same endpoint are coalesced to reduce reconnect storms and UI-impacting timeout noise.

## [Running build hooks...Running build hooks...1.1.5+9] - 2026-04-19

### Changed

- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- patch: release notes
- 'main' into dev
- patch: release notes
- patch: versions
- patch: versions
- patch: versions in settnigs screen
- patch: versions in settnigs screen
- minor: reply messages
- minor: reply messages

### Fixed

- correct path
- correct
- fix: dev_commit


## [Running build hooks...Running build hooks...1.1.4+8] - 2026-04-18

### Changed

- new identity, verify relay
- + group chats
- fix bug chat users, secure send group keys, group key service
- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- patch: release notes
- 'main' into dev
- patch: release notes
- patch: versions
- patch: versions
- patch: versions in settnigs screen
- patch: versions in settnigs screen

### Fixed

- correct path
- correct
- fix: dev_commit


## [Running build hooks...Running build hooks...1.1.3+7] - 2026-04-18

### Changed

- stable audi/video calls
- project optimization
- project optimization 2
- new identity, verify relay
- + group chats
- fix bug chat users, secure send group keys, group key service
- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- patch: release notes
- 'main' into dev
- patch: release notes
- patch: versions
- patch: versions

### Fixed

- correct path
- correct
- fix: dev_commit


## [Running build hooks...Running build hooks...1.1.2+6] - 2026-04-18

### Changed

- + settings share
- super calls, security signal server
- call from call screen
- stable audi/video calls
- project optimization
- project optimization 2
- new identity, verify relay
- + group chats
- fix bug chat users, secure send group keys, group key service
- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- patch: release notes
- 'main' into dev
- patch: release notes

### Fixed

- correct path
- correct
- fix: dev_commit


## [Running build hooks...Running build hooks...1.1.1+5] - 2026-04-18

### Changed

- + voice messages
- fix media bugs
- + Delete-for-everyone
- + base calls )))))) !!!!!!
- + settings share
- super calls, security signal server
- call from call screen
- stable audi/video calls
- project optimization
- project optimization 2
- new identity, verify relay
- + group chats
- fix bug chat users, secure send group keys, group key service
- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- chat reply navigation now resolves original messages from local history, loads older pages on demand, and scrolls more reliably to older referenced messages

### Fixed

- correct path
- correct
- fix: dev_commit
- improved stability of tapping a reply to jump to the original message when it is outside the current viewport


## [Running build hooks...Running build hooks...1.1.0+4] - 2026-04-17

### Added

- TODO

### Changed

- TODO

### Fixed

- TODO


## [Running build hooks...Running build hooks...1.1.0+3] - 2026-04-17

### Added

- TODO

### Changed

- TODO

### Fixed

- TODO

The format is intentionally simple and release-oriented.

## [1.0.1+2] - 2026-04-17

First release tracked under the formal versioning workflow.

### Added

- Managed application versioning from `pubspec.yaml` as the single source of truth.
- `tool/bump_version.dart` helper for `patch`, `minor`, `major`, `build`, and `set`.
- `VERSIONING.md` and `VERSIONING_RU.md`.
- Release history tracking through `CHANGELOG.md` / `CHANGELOG_RU.md`.
- Better server diagnostics in Settings for bootstrap, relay, and turn, including availability state and easier cleanup of outdated entries.

### Changed

- Project documentation now explicitly describes versioning and release bump rules.
- PeerLink version baseline advanced from `1.0.0+1` to `1.0.1+2`.
- More resilient bootstrap connectivity: the app can keep several bootstrap connections alive and route signaling more reliably when peers are visible on different servers.
- Faster relay delivery for messages and media:
  - runtime now prefers live relays and avoids dead servers when healthy ones are available,
  - active relay usage is limited to a small working set instead of the full configured list,
  - delivery and media fetch paths were optimized to reduce visible delays on partially unavailable relay setups.
