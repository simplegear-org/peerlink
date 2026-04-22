# CHANGELOG

All notable PeerLink application changes should be recorded in this file.

## [2.4.1] - 2026-04-22

### Changed

- Reworked `Settings` server management UX:
  - bootstrap/relay/turn are now shown as aggregated cards on the main Settings screen,
  - each server group is managed on its own dedicated list screen,
  - add actions for bootstrap/relay/turn were moved to those dedicated list screens,
  - server list headers/descriptions were unified across bootstrap/relay/turn screens.
- Updated the `Storage` block in Settings to use the same navigation pattern as server cards:
  - removed the standalone `Details` button,
  - opening storage details now happens by tapping the whole card,
  - added right-side chevron navigation affordance.

### Fixed

- Contact avatars should no longer disappear after app restart:
  - `AvatarService` now keeps an embedded backup for contact avatars,
  - startup restores the last local avatar first and only then performs network avatar sync.
- Improved incoming media download resilience across network switches:
  - direct blob download now uses retry/timeout protection,
  - if an incoming file breaks during `Wi‑Fi -> mobile` transition, the client schedules a bounded delayed auto-retry,
  - `Failed to download` UI state no longer looks like an infinite loading spinner.

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
