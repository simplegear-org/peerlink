# CHANGELOG

All notable PeerLink application changes should be recorded in this file.


## [3.14.3+2026092202] - 2026-09-22

### Changed

- Group membership changes are now owner-only. Clients reject membership
  mutations from non-owners and conflicting owner metadata, preventing an
  untrusted control message from altering or restoring a group.
- Fixed remote-video rendering across Android and iOS after renegotiation by
  retaining the receiver's peer owner for synthetic streams and binding native
  incoming streams as a whole. This prevents stale native track wrappers from
  freezing remote video.
- Delayed timestamp-based call invites older than two minutes are rejected
  before CallKit and in-app incoming-call UI, preventing zombie calls after
  push restoration or resume.
- Migrated the Android app module to AGP built-in Kotlin and updated
  `url_launcher_android` for compatibility. The legacy new-DSL opt-out remains
  only for the current Flutter Gradle Plugin limitation.


## [3.14.1+2026092001] - 2026-09-20

### Changed

- Upgraded the Android build stack to Flutter 3.47.5, AGP 9.0.1, and Gradle
  9.1. Release builds retain R8 minification and resource shrinking.
- Updated Android-facing packages for AGP 9 compatibility, including
  `audioplayers`, `file_picker`, `flutter_secure_storage`, `mobile_scanner`,
  `record`, `saver_gallery`, `share_plus`, `video_player`, and
  `flutter_webrtc 1.6.2+hotfix.3`. File-picker and gallery-save call sites
  now use their current APIs.
- AGP 9 currently runs with its documented Flutter compatibility opt-outs for
  the legacy DSL and Kotlin Gradle Plugin. `flutter_webrtc` and
  `url_launcher_android` still require that temporary mode.
- The upstream `FrameCapturer` bitmap-decoding warning remains in
  `flutter_webrtc 1.6.2+hotfix.3`; no local fork was introduced. The known
  Android remote-video freeze still requires real-device regression coverage.
- Startup no longer waits for server availability probes before showing the UI;
  persisted server configuration is still applied first and health refreshes
  continue in the background.
- Concurrent push device-state sync requests now share one in-flight operation,
  avoiding duplicate device registration and access-policy uploads at startup.

## [Unreleased]

## [3.14.0+2026091701] - 2026-09-17

### Changed

- Added local Profile `About`, remote profile metadata cache and reusable peer
  profile/group information screens. Peer cards and group members now prefer
  local contact names over PeerLink names and Peer IDs; self cards hide peer-only actions,
  and owner/admin labels render when group metadata provides them.
- Group information now reuses compact member cards; owners and admins can add
  participants or remove another non-owner participant with a left swipe.
- Added independent, persisted Messages and Calls notification switches to peer
  and group cards. The default is enabled; schema-v2 access-policy sync carries
  direct/group mute channels so the push server suppresses only matching fanout
  without affecting relay delivery or block state.
- Profile-card photos now preserve the source aspect ratio without circular
  cropping and scale to the available card width.
- Added cross-repository regression coverage for mute/unmute, message/call
  independence, block independence, and schema-v1 compatibility.
- Fixed rapid notification-mute changes so each latest snapshot is synchronized
  after an already active push-policy request.


## [3.13.2+2026091601] - 2026-09-16

### Changed

- One-tap sharing now creates a signed short invite link.
- Relay ACK is now targeted to every exact message replica after durable
  delivery. Partial cleanup retries later without failing delivery; ACK never
  deletes a media blob, whose retention is controlled by its own TTL.
- Relay ACK tombstones now persist recipient/message/acknowledgement/expiry
  metadata and are bounded by durable TTL garbage collection.
- Invite architecture is now split into `features/invites` domain,
  application and infrastructure; `InviteApi` and `PendingInviteStore` keep
  the coordinator independent from HTTP and Settings UI. Android Install
  Referrer is Invite-owned platform infrastructure.
- After accepting a short invite, the accepting peer now best-effort sends its
  configured username and avatar to the inviter.


## [3.13.1+2026091002] - 2026-09-10

### Changed

- Ordinary contact invitations are now a one-action flow: Contacts creates a
  signed short URL and opens the system share sheet immediately.
- Added local PeerLink display name editing in Settings. The optional name is
  included as invite display metadata, while manual contact names are kept.
- Invite resolution now validates version, expiry, invite ID and identity
  binding before applying server configuration, contact and direct-chat state.
- Fixed invite creation to use the public invite API at `tangash.org` while
  shared links continue to use `simplegear.org`.
- The website fallback for a short invite now opens the installed app without
  exposing a legacy payload.
- Added invite client/coordinator and backend persistence integration coverage.
- Usernames now use the existing profile control-message flow for known peers;
  a QR scan immediately sends the scanner profile to the QR owner. Manual
  names are preserved, while legacy names equal to a peer ID update as fallback.
