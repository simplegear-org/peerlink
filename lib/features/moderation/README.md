# Moderation feature ownership

`features/moderation` is the canonical bounded-context home for moderation.
Legacy files in `core/runtime` are forwarding exports retained for import
compatibility.

Classification:

- `domain`: `moderation_report_models.dart` — report reason and reported
  message metadata.
- `application`: contracts `ModerationReportsApi`, `AccessPolicyApi` and
  `ModerationStatusApi`; report, policy and access-control workflows;
  `ModerationLifecycleService`, which retries the outbox on startup, resume
  and restored connectivity.
- `infrastructure`: signed moderation HTTP client, push-server delivery
  adapter and storage-backed durable report outbox.
