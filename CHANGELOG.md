# CHANGELOG

All notable PeerLink application changes should be recorded in this file.

## [2.11.1] - 2026-05-03

### Added

- Contacts now include an Invite sheet with a `peerlink://invite` QR/deep link; opening it imports the inviter as a contact and merges the included available server configuration.
- Shared invite text now uses a clickable HTTPS landing URL while keeping the `peerlink://invite` app link for QR/direct opening; invite import accepts both formats.
- Added the public `https://simplegear.org` landing/invite page with a full-page language switcher for supported languages, open-source repository links, placeholder App Store / Google Play links, and real PeerLink web icons instead of Flutter defaults.
- Contact rows now open a long-press action menu with `Rename`, allowing saved display names to be updated without changing the peer ID.
- Direct chats with unknown peers now show `Add contact` in the top-right chat menu.
- Chat screens now show a floating down-arrow button after scrolling upward; tapping it jumps to the first unread message when present, otherwise back to the bottom.

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

## [2.2.1+1] - 2026-04-20

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
