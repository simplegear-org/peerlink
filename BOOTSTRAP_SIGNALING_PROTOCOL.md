# BOOTSTRAP_SIGNALING_PROTOCOL

Last updated: 2026-04-12
Version: `v=1`
Transport: WebSocket (`ws://` / `wss://`)
Frame format: UTF-8 JSON

This document describes the frame contract used by the current bootstrap signaling runtime.

## 1. Top-Level Frame

```json
{
  "v": "1",
  "id": "string",
  "type": "string",
  "payload": {}
}
```

- `v`: protocol version (`"1"`)
- `id`: unique frame id
- `type`: frame type
- `payload`: type-specific object

## 2. Registration

Client sends `register` after socket is ready.
Connection is considered established only after `register_ack`.
`payload.peerId` is the stable user id (`peerId v2`).

### 2.1 `register` (client -> server)

```json
{
  "v": "1",
  "id": "...",
  "type": "register",
  "payload": {
    "peerId": "PEER_ID",
    "client": { "name": "peerlink", "protocol": "1" },
    "capabilities": ["webrtc", "signal-relay"],
    "auth": {
      "scheme": "peerlink-ed25519-v1",
      "peerId": "PEER_ID",
      "timestampMs": 1741590002123,
      "nonce": "...",
      "signingPublicKey": "BASE64",
      "signature": "BASE64",
      "legacyPeerId": "OPTIONAL_LEGACY_ID",
      "identityProfile": {
        "stableUserId": "PEER_ID",
        "endpointId": "OPTIONAL_ENDPOINT_ID",
        "fcmTokenHash": "OPTIONAL_HASH"
      }
    }
  }
}
```

`auth` is optional for backward compatibility with older servers.

Server-side auth notes:
- server verifies signature against canonical registration payload;
- current rollout prefers v2 canonical payload and may keep v1 fallback for compatibility;
- if `identityProfile.stableUserId` is present, it must match `payload.peerId`.

### 2.2 `register_ack` (server -> client)

```json
{
  "v": "1",
  "id": "srv-ack-...",
  "type": "register_ack",
  "payload": {
    "peerId": "PEER_ID",
    "sessionId": "optional"
  }
}
```

Client timeout for `register_ack` is short (runtime reconnect logic handles retries).

## 3. Signaling Frames

### 3.1 `signal` (client -> server)

```json
{
  "v": "1",
  "id": "...",
  "type": "signal",
  "payload": {
    "type": "offer|answer|ice|call_*",
    "from": "PEER_A",
    "to": "PEER_B",
    "data": { "...": "..." }
  }
}
```

`payload.type` used by current client includes:
- transport signaling: `offer`, `answer`, `ice`
- call control/media: `call_invite`, `call_accept`, `call_reject`, `call_end`, `call_busy`, `call_media_ready`, `call_video_state`, `call_video_state_ack`, `call_video_flow_ack`

### 3.2 `signal` relay (server -> client)

Server forwards the same signal envelope to `payload.to`.

## 4. Heartbeat

Client periodically sends `ping`.
Server may respond with `pong` (or compatible ack frame if supported by server implementation).

## 5. Peer Discovery (Optional)

Client can send `peers_request`.
If supported, server responds with `peers`:

```json
{
  "v": "1",
  "id": "srv-peers-...",
  "type": "peers",
  "payload": {
    "peers": ["PEER_A", "PEER_B"]
  }
}
```

Runtime behavior for unsupported servers:
- if server returns `error` with `UNKNOWN_TYPE` for `peers_request`, client marks peer discovery as unsupported and continues signaling normally.

Client runtime notes (current implementation):
- after `register_ack`, client sends `peers_request` immediately and then periodically;
- each `peers` frame is treated as a snapshot of currently online peer ids on this bootstrap server;
- client computes `online/offline` transitions from snapshot diff and derives local `lastSeen` timestamp when a peer disappears from snapshot.

## 5.1 Presence Frames (Optional Extension)

Servers may provide explicit presence frames instead of snapshot-only mode.

### `presence_snapshot` (server -> client)

```json
{
  "v": "1",
  "id": "srv-presence-...",
  "type": "presence_snapshot",
  "payload": {
    "peers": ["PEER_A", "PEER_B"]
  }
}
```

### `presence_update` (server -> client)

```json
{
  "v": "1",
  "id": "srv-presence-update-...",
  "type": "presence_update",
  "payload": {
    "peerId": "PEER_A",
    "status": "online|offline",
    "lastSeenMs": 1741590002123
  }
}
```

## 6. Error Frame

```json
{
  "v": "1",
  "id": "srv-error-...",
  "type": "error",
  "payload": {
    "code": "ERROR_CODE",
    "message": "Human-readable message"
  }
}
```

## 7. Minimal Server Requirements

1. Accept `register` and bind `peerId -> websocket`.
2. Send `register_ack`.
3. Forward `signal` frames to destination peer.
4. Support heartbeat (`ping`/`pong`).
5. Return `error` for invalid/unsupported frames.