- User QR carries the optional PeerLink name and pre-fills the `Name` field on
  scan.
- Added Android App Links, iOS Universal Links, durable pending-invite resume,
  Android Install Referrer recovery, a safe iOS fallback, and redacted invite
  lifecycle diagnostics.


## [3.13.0+2026091001] - 2026-09-10

### Changed

- Added a common relay replication policy: up to three candidates with durable
  1/1, 2/2, or 2/3 quorum semantics for both messages and media blobs.
- Blob uploads now return exact successful relay locations; direct and group
  media references carry optional `blobRelayServers`, and receivers use them
  first for targeted blob fetch while retaining legacy fallback.
- Separated relay topology discovery from object routing: incoming chat relay
  metadata is stored in the TTL-bounded `PeerRelayDirectory` and no longer
  merges foreign relay endpoints into the persistent configured relay pool.
- Added relay routing and architecture regression coverage.
- Chunked media upload now makes a single five-second attempt per relay before
  failover; a failed relay is locally excluded for two minutes, preventing
  stale shared health from delaying subsequent media.

### Verified

- `dart format .`
- `flutter analyze`
- `flutter test test/architecture` (48 tests)
- `flutter test test/core/relay/http_relay_client_test.dart`
- `flutter test` (449 tests)

## [3.12.9+2026090902] - 2026-09-09

### Changed

- Extracted Moderation into the `lib/features/moderation` bounded context with
  `domain`, `application`, and `infrastructure` layers.
- Added narrow `ModerationReportsApi`, `AccessPolicyApi`, and
  `ModerationStatusApi` contracts; Chat safety and inbound now use contracts.
- Moved durable outbox retry to `ModerationLifecycleService` for startup,
  resume, and connectivity recovery, outside Chat lifecycle.
- Moved HTTP client, delivery, and storage-backed report outbox to moderation
  infrastructure; old `core/runtime` paths remain compatibility exports.
- Added architecture guards for moderation boundaries.
- Relay blobs are now replicated to every available relay in the selected
  working set (up to 3), rather than only to a quorum. A timeout during chunked
  upload excludes that relay from the current operation and storage continues
  on the remaining relays.
- Outgoing replication progress is now one monotonic scale to 100%, without a
  separate completion for each relay.
- Incoming relay media ignores delayed outgoing progress statuses and cannot
  show `Sending 100%` after reception.

### Verified

- `dart format .`
- `flutter analyze`
- `flutter test test/architecture` (48 tests)
- `flutter test`
- `flutter test test/core/relay/http_relay_client_test.dart`
- `flutter test test/features/chat/application/chat_media_restore_service_test.dart`
- `flutter analyze` for the changed relay/chat files.


## [3.12.8+2026090901] - 2026-09-09

### Changed

- Added `ChatHistoryApi` for history loading, pagination, unread anchors,
  persistence, unload, and message-offset lookup.
- Moved direct message mutation in `ChatController` behind `ChatMessagesApi`.
- Added narrow `ChatCleanupApi` and `ChatSafetyApi`; cleanup, moderation,
  access policy, group-key initialization, and relay status no longer leak into
  presentation state.
- Added architecture guards for history, direct message collection mutation,
  and forbidden cleanup/moderation/crypto/relay imports.

### Verified

- `dart format .`
- `flutter analyze`
- `flutter test test/architecture` (43 tests)
- `flutter test test/features/chat` (15 tests)
- `flutter test` (438 tests)


## [3.11.9+2026090802] - 2026-09-08

### Changed

- Added **Block and Report** flow for abusive users.
- Blocking now immediately hides blocked users and their content while submitting a moderation report.
- Added offline-safe report queueing and automatic retry.
- Improved blocked-user handling for direct and group chats.
- Added moderation report integration with the existing moderation dashboard.
- Added 24-hour report handling SLA tracking with approaching-deadline and `OVERDUE` indicators.
- Updated Terms & Safety with explicit zero-tolerance policy for objectionable content and abusive users.
- Updated Terms acceptance version to require acceptance of the new safety policy.
- Preserved metadata-only moderation reporting without exposing private E2EE message content, media, chat history, or encryption keys.
- Added automated coverage for blocking, reporting, offline retry, content visibility, unblocking, and Terms acceptance flows.


## [3.11.8+2026090801] - 2026-09-08

### Fixed

- Fixed Android incoming relay-media restore for direct and group chats: a
  completed download now proceeds once through decrypt, save, message
  persistence, and retry-state cleanup without returning to a download loop.
- Persisted `localFilePath` before best-effort thumbnail generation, so a
  thumbnail failure can no longer invalidate successfully restored media.
- Limited automatic relay retry to actual download/relay availability errors;
  decrypt, save, and message persistence failures no longer restart download.
- Replaced stale interrupted transfer state with `Retrying` instead of a false
  `Download failed`, and allowed fresh progress to replace an old error status.
