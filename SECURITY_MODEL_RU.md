# SECURITY_MODEL

Обновлено: 2026-08-28

Документ фиксирует, что PeerLink по безопасности уже может честно заявлять сейчас, а что еще остается зоной усиления.

## 1. Threat Model

Предполагается:
- метаданные трафика могут наблюдаться,
- TURN и relay инфраструктура недоверенные,
- bootstrap signaling путь недоверенный как транспорт,
- возможны replay и MITM атаки.

## 2. AS-IS Безопасность

### 2.1 Identity и ключи

- `IdentityService` управляет identity узла.
- Signing/key-agreement материал сохраняется через storage wrappers.
- `SignatureService` используется для sign/verify протокольных payload.
- Runtime identity использует стабильный `peerId` (v2), который вычисляется из signing key + installation id.
- Legacy peer id (hash только от signing key) сохраняется в метаданных для совместимости.
- Для невидимой миграции v2 -> v3 клиент публикует signed identity bundle v3: старый `peerId` остается routing/id значением, а `signingPublicKey` и `agreementPublicKey` передаются как проверяемый bundle, подписанный signing key.
- `AccountIdentity` добавляет слой аккаунта поверх device identity: `accountId`, `displayName`, список устройств и локальный QR/deep link pairing flow `peerlink://pair`.

### 2.2 Session Crypto

- `SessionManager` + `SessionCrypto` реализуют handshake и payload encryption API.
- Reliable messaging путь интегрирован с session API.
- В runtime-конфиге `NetworkDependencies` включено шифрование reliable messaging (`enableEncryption: true`).
- Direct reliable envelope может нести `senderIdentityBundleV3`; получатель проверяет подпись bundle и сохраняет ключи peer до decrypt, поэтому новая encrypted session может быть установлена без online-handshake, если bundle уже получен через invite/QR или входящее reliable-сообщение.
- Group-control рассылка (`groupKey`, `groupInvite`, `groupMembers`) отправляется через шифруемые control-message (E2E session path), а не plain-envelope.

### 2.3 Управление group-key

- Ключи групп хранятся в per-group записях:
  - `peerlink.group_key.v2.<groupId>`
  - `peerlink.group_key_version.v2.<groupId>`
- Legacy-хранилище (`peerlink.group_keys.v1`, `peerlink.group_key_versions.v1`) мигрируется при старте и затем удаляется.
- Добавлен GC group-key: ключи неактивных/удалённых групп очищаются.
- Ротация group-key запускается при изменении состава участников (add/remove) и на этапе bootstrap группы.

### 2.4 Целостность relay-envelope

- Relay envelope подписываются.
- Входящие relay-envelope проходят проверку подписи перед обработкой.
- Relay-сервер валидирует Ed25519-подпись на `/relay/store`.
- Relay-сервер валидирует Ed25519-подпись на `/relay/group/store`.
- Relay-сервер валидирует Ed25519-подпись на `/relay/group/members/update`.
- Relay-сервер валидирует Ed25519-подпись на `/relay/ack`.
- Relay-сервер валидирует Ed25519-подпись на blob upload/finalize endpoint-ах.
- Relay-сервер применяет server-side проверку членства на group write endpoint-ах.
- В reliable-envelope обработке применяются replay-window проверки.
- Direct fallback для группового медиа переносит только зашифрованную blob-ссылку и relay metadata; plaintext медиа не отправляется через push или direct payload.

### 2.5 Безопасность call/signaling

- Bootstrap register может содержать подписанный auth-proof.
- Signaling transport на своем уровне не является end-to-end encrypted.
- Media идет по WebRTC security, при этом routing-policy звонка сейчас форсируется на TURN.

### 2.6 Локальная защита от нежелательных контактов

