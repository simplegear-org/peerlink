# NETWORK_FLOW

Last updated: 2026-04-28

This document describes how the current runtime actually behaves, not just the target architecture on paper.

## 1. Startup Flow (AS-IS)

```text
main.dart
  -> StorageService.init()
  -> Firebase/notifications init
  -> NetworkDependencies.create()
    -> Identity/Session/Signature
    -> TransportManager
    -> OverlayRouter
    -> BootstrapSignalingService
    -> TurnAllocator
    -> DhtTransport + KademliaProtocol
    -> HttpRelayClient + ReliableMessagingService + ChatService + CallService
    -> MeshNode.initialize()
    -> NodeFacade
  -> AppBootstrapCoordinator.postBootstrap(...)
  -> UiApp
```

`MeshNode.initialize()` subscribes to signaling streams and peer discovery stream.

## 2. Connection Flow (Messages)

`NodeFacade.sendPayload(targetKind: ChatPayloadTargetKind.direct)`:
1. `MeshNode.connectTo(peerId)`
2. `MeshNode` waits for signaling readiness.
3. Ensures a `PeerSession` exists for peer.
4. `PeerSession.connect()` currently tries **direct WebRTC only**.

There is no active direct->turn->relay failover in message `PeerSession` now.

`NodeFacade.sendPayload(targetKind: ChatPayloadTargetKind.group)` uses the same entry API, but the runtime path switches to relay group fanout with explicit `recipients`.

## 3. Message Send Flow

```text
ChatController
  -> NodeFacade.sendMessage
    -> MeshNode.connectTo(peerId)
    -> ChatService.sendMessage
      -> ReliableMessagingService.send
        -> RelayEnvelope sign/store via HttpRelayClient
```

Important:
- message delivery is relay-based in current runtime,
- reliable-message encryption is active in runtime (`enableEncryption: true`),
- relay runtime now prefers live relays and keeps the working set small, so dead relay entries should not dominate user-visible send latency when healthy relays are available.

Group-specific path (current):
- group text and group media are sent through group relay messaging,
- media uses blob indirection (`upload blob -> send group metadata`),
- media payload encryption uses compact binary `PLG2` format (legacy format decode is still supported),
- large media encryption/decryption is offloaded to background isolate to keep UI responsive,
- large group media prefers chunked blob upload (`/relay/blob/upload/chunk` + `/complete`) with fallback to single upload endpoint.
- group owner synchronizes current membership via `/relay/group/members/update`,
- relay validates membership for group write-path calls,
- group key rotates on add/remove participant events.
- personal avatar sync path: sender uploads avatar blob to relay and sends control event `kind=profileAvatar` with `blobId`; receiver fetches blob and updates local avatar cache.
- group avatar sync path: owner uploads avatar blob to relay and sends service control `groupMembers` payload with `action=avatar` and `avatarBlobId`; receivers fetch blob and update local group avatar cache.
- group avatar updates are intentionally out-of-band (service path), so they are not rendered as regular text/media messages on legacy clients.
- owner-initiated group chat deletion is propagated as service control `groupChatDelete` to all known members before local cleanup; receivers accept it only from the known owner, delete the local chat, and keep a group tombstone so older relay/invite events do not recreate it. Non-owners send `groupMembers` with `action=leave`, the owner removes them from relay membership and rotates the group key, then the leaver deletes the local copy.
- empty relay configuration is treated as relay polling disabled/empty; startup and background polling must not throw when there are no configured relay servers.

Personal media path (current):
- direct chat media uploads the file to relay blob storage first,
- sender then delivers encrypted `direct_blob_ref` metadata through the normal personal reliable-message channel,
- receiver resolves the blob reference and restores media from relay blob storage,
- direct personal media receive now uses only encrypted `direct_blob_ref` plus relay blob download; legacy `fileMeta/fileChunk` receive has been removed,
- direct blob download now uses retry/timeout protection,
- if the current live relay shortlist returns only `404` for a blob, blob fetch expands to the remaining configured relays before declaring the blob missing,
- if incoming media restore fails during a transient network switch, the client schedules a few delayed retries automatically,
- if the app is backgrounded/killed during incoming relay media restore, the persisted placeholder can resume when the chat opens again, when the app resumes, or when connectivity returns,
- if the user taps an incoming file while its relay restore is active, the existing restore remains the only active download for that message,
- visible incoming relay-media progress is monotonic, because several relay candidates may report progress for the same blob fetch,
- relay media upload/download retry, incoming retry state, timers, and result handling are centralized in `RelayMediaTransferService` / `RelayMediaRetryCoordinator`.

## 4. Message Receive Flow

```text
ReliableMessagingService (poll every 2s)
  -> HttpRelayClient.fetch(/relay/fetch)
    -> transient retry/backoff on GET connection drop/timeout
    -> live-relay selection + bounded working set
  -> signature verification + envelope validation
  -> ChatService
  -> NetworkEventBus
  -> UI controllers
```

Ack path:
- successful durable processing triggers `HttpRelayClient.ack(/relay/ack)`.
- for chat messages, relay ack is deferred until `ChatController` handles the message event and persists the local message/placeholder; this prevents media metadata loss if the app is closed during incoming relay-media restore.
- ack request is signed and includes `from` + `signingPub`.
- ack signature payload format: `id|from|to|timestampMs`.
- relay `401 invalid signature` is explicitly logged by `HttpRelayClient`.
- relay fetch treats premature HTTP connection close before headers as a transient relay failure: the failed relay is marked unhealthy and the poll returns an empty batch/falls back to other relays instead of surfacing the exception to UI.
- selected relay operations are parallelized so one dead relay does not add a full sequential delay.
- on startup, contact avatars are restored from local embedded backup first if the stored avatar file path is missing; network avatar sync runs after that.

## 5. Signaling Flow

Bootstrap signaling is used for:
- WebRTC transport signaling,
- call signaling (`call_invite`, `call_accept`, `offer`, `answer`, `ice`, and call media control frames).

`BootstrapSignalingService` provides:
- reconnect/backoff,
- network-change fast reconnect,
- register/register_ack handshake,
- heartbeat (`ping`/`pong`).

## 6. Call Flow

Current policy in `CallService`:
- mode is always TURN (independent of Wi-Fi/4G),
- call media setup uses `AudioCallPeer` + extracted negotiation/video controllers,
- media-ready and video-state acks are exchanged via signaling messages.
- if multiple TURN servers are configured, ICE checks candidates from available servers and uses the first successful route.

## 7. DHT/Overlay Flow

- Overlay router and DHT transport exist and are wired.
- `KademliaProtocol` currently forwards incoming RPC to callback; full iterative lookup workflow is not implemented.

## 8. Operational Gaps

- Centralized bootstrap signaling is still required.
- Message transport session failover stack is not active.
- Runtime encryption is currently disabled.
- Group message fan-out still uses `/relay/group/store` recipient list path (not yet topic-log with server-side sequence stream).
- Integration tests for reconnect/failover/call regressions are still needed.