- Added distinct localized statuses for downloading, decrypting, saving, and
  their corresponding failures. The status is cleared after successful save.

### Diagnostics

- Added privacy-safe `[relay_media]` and `[chat_media]` stage logs covering
  download, decrypt, save, message lookup/replacement/persistence, retry-state
  cleanup, and thumbnail generation.
- Kept these diagnostics available in the application log even in errors-only
  mode and mirrored them to Android log output.
- Throttled download progress diagnostics to integer-percent changes, avoiding
  log rotation that previously hid the start and group restore stages.
- Added storage destination, exception, and stack-trace logging for media save
  failures without logging encrypted payloads or keys.

### Verified

- `flutter analyze`
- `flutter test` (428 tests)
- Android release update installed without clearing application data.
- Direct and group relay media restored successfully on device; retained direct
  trace confirmed download, decrypt, save, SQLite persistence, and retry clear.


## [3.12.7+2026090701] - 2026-09-07

### Changed

- Continued the ChatController architecture refactor: added `ChatMediaApi` /
  `ChatControllerMediaApi` as the UI-facing media application facade.
- Moved file send/cancel, queue resume, outgoing relay-media resume, incoming
  media restore/resume, thumbnails, progress/status helpers, and media
  lifecycle disposal behind `ChatMediaApi`.
- Reduced `ChatController` direct coupling to concrete media coordinators and
  added an architecture guard preventing regression to direct media workflow
  imports.
- Updated architecture backlog and service-map documentation for the new media
  boundary.

### Verified

- `dart format .`
- `flutter analyze`
- `flutter test`
- `flutter test test/architecture`
- `flutter test test/features/chat`
- `flutter test test/core/messaging`
- `flutter test test/core/relay`
- `flutter test test/ui/state`


## [3.12.6+2026090604] - 2026-09-06

### Changed

- Continued the ChatController architecture refactor: replaced the giant
  `ChatControllerComposition.create()` callback contract with cohesive
  presentation/application ports.
- Reduced `ChatControllerDependencies` from a broad top-level dependency bag to
  grouped persistence, messaging, group, media/lifecycle, and safety bundles.
- Added `ChatMessagesApi` and `ChatGroupsApi` application facades so
  ChatController message and group workflows no longer depend on many concrete
  chat services directly.
- Added architecture guards for the new composition ports, grouped dependency
  surface, and ChatController message/group facade usage.

### Verified

- `dart format .`
- `flutter analyze`
- `flutter test test/architecture`
- `flutter test`


## [3.12.5+2026090603] - 2026-09-06

### Changed

- Optimization and refactoring `StorageService`


## [3.12.4+2026090602] - 2026-09-06

### Changed

- Continued PR5 narrow capability migration: added `PresenceApi`, migrated
  presence/restriction/settings/call-history UI surfaces and settings/runtime
  support services from broad `NodeFacade` dependencies to narrow APIs or
  explicit callbacks.
- Moved settings application services under `features/settings/application`,
  leaving old `lib/ui/state/settings_*` paths as temporary compatibility
  exports.
- Completed the next `ChatController` capability-narrowing slice: introduced
  `ChatRuntimeApi` for Chat-owned runtime needs and wired production through
  `ChatRuntimeNodeAdapter` in `lib/app/composition`.
- Migrated `ChatController`, chat application services, and related chat tests
  away from direct `NodeFacade` dependencies while preserving runtime behavior.
- Updated chat screens to read local peer identity from `ChatController`
  instead of reaching through the controller to the runtime facade.
- Added architecture guards that prevent `ChatController` and
  `features/chat/application` from importing unrestricted `NodeFacade`.

### Verified

- `flutter test test/architecture test/ui/state/settings_controller_server_config_test.dart`
- `flutter test test/ui/state/chat_group_flow_service_test.dart test/ui/state/chat_inbound_service_test.dart test/ui/state/chat_outgoing_relay_media_resume_service_test.dart`

## [3.12.3+2026090601] - 2026-09-06

### Changed

- Completed local PR1/PR2 refactor plan status: added a safety-net manifest
  test for CI/architecture/capability/critical-flow coverage and removed
  singleton runtime state from `NetworkDependencies.create`.
- Completed PR7 runtime cleanup first slice: call log/native call bridges moved
  to `features/calls`, contacts moved to `features/contacts`, avatar/profile
  service moved to `features/profile`, and chat Drift database moved to
  `features/chat/infrastructure`.
- Kept old runtime/UI paths as temporary compatibility exports.
- Added architecture guardrails for explicit `core/runtime` inventory,
  migrated forwarding exports, and cross-feature concrete import prevention.
- Updated architecture, refactor-plan, backlog, project-structure, service-map,
  service-API-map, and provenance documentation for PR7.
