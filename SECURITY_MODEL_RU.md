# SECURITY_MODEL

Обновлено: 2026-04-12

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

### 2.2 Session Crypto

- `SessionManager` + `SessionCrypto` реализуют handshake и payload encryption API.
- Reliable messaging путь интегрирован с session API.
- В runtime-конфиге `NetworkDependencies` включено шифрование reliable messaging (`enableEncryption: true`).
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

## 4. Что нельзя утверждать

- Полное anti-replay покрытие для всех control/signaling flow.
- Полноценную ratcheting/session-key rotation стратегию для всех классов сообщений.
- Формальные гарантии приватности метаданных (сервер всё ещё видит routing-метаданные).

## 5. Что делать дальше

1. Расширить replay protection на signaling/control envelope где это нужно.
2. Добавить интеграционные тесты на invalid signature/replay/tampered payload.
3. Расширить текущую group-key rotation до полноценной ratcheting/session-key стратегии.
4. Постепенно снижать доверие к централизованному bootstrap пути.
