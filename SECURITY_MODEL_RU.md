# SECURITY_MODEL

Обновлено: 2026-08-11

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

## 3. Что можно утверждать сейчас

- Криптопримитивы и verification hooks присутствуют.
- Подпись relay-envelope проверяется на receive path.
- Session-based encryption включен в runtime-конфиге для reliable peer messaging.
- Group-control рассылка ключа/инвайтов/обновления участников идет через E2E session encryption.
- Group media payload шифруется до загрузки blob в relay.
- Group media direct fallback сохраняет тот же E2E group-media payload; меняется только маршрут доставки metadata после server-side membership отказа.

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