- Completed PR8 MeshNode integration boundaries: introduced
  `CallControlTransport`, added `ReliableCallControlAdapter`, and moved
  Calls ↔ Chat reliable-control wiring out of `MeshNode` into
  `NetworkDependencies`.
- Added `MeshNodeRuntimeAdapterFactory` / `MeshNodeRuntimeAdapters` so push,
  moderation, device sync, policy sync and signal-router helper construction is
  no longer hidden inside the `MeshNode` constructor.
- Added tests for the call-control adapter, injected call-control transport,
  MeshNode callback-wiring guardrail, and MeshNode `StorageService`
  / integration-helper construction guardrails.

### Verified

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`
- `flutter test test/core/node/reliable_call_control_adapter_test.dart test/core/node/mesh_node_smoke_test.dart test/core/calls/call_service_test.dart test/architecture/feature_boundary_test.dart`


## [3.12.2+2026090504] - 2026-09-05

### Changed

- Added narrow node capability contracts: `MessagingApi`, `CallsApi`,
  `IdentityApi`, `NetworkApi`, `ModerationApi`, and `RuntimeEventsApi`.
- Kept `NodeFacade` as the compatibility aggregate while making it implement
  the new narrow contracts.
- Migrated app push/deep-link/call coordinators and the active call screen from
  unrestricted `NodeFacade` dependencies to the minimum required capability
  APIs.
- Added contract and architecture tests to keep migrated app/call surfaces from
  regressing back to broad `NodeFacade` imports.
- Updated architecture, backlog, README, network-flow, project-structure, and
  service-map documentation for PR5.
- Started PR6 Chat vertical ownership under `lib/features/chat`.
- Moved `Chat` and `Message` into `features/chat/domain`.
- Moved `ChatRepository` into `features/chat/infrastructure` and relocated its
  repository tests to `test/features/chat/infrastructure`.
- Moved non-presentation chat application services/coordinators/helpers into
  `features/chat/application`, leaving `ChatController` and contact/forward
  UI-adjacent services in `lib/ui/state`.
- Kept temporary compatibility exports for old `lib/ui/models` and selected
  `lib/ui/state/chat_*` paths.
- Added an architecture boundary test preventing `features/chat` from importing
  UI implementation code.
- Updated architecture, refactor-plan, backlog, and project-structure
  documentation for PR6.

### Verified

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`


## [3.12.1+2026090503] - 2026-09-05

### Changed

- Added `AppCompositionRoot` / `AppDependencies` as the top-level application
  composition layer, with runtime graph creation still delegated to
  `NetworkDependencies`.
- Added `AppUiDependencies` so UI-facing controllers, repositories, and
  presentation services are constructed outside `UiApp`.
- Moved main app storage/runtime dependency creation out of `main.dart` and
  updated architecture guardrails to allow that construction only in
  `lib/app/composition`.
- Updated architecture, backlog, network-flow, README, project-structure, and
  service-map documentation for the AppCompositionRoot refactor step.
- Extracted initial FCM push callback registration from `UiApp.initState` into
  `AppPushCoordinator`, keeping UI navigation as injected callbacks.
- Completed PR4 by moving push-open relay polling, deep-link dispatch,
  call-state/CallKit orchestration, lifecycle resume handling, and app badge
  synchronization into app-level coordinators.

### Verified

- `dart format lib/app test/app lib/ui/ui_app.dart lib/main.dart`
- `flutter analyze`
- `flutter test test/app/push/app_push_coordinator_test.dart test/app/deep_links/app_deep_link_coordinator_test.dart test/app/calls/app_call_coordinator_test.dart test/app/lifecycle/app_lifecycle_coordinator_test.dart`
- `flutter test`


## [3.12.0+2026090502] - 2026-09-05

### Changed

- Added CI validation for format, analyzer, and tests.
- Added architecture/import-boundary tests covering presentation dependency
  construction, composition ownership, feature boundaries, and platform bridge
  imports.
- Made production storage ownership explicit: `main.dart` now creates the shared
  `StorageService` and passes it into `NetworkDependencies.create(...)`.
- Removed hidden `StorageService()` construction from the main runtime graph
  across network, push, notification, CallKit, and server-merge wiring.
- Kept the FCM background handler as an explicit background-isolate composition
  root with its own storage lifecycle.
- Added `test/` to the public source mirror manifest.
- Updated architecture/service-map/backlog documentation for the completed
  architecture safety net and explicit storage DI steps.

