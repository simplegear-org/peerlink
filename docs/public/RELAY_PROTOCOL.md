# RELAY_PROTOCOL

Last updated: 2026-09-16
Status: implementation-aligned draft

This document describes the relay contract as the current runtime uses it today.

## 1. Purpose

Defines the relay-backed delivery contract used by the current runtime.

## 2. Roles

- Client node: stores/fetches/acks envelopes.
- Relay server: stores encrypted/signed envelopes and serves fetch/ack API.

## 3. Envelope Model

Client sends relay envelope with fields:
- `id`
- `from`
- `to`
- `timestampMs`
- `ttlSeconds`
- `payload` (bytes)
- `signature`
- `senderSigningPublicKey`

Runtime behavior:
- envelope payload itself contains a reliable envelope (`plainMessage`, `secureMessage`, handshake types),
- receive path verifies signature before processing.
- relay server verifies signatures on relay API endpoints (`store`, `group/store`, `group/members/update`, `ack`, blob upload/finalize).

Signature payload for envelope verification:

- `id|from|to|timestampMs|ttlSeconds|` + raw `payload` bytes

## 4. HTTP API (used by client)

- `POST /relay/store` — store envelope
- `POST /relay/group/store` — store one signed group envelope and fan-out to listed recipients
- `POST /relay/group/members/update` — update authoritative group membership on relay
- `GET /relay/fetch?to=<peerId>&limit=<n>&cursor=<optional>` — fetch envelopes
- `POST /relay/ack` — acknowledge delivered envelope
- `POST /relay/blob/upload` — upload encrypted blob payload (single-shot)
- `GET /relay/blob/:blobId` — fetch blob payload by id
- `POST /relay/blob/upload/chunk` — upload one chunk of large blob
- `POST /relay/blob/upload/complete` — finalize chunked upload and materialize blob

`/relay/ack` request body now includes:

- `id`
- `from`
- `to`
- `timestampMs` (`ts`)
- `signature` (`sig`)
- `senderSigningPublicKey` (`signingPub`)

Ack signature payload:

- `id|from|to|timestampMs`

ACK semantics:

- the client targets every exact relay replica returned by multi-relay fetch;
- partial cleanup is best-effort and retried later without failing durable
  delivery;
- ACK deletes only the matching message envelope, never a media blob;
- relay stores a bounded, durable `(recipient, messageId, ackedAt, expiresAt)`
  tombstone to make repeated ACK/store handling idempotent within retention.

Blob upload signature payload:

- `id|from|groupId|fileName|mimeType|timestampMs|ttlSeconds|` + raw blob payload bytes

Direct media note:

- personal media uses the same blob upload contract,
- client derives a deterministic direct blob scope in `groupId` form: `dm:<peerA>|<peerB>` (sorted peer ids),
- actual chat delivery of personal media happens through encrypted `direct_blob_ref` metadata sent over the normal personal reliable-message channel.

Group membership update signature payload:

- `id|from|groupId|ownerPeerId|member1,member2,...|timestampMs|ttlSeconds`

## 5. Group Messaging over Relay

Current group runtime uses relay as source of truth:

- group text and group media are delivered through group relay path,
- group media is uploaded once as blob and distributed through group message metadata,
- group media encrypted payload is packed in compact binary format (`PLG2`) with legacy decode fallback on client side,
- large media crypto operations are executed in background isolate on client side,
- for large blobs client attempts chunked upload first (`/chunk` + `/complete`), then falls back to single-shot `/relay/blob/upload` if chunk API is unavailable.
- group membership is synchronized by group owner through `/relay/group/members/update`,
- relay enforces membership on group delivery path (`/relay/group/store`);
  blob upload endpoints are storage-only signed writes,
- group key rotates when membership changes (add/remove participants).

## 5.1 Personal Media over Relay

Current personal media runtime uses relay as blob storage:

- file payload is uploaded once through `/relay/blob/upload` (or chunked blob upload when available),
- before upload, a health-aware working set of at most 3 relays is selected; the
  blob uses the shared durable quorum: 1/1, 2/2, or 2/3 successful replicas,
- one-shot upload runs in parallel, while large chunked upload runs sequentially
  per relay (with up to 5 chunks in parallel within one relay); a relay that
  times out during upload is excluded from the current operation, and the blob
  must be stored on every remaining available relay,
- visible replication progress is one monotonic scale and reaches 100% only
  after the final available relay stores the blob,
- upload receipt contains the immutable `blobId` and exact successful relay
  locations; it does not alter encryption, signature, or blob-id semantics,
- sender then delivers encrypted `direct_blob_ref` metadata through the normal
  personal relay message path, including optional `blobRelayServers`,
- receiver first resolves a blob from `blobRelayServers` without adding those
  endpoints to its configured relay pool; a legacy reference without locations
  uses the configured local pool,
- direct personal media receive now uses only encrypted `direct_blob_ref` plus relay blob download; legacy `fileMeta/fileChunk` receive has been removed.

## 6. Multi-Server Behavior

Configured relay servers are a local Settings-owned pool. Peer-advertised
relay topology is held separately in a TTL-bounded `PeerRelayDirectory`; it
may prioritize a healthy shared relay for a new direct store operation, but it
never mutates the persistent configured pool. Exact write locations are object
routing metadata, not discovery data.

Client keeps the configured relay list, but runtime no longer treats every server as equally active.

Current multi-server behavior:
1. run a fast health-aware selection step,
2. prefer only live relays for runtime operations,
3. keep the active working set small (up to 3 relays),
4. use the shared 1/1, 2/2, or 2/3 quorum for envelope writes, acks, and blob uploads,
5. run selected relay operations in parallel so one dead relay does not add full sequential delay.

Fetch-specific stabilization:
- client GET fetch uses transient retry/backoff for connection-drop/timeout transport errors before marking server unhealthy.

Operational note:
- on timeout/http errors for all servers, client degrades gracefully instead of hard-crashing,
- relay status is exposed to migrated UI through `NetworkApi`,
- `HttpRelayClient` writes explicit runtime logs when relay responds `401 invalid signature`.

## 7. Security Notes

- Envelopes are signed and verified on receive.
- Relay server verifies signatures for store/group-store/group-members-update/ack/blob upload/finalize.
- Relay server enforces server-side membership for group write endpoints.
- Replay checks are applied in reliable envelope handling.
- Runtime reliable-message encryption path is active (`enableEncryption: true`).

## 8. Open Items

- strict server-side schema/validation specification,
- retention and deletion guarantees,
- authenticated relay access control beyond signature + membership checks,
- stronger metadata privacy strategy.
