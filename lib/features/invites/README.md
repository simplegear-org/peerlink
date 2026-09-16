# Invite bounded context

Этот feature владеет short-invite workflow: созданием и разрешением подписанного
manifest, его domain validation и persistence pending token.

## Целевое ownership

```text
domain/
  InviteManifest
  version, expiry, token, peerId ↔ identity и username validation

application/
  InviteApi
  pending invite workflow/store port

infrastructure/
  HTTP implementation InviteApi
  Android Install Referrer implementation
```

## Текущее расположение и следующие шаги

| Текущий код | Целевой owner | Backlog |
| --- | --- | --- |
| `domain/invite_manifest.dart`: `InviteManifest` и validation | domain | INVITE-002 — DONE |
| `infrastructure/invite_manifest_client.dart`: HTTP create/resolve и error classification | infrastructure | INVITE-002 — DONE |
| `app/invites/invite_flow_coordinator.dart` | app cross-feature orchestration через narrow ports | INVITE-003, INVITE-004 — DONE |
| `application/pending_invite_store.dart` + storage implementation | Invite application persistence port | INVITE-005 — DONE |
| `infrastructure/android_install_referrer_service.dart` | Invite platform infrastructure | INVITE-006 — DONE |

`app/invites/invite_manifest_client.dart` сохранён как compatibility export.
`SettingsInviteCodec` остаётся legacy QR/settings flow и не является частью
short-invite bounded context. Механический перенос до соответствующих пунктов
backlog запрещён, чтобы не менять protocol и UI behavior.

После успешного принятия short invite coordinator best-effort синхронизирует
обратно приглашающему настроенные username и avatar принимающего peer. Ошибка
profile sync не отменяет accepted invite.