### Verified

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`


## [3.11.2+2026090501] - 2026-09-05

### Changed

- Updated the app version to `3.11.2+2026090501`.
- Changed the Apple-platform app category from `Utilities` to
  `Social Networking`.
- Updated the official hosted `flutter_webrtc` dependency from `1.5.0` to
  `1.6.1` and the iOS WebRTC SDK from `144.7559.09` to `150.7871.01` to remove
  the reference to the App Store-prohibited
  `RPSystemBroadcastPickerView.buttonPressed:` API. No local fork is used.

### Verified

- `flutter analyze`
- `flutter test`
- `flutter build ios --release --no-codesign`
- The built iOS application does not contain the
  `RPSystemBroadcastPickerView.buttonPressed:` string.


## [3.11.1+2026090102] - 2026-09-01

### Changed

- The `POST /devices/access-policy` client now reads stale push-server
  responses and retries the snapshot above `effectivePolicyVersion`, so unblock
  does not leave the old `blockedPeerIds` snapshot active after local policy
  version rollback.


## [3.11.0+2026090101] - 2026-09-01

### Changed

- Added a single push device-state sync path: token registration and
  access-policy snapshots now run together on startup/resume, push-token
  registration, push-server changes, block/unblock, and contacts-only changes.
- Push device registration failures no longer prevent the access-policy snapshot
  sync from running for reachable push servers.
- Access-policy sync timestamps are normalized to UTC milliseconds before
  signing, matching the push server canonical signature format.
- iOS signing now uses a single app target/profile; the Notification Service
  Extension and App Group entitlement are not used for server-side push
  blocking.
- On startup with completely empty server configuration, the app now
  best-effort fetches `https://simplegear.org/config/initial-server-config.json`
  and imports bootstrap/relay/TURN/push from the public `Server configuration`
  QR payload; site unavailability does not block startup.


## [3.10.2+2026082701] - 2026-08-27

### Changed

- Moderation is split into bounded services: the `/moderation/*` HTTP client, delivery orchestration, policy snapshot, and UI gate no longer spread through push/UI layers.
- After appeal submission the account restriction screen is hidden, but the persisted ban still blocks outgoing messages and calls until `unban`.
- The client applies `moderation_policy action=unban` and clears the local ban.
- Warning now uses a fullscreen screen with a `Continue` button; Settings shows the current warning/ban below Peer ID/QR in red.
- The iOS native push bridge now immediately forwards silent `moderation_policy` payloads to Flutter while the app/engine is alive.
- App restart no longer shows fullscreen warning/ban again after warning acknowledgement or appeal submission.
- The client verifies moderation-policy `signedStatus` when `MODERATION_STATUS_SIGNING_PUBLIC_KEY` is set and rejects unsigned/fake moderation events.
- App documentation is synchronized with the completed App Store UGC/moderation phase.

### Verified

- `dart analyze`
- `flutter test test/core/runtime/moderation_api_client_test.dart test/ui/state/app_restriction_controller_test.dart test/ui/screens/chat_report_actions_test.dart test/core/runtime/moderation_report_service_test.dart test/core/runtime/moderation_policy_service_test.dart test/core/firebase/firebase_push_payload_test.dart`


## [3.10.1+2026082601] - 2026-08-26

### Changed

- The client now persists `moderation_policy` push events: warnings show a warning message, and bans open the account restriction screen while keeping appeal submission available.
- Warning/ban text is rendered in the user's locale and includes report count plus unique reporter count without exposing reporter Peer IDs.
- The client now polls `/moderation/status` on startup/resume and force-registers its push token so moderator warn/ban still applies after a push-server restart.
- When a ban is persisted, the app does not present regular incoming push messages/calls or open communication UI.
- UGC reports are now metadata-only: message text/media is not sent to moderators, and the selected message is hidden locally for the reporter.
- Group-message reports target the message author and send only metadata (`groupId`, message id/type/timestamp), without content.
- New-client push registration sends a v2 identity binding in the existing `/devices/register` request so the server can bind `peerId` to `signingPub` without an extra request.
- Documentation was updated for the new moderator UI: reported-user/reporter aggregates with total/direct/group counters plus a general metadata-only report list.


## [3.10.0+2026082401] - 2026-08-24

### Added

- Added a `Privacy & Safety` Settings section with a contacts-only messages/calls switch, a short safety policy summary, and a link to the blocked Peer ID list.
- Added local Peer ID blocking: blocked senders do not create visible incoming messages, calls, or push notifications.
- Fixed call blocking: outgoing calls to blocked Peer IDs no longer start, and Android fullscreen notifications plus iOS CallKit check the native blacklist copy before showing incoming calls.
- Added `Block user` / `Unblock user` actions in direct chats and on the Contacts tab.
- Blocked contacts are marked with a block icon in the contact list.
- Added a dedicated blocked users screen; saved contact names are shown when available.
- Added EN/RU/ES/FR/ZH translations for the new privacy/safety UI.

### Changed

- Updated the app version to `3.10.0+2026082401`.
- Incoming bootstrap/push call invites and push-open handling now check local privacy/block rules before showing calls or notifications.

### Verified

- `flutter analyze`
- `flutter test test/core/calls/call_service_test.dart test/core/runtime/peer_access_control_service_test.dart test/ui/state/chat_inbound_service_test.dart`
- `flutter build apk --debug`
- `flutter build ios --debug --no-codesign`


