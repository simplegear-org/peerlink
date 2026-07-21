# Group Blob Messaging v1 (Spec)

Last updated: 2026-04-12
Status: partial implementation. Current runtime already uses `/relay/group/store` plus the blob upload path, while server-side membership checks and group-key rotation are active.

## 1. Goal

- Use one delivery model for **group text** and **group media**.
- Minimize sender device load: `upload once + send one group event`.
- Keep E2E privacy with group key encryption.
- Prepare for push wake-up and blob GC.

---

## 2. Scope v1

In scope:

- Group messaging transport (`blob + group event`).
- Client fetch-by-seq pipeline.
- Push wake-up contract (via bootstrap server).
- Blob TTL and garbage collection policy.

Out of scope:

- Full topic-sharding/multi-region architecture.
- Long-term key history beyond active + previous key.

---

## 3. Data Model

### 3.1 Group Event

- `eventId: string`
- `groupId: string`
- `seq: int64` (assigned by server)
- `senderPeerId: string`
- `kind: "text" | "media" | "group_key_update"`
- `blobId: string?`
- `ts: int64` (client timestamp)
- `ttl: int`
- `sig: base64`
- `signingPub: base64`

### 3.2 Blob

- `blobId: string`
- `groupId: string`
- `fileName: string`
- `mimeType: string?`
- `sizeBytes: int`
- `payload: base64` (encrypted payload)
- `ts: int64`
- `ttl: int`
- `sig: base64`
- `signingPub: base64`

---

## 4. API Contract v1 (Target)

## 4.1 `POST /relay/blob/upload`

Purpose:

- Upload encrypted payload once.

Request JSON:

```json
{
  "id": "blob:1770000000000",
  "from": "peerA",
  "groupId": "group:123",
  "fileName": "photo.jpg",
  "mimeType": "image/jpeg",
  "ts": 1770000000000,
  "ttl": 2592000,
  "payload": "base64...",
  "sig": "base64...",
  "signingPub": "base64..."
}
```

Response JSON:

```json
{
  "ok": true,
  "blobId": "blob:1770000000000"
}
```

## 4.2 `GET /relay/blob/:blobId`

Purpose:

- Download blob payload by ID.

Response JSON:

```json
{
  "id": "blob:1770000000000",
  "groupId": "group:123",
  "fileName": "photo.jpg",
  "mimeType": "image/jpeg",
  "sizeBytes": 245667,
  "payload": "base64..."
}
```

## 4.3 `POST /relay/group/event`

Purpose:

- Append one event to group log.

Request JSON:

```json
{
  "eventId": "1770000001111",
  "groupId": "group:123",
  "senderPeerId": "peerA",
  "kind": "media",
  "blobId": "blob:1770000000000",
  "ts": 1770000001111,
  "ttl": 2592000,
  "sig": "base64...",
  "signingPub": "base64..."
}
```

Response JSON:

```json
{
  "ok": true,
  "seq": 1042
}
```

## 4.4 `GET /relay/group/events?groupId=...&afterSeq=...&limit=...`

Purpose:

- Pull group events after last local sequence.

Response JSON:

```json
{
  "groupId": "group:123",
  "events": [
    {
      "eventId": "1770000001111",
      "seq": 1042,
      "senderPeerId": "peerA",
      "kind": "media",
      "blobId": "blob:1770000000000",
      "ts": 1770000001111
    }
  ],
  "lastSeq": 1042
}
```

## 4.5 `POST /relay/group/ack` (optional v1)

Purpose:

- Client confirms local processing up to `seq`.

---

## 5. Client Pipeline v1 (Target)

### 5.1 Send text (group)

1. Encrypt text bytes by current group key (`AES-GCM-256`).
2. `POST /relay/blob/upload`.
3. `POST /relay/group/event` with `kind=text`, `blobId`.
4. Mark local message as sent after `group/event` success.

### 5.2 Send media (group)

1. Encrypt media bytes by current group key.
2. `POST /relay/blob/upload`.
3. `POST /relay/group/event` with `kind=media`, `blobId`, metadata.
4. Mark local message as sent after `group/event` success.

### 5.3 Receive

1. Poll/fetch `group/events` from `afterSeq`.
2. For each event with `blobId`, fetch blob once.
3. Decrypt payload via group key.
4. Save to local storage and update UI.

### 5.4 Retry/idempotency

- `blobId` and `eventId` are client-generated and idempotent.
- Exponential backoff: `1,2,4,8,16,30s`.
- On reconnect: resume by `afterSeq`.

---

## 6. E2E Group Key v1

- Cipher: `AES-GCM-256`.
- One active key per group + one previous key.
- Rotate key when membership changes.
- Key update travels as `group_key_update` event.
- Key payload is encrypted per-recipient by recipient public key.

---

## 7. Push Contract v1 (Bootstrap Server)

Purpose:

- Wake client up; message content still fetched from relay.

FCM `data` payload:

```json
{
  "type": "group_update",
  "groupId": "group:123",
  "lastSeq": "1042",
  "unreadDelta": "3",
  "ts": "1770000002222"
}
```

Rules:

- Send push only for offline/idle users.
- Debounce by `(peerId, groupId)` for 2-5 seconds.
- Client must fetch via `group/events`; push is a hint, not source of truth.

---

## 8. Blob GC Policy v1

- Default blob TTL: `30 days`.
- GC interval: `10-30 min`.
- Keep safety window (do not delete very fresh blobs even if clocks drift).
- If blob expired but event exists, mark event as expired in client UI.

---

## 9. Implementation Checklist

### 9.1 Client (`/Users/Vladimir/peerlink`)

- [ ] Add `group/event` APIs in relay client layer.
- [ ] Replace `group/store` text send path with `blob + event`.
- [ ] Replace `group/store` media send path with `blob + event`.
- [ ] Add `seq` cursor storage per group.
- [ ] Add pull loop for `group/events` and replay logic.
- [ ] Add idempotent local mapping (`eventId -> local message`).
- [done] Group key rotation on membership changes (current runtime path, non-event API).
- [ ] Show expired blob placeholder in chat UI.

### 9.2 Server (`/Users/Vladimir/peerlink_servers`)

- [ ] Add `POST /relay/group/event`.
- [ ] Add `GET /relay/group/events`.
- [ ] Store append-only per-group log with monotonic `seq`.
- [done] Enforce membership check on current group write path (`/relay/group/store`, blob upload endpoints) and membership sync endpoint (`/relay/group/members/update`).
- [ ] Add debounce push sender in bootstrap service.
- [ ] Add blob/event signature verification for new endpoints.
- [ ] Add blob GC worker by `expireAt`.

### 9.3 Docs

- [done] Update `RELAY_PROTOCOL.md` (client repo).
- [done] Update `README.relay.md` and `README_RU.md` (server repo).
- [ ] Add migration notes (v1 dual-stack period).

---

## 10. Migration Plan (Safe Rollout)

1. Add endpoints and keep old flow untouched.
2. Ship client dual-read (old + v1), single-write for test groups only.
3. Enable by feature flag for selected groups.
4. Observe metrics and failure rates.
5. Gradually switch all groups to v1.
6. Remove old group fan-out path after stabilization.
