# Reliability and Delivery Resilience

Last reviewed: 2026-09-19

PeerLink X is designed to keep relay-backed delivery usable when individual
relay endpoints or network connections are temporarily unavailable. These are
implementation properties, not an availability SLA.

## Relay-backed delivery

- The client evaluates relay health and keeps a small live working set instead
  of making a failed endpoint block every operation.
- Message envelopes and media blobs can use a durable `1/1`, `2/2` or `2/3`
  replica quorum, depending on the available relay set.
- Selected relay operations run in parallel. Timeout/failure of one candidate
  causes fallback to another candidate and a temporary local cooldown.
- Successful writes retain their exact replica locations. Receivers use these
  locations first, without adding foreign endpoints to the user's persistent
  relay configuration.

## Durable receive and recovery

- A message is acknowledged only after durable local handling. This prevents a
  relay envelope from being removed before message data or a media placeholder
  is stored locally.
- Acknowledgements target every known replica. Failed cleanup is retried later;
  replica TTL remains the fallback cleanup mechanism.
- Push is a delivery accelerator, not the only recovery mechanism. The client
  polls relay on startup, resume and restored connectivity.
- Media restore records a durable placeholder. A transfer interrupted by a
  network change, backgrounding or temporary relay outage can continue when
  the app becomes active, the chat opens or connectivity returns.
- Blob fetch first tries the exact relay locations carried by the reference and
  can expand to configured relays when the short live set has no copy.

## Runtime behavior during outages

- Server health checks update asynchronously and do not block initial UI
  creation.
- Empty relay configuration is handled as disabled polling rather than an app
  error.
- Connection drops and timeouts on relay fetch are treated as transient
  failures; the client applies retry/backoff and can continue with another
  healthy relay.

## Limits

- Centralized bootstrap signaling remains a dependency.
- Direct message-session transport does not currently implement a full
  direct-to-TURN-to-relay failover stack.
- Reliable delivery depends on reachable configured relay infrastructure and
  does not provide an unconditional delivery guarantee.