## [3.9.4+2026082301] - 2026-08-23

### Changed

- Android release builds now enable R8 minify and resource shrinking; AGP 9+ migration remains a separate backlog task until Flutter/Gradle/plugin compatibility is verified.
- Call history now shows the current contact name when a contact is saved; without a contact it keeps the short peer id fallback.
- Incoming accept runtime-enrichment wait was increased to 8 seconds so updated clients can apply bootstrap/TURN metadata before answering a call.
- Critical call commands (`call_invite`, `call_accept`, `call_reject`, `call_end`) are now duplicated through the direct reliable control payload `__peerlink_call_control_v1__` and also retried by bounded bootstrap-signaling timers.
- After a call is active, stopped inbound RTP/media stats while outbound traffic continues is no longer treated as a healthy channel: the call enters visible recovery and initiates an ICE restart offer.

### Fixed

- Fixed `Answer` failing with `Signaling is not ready`: when bootstrap is temporarily unavailable, the answer is sent through the reliable fallback while signaling keeps recovering.
- Fixed `Reject`/`End` commands getting lost and leaving the other side ringing indefinitely.
- Fixed terminal call resets that could close the caller locally while leaving the callee on an active screen with `Call transport interrupted`.
- Fixed calls dropping immediately after answer because of a late reliable `call_invite` retry: a duplicate for the current `peerId/callId` is no longer converted into `call_busy`.
- Fixed Android release calls dropping immediately after answer by adding app-level R8 keep rules for `flutter_webrtc` / native WebRTC classes.
- Removed unsafe Android `getLocalDescription()` calls from offer/answer guards to avoid native null-SDP crashes right after accepting a call.
- Fixed network-switch calls looking active after the real media path had died just because channel byte counters kept increasing.

### Verified

- `flutter test test/core/calls`
- `flutter analyze`
- `flutter build apk --release`


## [3.9.3+2026082201] - 2026-08-22

### Changed

- Updated release metadata to `3.9.3+2026082201` and source snapshot tag `source-v3.9.3-build-2026082201`.
- Pinned the Android/iOS WebRTC dependency to `flutter_webrtc 1.5.0` to avoid the Android remote-video freeze regression when video is enabled later in a call.
- Kept the app version on the main Settings screen only in About/Legal, removing the duplicate top footer.

### Fixed

- Fixed call-end push/deep-link handling so `call_invite` payloads with `callAction=end` do not reopen an incoming call and instead terminate the runtime session first.
- Bound outgoing call timeout to the current call epoch after runtime tracking reset so late timers cannot affect a newer call.
- Made the in-call local self-preview transparent while local video is off and opaque black only while local video is being sent.
- Throttled open-chat read marking and tightened the bottom threshold to reduce redundant read events while scrolling.


## [3.9.2+2026081501] - 2026-08-15

### Changed

- Updated release metadata to `3.9.2+2026081501` and source snapshot tag `source-v3.9.2-build-2026081501`.

### Fixed

- Fixed self-hosted TURN deployment credentials to use the configured `peerlink` account consistently.
- Fixed public snapshot validation for changelog entries that include build suffixes.


## [3.9.1] - 2026-08-14

### Changed

- Cleaned public README files so they reference only files and workflows
  included in the public source mirror.
- Moved the AI-authorship notice near the top of the English README.
- Updated About & Legal Settings UI to separate product version, open-source
  license, version-specific source link, and third-party license action.
- Added MPL-2.0 source headers to project-authored platform and tooling files.
- Updated public snapshot metadata for `3.9.1+2026081401`.

### Fixed

- Hardened public mirror tooling with source metadata generation and snapshot
  consistency validation.
- Fixed release preparation parsing so Flutter hook output is not captured as
  part of the release version.

## [3.9.0] - 2026-08-14

### Licensing

- PeerLink X source snapshots beginning with this release are distributed under
  Mozilla Public License 2.0 (MPL-2.0).
- Earlier public releases were distributed under MIT.
- Separate commercial licensing may be available.
- The public GitHub repository is maintained as an append-only public source
  snapshot mirror rather than a copy of internal development history.

## [3.8.0] - 2026-08-12

### Added

- Added outbound message receipt/read-state: 1 check after confirmed relay send, 2 checks after durable receiver save, and 3 checks after read.
- Group chats aggregate 2/3 checks by `at least one participant delivered/read`; per-peer receipt maps are persisted in message JSON.

### Changed

- Outgoing message status checks now render as overlapping marks.
- Chat list rows now show top-right receipt checks for the last outgoing message and the last-message time/date as `HH:MM`, `DD:MM`, or `DD:MM:YY`.
- Placeholder `File` and `Location` items were removed from the chat attachment sheet; it now keeps `Gallery`, `Paste`, and `Cancel`.
- The app version was moved to the top of the main Settings screen with the existing footer formatting and inter-section spacing.
- Release version is now `3.8.0+2026081201`.

