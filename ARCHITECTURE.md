# ARCHITECTURE

Last updated: 2026-04-22

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
- Overlay router + message dedup cache.
- HTTP relay client with live-relay preselection, bounded active pool, quorum write/quorum ack, and status tracking.
- Reliable messaging envelopes, relay poll loop, ack flow.
- Group chat delivery via relay group envelopes.
- Personal media delivery via relay blob + encrypted direct blob-reference metadata.
- Group media and group text blob transport path (single upload + metadata fan-out).
- Server-side group membership enforcement in relay write path.
- Group membership sync via `/relay/group/members/update`.
- Group key rotation on membership changes.
- Chunked blob upload support in relay protocol (`chunk` + `complete`) with client fallback.
- Group media encrypted bytes use compact binary `PLG2` payload format (legacy decode path remains).
- Group media crypto for large payloads is offloaded from UI isolate to background isolate.
- Relay fetch GET path includes transient retry/backoff on connection-drop errors.
- Relay runtime paths now prefer only live relay servers, capped at 3 selected servers for message/media operations.
- Relay control writes, fetch, and blob fetch are parallelized across selected relays to avoid cumulative timeout delays from dead servers.
- Call stack with extracted controllers:
  - `CallNegotiationController`,
  - `CallVideoController`,
  - `CallVideoState`.
- TURN allocator and TURN server configuration from settings.

Current constraints:
- Bootstrap signaling remains centralized by contract, but runtime now keeps multiple bootstrap WebSocket channels alive through an aggregator.
- DHT layer is skeletal (`KademliaProtocol` pass-through API).
- Message encryption is available but disabled by runtime config (`enableEncryption: false`).
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
- Screen composition pattern is standardized:
  - `*_screen.dart` for orchestration/state wiring,
  - `*_view.dart` for layout widgets,
  - `*_styles.dart` for design constants.
- Chat modules are split into focused units (`chat_screen_view`, `chat_screen_helpers`, `chat_screen_unread_divider`, `chat_screen_media_actions`, `chat_controller_parts`, `chat_controller_media`).
- Settings uses aggregated bootstrap/relay/turn cards on the main screen and dedicated list screens for managing each server group.

### 4.2 Core Entry (`lib/core/node`)

- `NodeFacade`: stable API for UI.
- Unified messaging/blob entrypoints live here: `sendPayload(...)`, `uploadBlob(...)`, `downloadBlob(...)`.
- `MeshNode`: composition/lifecycle/signaling routing.

### 4.3 Runtime (`lib/core/runtime`)

- `NetworkDependencies`: dependency graph builder.
- `AppBootstrapCoordinator`: post-bootstrap wiring (servers, background tasks).
- Storage and repositories (`StorageService`, contact/call repositories).
- Runtime storage cleanup is explicit-only:
  - users can clear concrete categories (`Media files`, `Messages database`, `Logs`, `Settings and service data`) from Settings,
  - heuristic orphan-media cleanup is intentionally removed because it is unsafe with legacy media recovery paths.
- The `Storage` block in Settings now follows the same navigation pattern as the server cards: tap the whole card and use the chevron to open details.
- `IdentityService` provides stable `peerId` (v2) plus legacy id metadata for compatibility.
- `SelfHostedDeployService`: SSH deployment orchestration for personal server stack, staged progress (`1/14 ... 14/14`), post-deploy connectivity checks, and fixed self-hosted endpoints `wss://<ip>:443` / `https://<ip>:444`.
- Server-health services share the `ServerAvailabilityProvider` contract so future runtime orchestration can work with bootstrap/relay/turn probing through one interface.
- `ServerHealthCoordinator` owns the shared bootstrap/relay/turn health services and starts them after app bootstrap, so runtime and Settings use the same availability state instead of duplicate probe loops.
- `HttpRelayClient` and `TurnAllocator` are wired to coordinator-backed relay/turn availability lookups, so runtime routing decisions can reuse the same shared health snapshots that drive Settings.
- The coordinator also reacts to app resume and connectivity changes, triggering shared health refreshes without requiring Settings to be opened.
- Relay critical paths can request a selective coordinator-backed refresh for just the current relay shortlist when the shared relay snapshot is stale, keeping send/blob decisions fresh without refreshing the whole relay set.
- TURN call setup can request a selective coordinator-backed refresh for just the current TURN shortlist when shared TURN health is stale, so TURN-backed `rtcConfig` stays fresh without reprobeing the full TURN set.
- Application versioning is sourced from `pubspec.yaml` (`version: x.y.z+n`) and propagated to Android/iOS through Flutter build variables.

### 4.4 Messaging (`lib/core/messaging`, `lib/core/relay`)

- `ReliableMessagingService`: envelope encode/decode, replay checks, relay polling.
- `HttpRelayClient`: `/relay/store`, `/relay/group/store`, `/relay/group/members/update`, `/relay/fetch`, `/relay/ack`, blob APIs.
- Relay strategy:
  - active relay pool is capped,
  - runtime operations preselect only live relays and use at most 3 servers,
  - writes and ack use quorum,
  - fetch aggregates across the active pool with per-relay cursors,
  - dead relays are excluded from the active path whenever healthy relays are available.
- Personal media/blob strategy:
  - upload once to relay blob storage using deterministic direct scope,
  - deliver encrypted `direct_blob_ref` over the normal personal reliable-message path,
  - receive personal media only through `direct_blob_ref` plus relay blob download,
  - direct blob restore now wraps download with retry/timeout protection,
  - transient incoming restore failures schedule a bounded delayed retry.
- Group media/text blob strategy:
  - preferred for large payloads: chunked upload (`/relay/blob/upload/chunk`, `/relay/blob/upload/complete`),
  - fallback: single-shot upload (`/relay/blob/upload`),
  - receive path fetches `/relay/blob/:blobId`,
  - media/blob receive path should not stall on sequential waits for unavailable relays when live relay candidates exist.

### 4.5 Calls (`lib/core/calls`)

- `CallService` handles call state machine.
- `AudioCallPeer` owns media peer connection and track management.
- Negotiation/video concerns extracted into dedicated controllers.
- Current call policy: TURN-only for all network types.

### 4.6 Signaling (`lib/core/signaling`)

- `BootstrapSignalingService` over WebSocket.
- `MultiBootstrapSignalingService` aggregates multiple bootstrap connections into a single runtime signaling surface.
- Handles reconnect, registration, signal frames, optional peer discovery.
- Outgoing signaling (`call_invite`, `offer`, `answer`, `ice`) is sent to every bootstrap channel where the target peer is visible through `peers` snapshots; if there is no match, fallback is all connected bootstrap channels.
- Registration uses stable `peerId` (v2); auth proof may include `legacyPeerId` and `identityProfile`.
- For self-hosted IP endpoints, runtime accepts self-signed TLS certs in bootstrap and relay clients (IP-host only).
- In self-hosted topology, HAProxy terminates only `signal` (`:443`) and `relay` (`:444`); TURN/TURNS is served directly by `coturn` on `3478/5349`.

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
- Documentation must track runtime truth (not target-only intent).

## 6. Near-Term Architectural Priorities

1. Re-enable and harden encrypted messaging path end-to-end.
2. Decide and implement transport strategy for message sessions (direct-only vs failover stack).
3. Expand group transport from recipient fan-out to server-side sequence log (topic style).
4. Expand DHT from skeleton to working lookup/RPC workflows.
5. Reduce bootstrap centrality (move signaling toward overlay/DHT).
6. Add integration tests for signaling/reconnect/call stability.