- Contacts-only privacy setting включен по умолчанию и запрещает unsolicited direct messages, direct media, account pairing/group invite, push presentation/open и call invite от Peer ID, которых нет в локальных контактах.
- Локальный blacklist `blockedPeers` применяется раньше UI/persistence path: заблокированный Peer ID не создает видимые сообщения, входящие звонки или push-уведомления, а исходящий звонок к нему не стартует.
- Android FCM service и iOS CallKit bridge получают best-effort native-копию blacklist и проверяют ее до показа background/fullscreen/CallKit входящего звонка.
- Блокировка относится только к конкретному `peerId`; из-за децентрализованной identity-модели она не является пожизненной блокировкой физического человека.
- Push/relay/bootstrap серверы не получают приватные ключи, session keys или историю переписки для локальной блокировки.

## 3. Что можно утверждать сейчас

- Криптопримитивы и verification hooks присутствуют.
- Подпись relay-envelope проверяется на receive path.
- Session-based encryption включен в runtime-конфиге для reliable peer messaging.
- Group-control рассылка ключа/инвайтов/обновления участников идет через E2E session encryption.
- Group media payload шифруется до загрузки blob в relay.
- Group media direct fallback сохраняет тот же E2E group-media payload; меняется только маршрут доставки metadata после server-side membership отказа.
- Contacts-only и local block уже доступны как user-controlled protection от unsolicited direct content/calls/push; local block также запрещает исходящие звонки к заблокированному Peer ID.
- Push registration новых клиентов привязывает `peerId` к `signingPub` через проверяемый v2 identity binding (`peerId = SHA-256(signingPub + identityNonce)`) без дополнительного запроса; push/moderation endpoints в soft migration отклоняют mismatch для уже привязанных peerId и пропускают legacy unbound клиентов.
- Жалобы на UGC отправляются как metadata-only: текст/медиа сообщения, история чата, контакты, private keys и session keys не передаются модератору. При жалобе на сообщение клиент сразу скрывает его локально у репортера.
- HTTP-контракт модерации изолирован в `ModerationApiClient`; обычный push fanout/registration не должен расширяться moderation endpoint-ами, чтобы новый сервис не влиял на push delivery path.
- Moderator UI показывает агрегаты по пользователям, на которых жалуются, и по пользователям, которые жалуются, включая total/direct/group счетчики; модератор вручную принимает решение `warning` или `ban`, не видя содержимого сообщения.
- Warning/ban модель готова для App Store UGC flow: решение принимает только модератор, push отправляет пользователю `moderation_policy` с `messageKey`, `reportCount` и `reporterCount`, а клиент показывает fullscreen warning/ban на локали пользователя. Warning закрывается кнопкой `Продолжить`; ban сначала показывает экран appeal, после отправки appeal экран скрывается, но отправка сообщений и звонки локально запрещены до `unban`. Settings показывает текущий warning/ban красным под Peer ID/QR. Push также напрямую запрещает регистрацию, report и signed fanout от `banned` peer; relay/bootstrap не требуют доступа к moderation DB. `/moderation/status` возвращает `signedStatus`, если задан `MODERATION_STATUS_SIGNING_PRIVATE_KEY`; клиент проверяет подпись при заданном `MODERATION_STATUS_SIGNING_PUBLIC_KEY`.

## 4. Что нельзя утверждать

- Полное anti-replay покрытие для всех control/signaling flow.
- Полноценную ratcheting/session-key rotation стратегию для всех классов сообщений.
- Формальные гарантии приватности метаданных (сервер всё ещё видит routing-метаданные).
- Криптографически подтвержденное cross-device enrollment: pairing больше не применяется мгновенно и теперь требует явного approval от уже доверенного устройства аккаунта, но этот approval пока еще не оформлен как отдельный signed enrollment handshake и должен быть усилен перед production-синхронизацией ключей между устройствами.

## 5. Что делать дальше

1. Расширить replay protection на signaling/control envelope где это нужно.
2. Добавить интеграционные тесты на invalid signature/replay/tampered payload.
3. Расширить текущую group-key rotation до полноценной ratcheting/session-key стратегии.
4. Постепенно снижать доверие к централизованному bootstrap пути.