### Verified

- `dart analyze`
- `flutter test test/ui/state/chat_group_flow_service_test.dart test/ui/state/chat_inbound_service_test.dart test/core/runtime/storage_service_chat_messages_test.dart`

## [3.7.6] - 2026-08-12

### Changed

- Chat initial viewport now uses a reversed list: opening stabilizes the bottom first, then jumps to the first unread message without visible scan jumps.
- Initial history loading keeps the latest window again; the persisted first unread anchor is resolved separately for startup positioning.
- Leaving a chat unloads loaded messages from memory after persisting them, reducing retained heavy media history.
- Video bubbles now render a compact black placeholder with a play overlay; native video thumbnail generation on Android/iOS/macOS was removed, while image thumbnail generation remains.
- Dependencies were updated for the current release: Firebase Core/Messaging, file_picker, share_plus, flutter_secure_storage, and sqlite3_flutter_libs.

### Fixed

- Android release docs now require checking that the APK contains `lib/*/libsqlite3.so`; `sqlite3_flutter_libs 0.6.0+eol` must not be used without a separate native sqlite migration.
- iOS Podfile now declares modular headers for `FirebaseMessaging`.

### Verified

- `flutter test test/ui/state/chat_repository_test.dart`

## [3.7.3] - 2026-08-11

### Changed

- Outbound group media can now deliver the encrypted blob reference directly to recipients after a successful blob upload when relay group write is rejected because the relay has stale group membership.
- Successful direct fallback for group media discards the pending group payload so the reliable scheduler does not retry an already delivered message.
- `owner mismatch` during group membership synchronization is treated as terminal for the pending `groupMembers` operation and removed from retry.
- Resumed relay-media sends now mark a message as sent only after a confirmed relay store receipt.

### Verified

- `flutter test test/ui/state/chat_group_flow_service_test.dart test/ui/state/chat_outgoing_relay_media_resume_service_test.dart`
- `flutter analyze`

## [3.7.0] - 2026-08-09

### Added

- Added a `Server sharing via push` Settings section with toggles for sending local server metadata and receiving server metadata from other clients.

### Changed

- When local server sharing is disabled, push events no longer include `servers` or `priority_servers`.
- When receiving external servers is disabled, incoming push/runtime payloads no longer merge received bootstrap/relay/push/turn servers into local configuration.
- The receive toggle is available only while local server sharing is enabled; disabling sharing also disables receiving.
- Android release metadata is now `3.7.0+2026080901`.

### Verified

- Built Android release artifacts: `build/app/outputs/bundle/release/app-release.aab` and `build/app/outputs/flutter-apk/app-release.apk`.
- `flutter analyze` passes with no issues.
- APK metadata was checked: `versionName=3.7.0`, `versionCode=2026080901`, release v2 signing is valid.

## [3.6.6] - 2026-08-06

### Added

- Added generated local image/video thumbnails for chat media; native Android/iOS/macOS thumbnail bridges extract usable video frames, and image thumbnails are generated off the UI isolate.
- Added cached asynchronous media-file availability checks so chat bubbles do not block rebuilds on synchronous file-system probes.

### Changed

- iOS deployment target and Flutter framework `MinimumOSVersion` are now `15.0` for App Store Connect's Spring 2027 upload requirement.
- Direct chat media blob bytes are encrypted before relay upload and marked with `mediaCipher=direct_session_v1` in `direct_blob_ref` metadata.
- Outbound direct/group media preparation, upload, local save, and thumbnail creation now go through a shared `ChatMediaOutboundService`.
- Video bubbles now render stored thumbnails with a play overlay instead of initializing `video_player` inside every message preview.
- Settings server summary cards and exported QR payloads refresh from availability streams, and storage breakdown loading is cached briefly.
- Contacts rows update presence per row instead of rebuilding the whole list for every presence tick.
- Desktop/web pointer dragging is enabled through the shared app scroll behavior.

### Fixed

- Removed unused system Contacts access from iOS/macOS: no `NSContactsUsageDescription`, no macOS address-book entitlement, and no `flutter_contacts` dependency.
- Thumbnail files are deleted together with managed media when a message is removed.

## [3.6.5] - 2026-08-01

### Added

- Added a native Android FCM handler for `call_invite` data pushes: inactive apps show high-priority fullscreen call notifications that open `peerlink://call?...`.
- Added an Android bridge for clearing call notifications from the status bar after the Calls screen is viewed.

### Changed

