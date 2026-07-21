# AI_CONTEXT

Last updated: 2026-07-21

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
- Group crypto implementation lives in `lib/core/security/group_message_crypto_service.dart` next to `GroupKeyService`; `ChatController` should only delegate and must not keep its own crypto implementation.
- `IdentityService` should remain a facade over identity lifecycle; keep the key-store bridge in `identity_key_store.dart`, storage/keypair/install-id helpers in `identity_storage_support.dart`, and membership/update signing payload logic in `identity_membership_crypto.dart`.
- Relay fetch GET path uses transient retry/backoff on connection-drop errors, including premature connection close before HTTP headers.
- Relay POST/control/blob upload paths use the same transient retry/timeout containment approach as GET, so late connect/open/close/body-read socket errors should degrade into per-relay failure instead of crashing the app.
- Relay HTTP connect/header/body-read errors must be contained as transient per-relay failures; do not surface raw `dart:io` HTTP exceptions to UI/startup paths.
- Relay server enforces membership for group write endpoints; owner syncs membership via `/relay/group/members/update`.
- Group key rotates on membership changes (add/remove participants).
- Group chat deletion for everyone is owner-only: the owner sends service-control fan-out (`groupChatDelete`) and stores a local group tombstone; non-owners send a `groupMembers` leave event, leave membership, and delete their local copy.
- Relay runtime uses a bounded active pool + quorum instead of fan-out to every configured relay.
- Relay writes should target the bounded active pool, not only the quorum count, so write-time failure of one previously healthy relay can still meet quorum through another active relay.
- Relay runtime preselects only live relay servers for runtime operations, with a hard cap of 3 selected relays.
- If at least one healthy relay is available, unhealthy relays must not remain in the active runtime path for text/media delivery.
- Empty relay configuration is valid: startup/background relay polling must return an empty fetch result or skip work, not throw `No message relay servers configured`.
- macOS secure storage should use the shared `peerLinkMacOSStorageOptions` / `peerLinkSecureStorage` with `usesDataProtectionKeychain: false`; identity/session key stores must not call `FlutterSecureStorage` directly and should use `SecureStorageWrapper`, because Data Protection Keychain/Keychain without entitlement causes `-34018` fallback/errors in local release builds.
- macOS local notification initialization must provide `InitializationSettings.macOS`; otherwise `flutter_local_notifications` throws `macOS settings must be set when targeting macOS platform` during app startup.
- The FCM module in `lib/core/firebase` must stay decomposed: `FirebaseMessagingService` is only the coordinator/external API, `FirebasePushTokenLifecycle` owns token lifecycle, `FirebasePushInboundService` owns inbound orchestration, `FirebasePushPayloadProcessor` owns push payload processing/server config and account/group updates, and `FirebasePushPresentationHandler` owns foreground/open/native-fallback presentation. Do not collapse these responsibilities back into one monolithic service.
- The push/call payload path should use one shared `FirebasePushPayload`; do not reintroduce separate ad-hoc call-payload DTOs for the UI open path, FCM fallback, and iOS CallKit.
- Push fanout construction is split out of low-level HTTP: keep payload/signature creation in `PushEventFactory`, server runtime metadata in `PushRuntimeMetadataBuilder`, and event dispatch orchestration in `PushEventService`.
- App icon badge state is owned by `AppBadgeService`, which persists unread/missed-call counts and syncs the platform badge instead of letting UI code call the notification plugin directly.
- `IosCallkitService` should remain a native bridge layer with an external callback seam, not an owner of merge/payload orchestration.
- `group_update` push accelerates recovery but is not the only trigger: the client must run `pollRelay()` on normal startup, on `AppLifecycleState.resumed`, and when network connectivity returns.
- Incoming relay group envelopes must preserve `groupId` all the way to `ChatService`; when `groupId` is present, the message must be routed to the group chat target rather than the sender's direct chat target.
- macOS sandbox builds must include `com.apple.security.network.client` in DebugProfile/Release entitlements, otherwise outgoing DNS/WebSocket/HTTPS/TURN connections can fail as `Failed host lookup` or network permission errors.
- macOS sandbox builds for calls/media should include usage descriptions in `macos/Runner/Info.plist` for camera, microphone, local network, contacts, and notifications, plus `device.audio-input`, `device.camera`, `network.server`, `files.user-selected.read-write`, and `personal-information.addressbook` entitlements.
- `Helper.setSpeakerphoneOn` only makes sense on Android/iOS; on desktop/web it should be treated as a no-op and must not crash calls with `enable speakerphone` errors.
- The macOS AppIcon asset catalog should be regenerated from the current primary icon at `assets/app_icon/icon_1.png` so desktop builds do not keep stale artwork.
- Relay control writes, fetch, and blob fetch are parallelized across the selected relays to reduce latency when part of the relay list is unavailable.
- If blob fetch returns only `404` from the current live relay shortlist, runtime expands the read to the remaining configured relays before treating the blob as missing.
- Runtime reliable-message encryption is enabled by config (`enableEncryption: true`).
- Multi-device identity is moving from stage 2 toward stage 3: `AccountIdentity` stores `accountId`, `displayName`, and `devices`; Settings can export `peerlink://pair`, and the receiving device now stages pairing as a pending request that requires explicit approval before merging the incoming `accountId` and server config, while the current `peerId/nodeId` still remains the runtime device id for routing, bootstrap, relay, and crypto sessions.
- Calls are currently TURN-only for all network types.
- Self-hosted deployment flow exists in Settings with staged progress (`1/14 ... 14/14`) and post-deploy service checks.
- Self-hosted endpoints are fixed TLS addresses: `wss://<ip>:443` for bootstrap and `https://<ip>:444` for relay.
- Runtime allows self-signed certs for IP-hosted bootstrap/relay TLS endpoints.
- In self-hosted topology, HAProxy is used only for `signal`/`relay`; TURN/TURNS must be served directly by `coturn`, not proxied through HAProxy.
- Self-hosted TURN configuration must accept both `turn:` and `turns:` URLs.
- Settings server lists now expose availability state, sort by state, and use swipe-to-delete with confirmation.
- On the main Settings screen, bootstrap/relay/turn are represented as aggregated cards; add actions live on the dedicated list screens for each server group.
- `SettingsController` should not absorb presentation/codec/flow logic: keep server-status formatting in `settings_server_status_presenter.dart`, invite encode/parse in `settings_invite_codec.dart`, and pairing request/approve/reject flow in `settings_pairing_flow_service.dart`.
- The `Storage` block in Settings opens by tapping the whole card with a chevron, without a separate `Details` button.
- Top-level Contacts/Chats/Settings pages use compact AppBar-led layouts without descriptive page-copy headers, with tight card spacing and restrained internal padding.
- Interface language is runtime-selectable from Settings via `AppLocaleController`; supported languages currently start with EN/RU/ES/ZH/FR and UI strings should go through `AppStrings` plus per-language dictionaries instead of new hardcoded display text.
- Contacts invite QR/direct-open uses `peerlink://invite?payload=...`, while shared text uses the clickable HTTPS landing URL (`https://simplegear.org/invite?payload=...` by default). Both formats carry the inviter Peer ID plus currently available server configuration, and imports should merge servers instead of replacing existing settings; self-invite links must still merge the embedded server config before skipping contact creation.
- `Share configuration` uses `https://simplegear.org/config?payload=...` with only currently available server config. Web routing opens `peerlink://config?...`, and app-side config deep links merge `bootstrap/relay/turn/push` directly without the QR import mode dialog.
- Android and macOS native runners must forward `peerlink://invite`, `peerlink://pair`, `peerlink://config`, `peerlink://call`, and supported `https://simplegear.org/...` / legacy GitHub Pages links into Flutter through `DeepLinkService`; on macOS the channel is configured from `MainFlutterWindow` and URL handlers are registered early to avoid cold-start link loss.
- The public `web/` landing/invite pages are static HTML/CSS/JS, use real PeerLink icons from `assets/app_icon/icon_1.png`, and localize visible page text through the `web/site.js` language switcher for EN/RU/ES/ZH/FR.
- Contact, chat, and call-history rows share compact card constants through `CompactCardTileStyles`; screen-specific style files should only keep genuinely screen-specific values.
- Contact rows show avatar, one display label (contact name or short peer id), and last-seen text; they must not duplicate name and peer id in the same row.
- Contact rows expose a long-press action menu for renaming the saved display name; the peer ID stays unchanged.
- Direct chat app-bar overflow menu exposes `Add contact` only when the peer is not already saved as a contact.
- Chat rows show avatar, chat title, last message, and unread badge only; last-seen text is intentionally not shown in chat list cards.
- Call history rows should stay compact: use tight spacing between rows and avoid oversized internal padding around the text.
- App typography is centralized in `AppTheme.fontFamily`; top-level text styles, AppBar, NavigationBar, dialogs, snackbars, and inputs should use the same family.
- Contact avatars must survive app restart via local backup restoration before fresh network avatar sync arrives.
- `AvatarService` lives in `lib/core/runtime`; UI must not move avatar storage/blob/broadcast logic back into `ui/state`.
- Incoming media restore must tolerate short network switches: direct blob download uses retry/timeout, and failed downloads schedule a bounded automatic retry.
- Relay media transfer and incoming relay-media retry state/timers live in `RelayMediaTransferService` / `RelayMediaRetryCoordinator`; `ChatController` should only coordinate message state, queues, and UI notifications.
- `RelayMediaTransferService` / `RelayMediaRetryCoordinator` live in `lib/core/relay`, not in `ui/state`; the UI/state layer should only call them and coordinate presentation state.
- For chat-state decomposition, use domain services such as `ChatRepository`, `ChatSummaryService`, `ChatFileQueueService`, `ChatOutboundService`, `ChatInboundService`, `ChatReadStateService`, `ChatContactsService`, and `ChatGroupService`; do not move storage/contacts/group/read-state logic back into `ChatController`.
- Message deletion for an unloaded chat must still update persisted storage and summary state instead of depending on the chat being present in in-memory `chats`.
- Group `memberPeerIds` must be canonicalized (`trim + unique + sort`) before persistence/comparison, otherwise list ordering creates false group-meta writes.
- A local group avatar path must not be considered committed before successful membership-update broadcast; failed fan-out should roll back the staged avatar file.
- Incoming relay-media restore uses persisted bounded retry state, so interrupted placeholders can auto-resume when the chat is opened, the app resumes, or connectivity comes back.
- Incoming media auto-retry must stop after a confirmed relay `blob not found` result; reopening the chat must not restart an infinite restore loop for the same placeholder.
- If the app reopens a chat with an unfinished incoming relay-media placeholder, stale in-progress statuses must be normalized out of endless `Получение из relay` state and then resumed only through the persisted bounded retry path.
- Manual tap while an incoming relay-media restore is already active must not start a second blob download for the same message; UI should report that the media is still loading.
- Incoming relay-media progress must be monotonic; parallel relay candidate callbacks must not move the visible progress/status backwards.
- Late progress callbacks from an old incoming relay-media restore must not overwrite terminal `Ошибка загрузки` or completed local-file state.
- Manual tap on an incoming relay-media placeholder must never crash the app on `blob not found`; the message should stay in `Ошибка загрузки` state instead.
- Relay blob `404 not found` in normal media receive/open flows should be surfaced as a non-throwing missing-blob result, so UI can downgrade to `Ошибка загрузки` without bubbling a runtime exception.
- Relay message ack must wait for durable chat handling; for incoming chat messages, `ChatController` must persist the message/placeholder before the relay envelope is acknowledged.
- Reliable outbound relay operations are now persisted before send attempts: direct payloads, group payloads, and group membership updates must survive app restart and continue retrying from runtime state instead of relying only on in-memory timers.
- Relay polling must distinguish `no messages` from `all selected relays unavailable`; relay outage should not advance the normal empty-poll backoff as if the inbox were simply empty.
- Chat opening initial viewport is single-flight: the UI must not schedule duplicate first-scroll jumps while the first bottom/unread positioning pass is still pending; bottom mode keeps settling for several frames so late media layout changes do not leave the viewport above the actual bottom.
- Initial unread positioning must resolve a real divider/message context by probing the lazy list; do not rely only on index-to-scroll-extent ratios because failed media placeholders have unstable/large heights.
- Reply-to-message navigation should avoid visible zig-zag probes: programmatic message jumps use a monotonic smooth scan toward the target and suppress lazy-load triggers during that scan.
- An already-open chat should mark incoming updates as read only when the user was near the bottom; if the user is scrolled away, keep unread state so reopening can jump to the first unread message.
- Failed incoming media placeholders (`Ошибка загрузки`) must not be used as the initial history-window anchor or unread scroll anchor when opening a chat.
- Chat video-file bubbles render a paused local video frame preview when media bytes are available; the old dark play placeholder remains the fallback when the file is unavailable or preview initialization fails.
- Server-health probing remains type-specific per service, but runtime now has a shared `ServerAvailabilityProvider` contract for bootstrap/relay/turn providers.
- `ServerHealthCoordinator` is the shared runtime orchestration layer for these providers; Settings should consume coordinator-backed availability instead of creating duplicate probe loops.
- Bootstrap/relay/turn availability services now share a common polling/backoff engine, so failed servers move into exponential retry backoff instead of staying on a fixed probe cadence.
- Relay and TURN runtime consumers now prefer coordinator-backed health snapshots too, so server selection and Settings derive from the same shared availability picture.
- Bootstrap availability probes must treat WebSocket connect timeouts as ordinary `unavailable` health results, not as bubbling `TimeoutException`s; only one bootstrap refresh should run at a time.
- Bootstrap runtime `setServer` should treat WebSocket `ready` timeout as a normal connection error with reconnect instead of throwing `TimeoutException`; half-open channel teardown must use a bounded close timeout.
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
4.1. For `lib/core/calls`, extend existing `Call*Controller` modules first instead of pushing responsibility back into `AudioCallPeer`.
5. Update docs in the same change when behavior changes.
6. Add/adjust tests for critical networking/security flows.
7. Treat `pubspec.yaml` as the single source of truth for app versioning; do not manually diverge Android/iOS version metadata.
8. Prevent unbounded file growth: when a file is already large (guideline: `~800+` lines for UI/state, `~500+` for runtime services), new features must be added through domain decomposition (separate classes/services/controllers/helpers via `import` with explicit ownership).
9. Before adding a new feature into a large file, record the architecture choice first: target module boundaries, test strategy, and rationale for not extracting into a separate component.
10. If a file already behaves like a god-object, the next change should prioritize decomposition; adding more logic directly into that file without extraction is considered an architecture baseline violation.
11. Do not use `part` as the end-state architecture during decomposition; `part` is allowed only as a short-lived migration step within one PR or PR series.
12. Before creating a new service, first inspect the existing services in the same bounded context; do not introduce duplicate responsibilities or overlapping service layers.
13. Target decomposition state: separate files and service/controller modules via `import`, explicit constructor/callback dependencies, and no hidden access to parent-file state.
14. If a suitable service already exists but does not yet cover the full scenario, extend that service instead of creating a new duplicate beside it.
15. During refactors and service extractions, place moved services in the target project directories that match their actual responsibility (`core`, `runtime`, `relay`, `security`, `ui/state`, etc.) instead of preserving legacy placement by inertia.
16. Before creating a new service or extracting logic from a large file, first check whether an existing service in the target directory can be extended or reused cleanly without introducing a duplicate layer.

## 5. Non-Functional Baseline

- No silent crash loops on network instability.
- No leaked timers/stream subscriptions.
- No silent crypto downgrade in production paths.

## 6. Under Uncertainty

- Prefer minimal safe changes.
- Validate assumptions against code before writing docs.
- If docs conflict with code, code is source of truth and docs must be updated.