- Standard FCM incoming-call pushes are now data-only; the client decides how the call is presented.
- Foreground push on iOS and Android no longer shows system notifications: messages update UI/counters, calls show the in-app incoming-call screen.
- Active iOS apps no longer report incoming VoIP pushes to CallKit; CallKit remains for background/terminated states.
- The push server now normalizes FCM data payload values to strings, including JSON for nested `servers`.
- The chat composer uses sentence capitalization, multiline keyboard input, and the newline key; sending remains a UI button action.
- When the keyboard opens, the chat screen raises the list and composer above it while preserving the bottom position.
- Grouped call history now displays the latest call status instead of the aggregate missed-call count.

### Fixed

- Android no longer shows push/local notifications while the app is active; messages update chat counters and calls use the visible incoming-call screen.
- Android call notifications are removed from the status bar after call information is viewed in the app.
- Missed Android calls are no longer marked seen automatically when history is recorded, so the app badge keeps the count until the Calls screen is opened.
- Fixed a race in the `peerlink_servers` signal test by creating `register_ack` waits before sending register frames.

## [3.6.4] - 2026-07-31

### Added

- Added `Forward` to the message long-press menu: selecting it opens a recency-sorted list of chats and contacts, then duplicates the selected text or media message into the target chat.
- Added a focused `ChatForwardService` plus unit coverage for target sorting and text/media forwarding so forwarding logic does not grow inside `ChatScreen`.
- Added a user-facing Android fallback for iPhone Dolby Vision/HDR video playback failures, with an action to open the file in another app.

### Changed

- Incoming relay media that was not fully restored because servers became unavailable now remains resumable and can continue on chat open, app resume, and connectivity restoration.
- Media forwarding now starts after the target picker closes and uses asynchronous file checks so selecting a target does not block UI animations.
- Existing VSCode launch profile names are preserved, but profiles no longer pin a concrete `deviceId`; select the physical or virtual device in VSCode before running the chosen profile.
- iOS metadata is synchronized for release `3.6.4+2026073101`.

### Fixed

- `RelayMediaRetryCoordinator` no longer treats temporary relay unavailability as a terminal failure for unfinished incoming media; confirmed `not_found` still stops retries.
- Stale in-progress incoming media placeholders are normalized and resumed through persisted retry state instead of staying stuck in `Получение из relay`.
- Android foreground-service restore was removed, so the app no longer requests `FOREGROUND_SERVICE_DATA_SYNC`.
- Android debug builds pass after the media restore and forwarding changes.

## [3.6.3] - 2026-07-30

### Changed

- The user-visible app name on Android, iOS, macOS, and iOS CallKit is now `PeerLink X`; bundle id, package id, and the `peerlink://` custom scheme are unchanged.
- Invite and server-configuration share text is now localized and includes two links with the same payload: a primary `peerlink://...` direct app link and an `https://simplegear.org/...` fallback.
- Invite QR/direct-open still uses `peerlink://invite?payload=...`; server configuration export now also exposes the direct-link format `peerlink://config?payload=...`.
- Call runtime was decomposed further into bounded modules for media readiness, remote control, renegotiation, video signaling/transceivers/quality, terminal lifecycle, runtime tracking, epoch timers, and diagnostics.
- Chat state was decomposed further into focused inbound/outbound handlers, file/history/cleanup/message coordinators, reply metadata resolution, account payload decoding, and message bubble sub-widgets.
- Firebase push payload processing was split into parsers, server-storage merge/update parsing, and log formatting helpers.
- Android release metadata is now `3.6.3+2026073001`, producing `versionName=3.6.3` and `versionCode=2026073001`.
- iOS generated build settings were synchronized with `pubspec.yaml`: `MARKETING_VERSION=3.6.3`, `CURRENT_PROJECT_VERSION=2026073001`.

### Fixed

- Removed unused and sensitive Android permissions from the final manifest, including `MANAGE_EXTERNAL_STORAGE`, storage/media permissions, contacts/call-log, exact alarm, Wi-Fi change/state, `BLUETOOTH_ADMIN`, and vendor badge permissions.
- Verified release APK/AAB no longer contain `USE_EXACT_ALARM` or `MANAGE_EXTERNAL_STORAGE`; the final manifest keeps only permissions needed for QR, networking, notifications/push, WebRTC audio/calls, and background runtime.
- Added real SQLite `StorageService` coverage for chat message write/read so message persistence regressions are checked against the actual database path.

## [3.6.1] - 2026-07-21

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

### Fixed

- Self-hosted deployment now avoids pipe-based `sudo` auth and downloads the remote bootstrap script before executing it instead of piping `wget` directly into `bash`, preventing false failures with exit code `141`; failed remote commands also include the last output lines in the error.
- Self-hosted deploy progress, readiness retries, and known deploy errors now use typed events/exceptions and are localized through the app dictionaries instead of hardcoded service text.
- iOS `Release` local installs now use the `AdHoc` provisioning profile instead of the App Store `iOSProd` profile.

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
- Updated the architecture documentation to record the new `MeshCallPushHelper` boundary and the current decomposition status of the `mesh_node` / call-runtime layer.

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
