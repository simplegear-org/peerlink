# BOOTSTRAP_SIGNALING_PROTOCOL (Русский)

Последнее обновление: 2026-04-12
Версия: `v=1`
Транспорт: WebSocket (`ws://` / `wss://`)
Формат фреймов: UTF-8 JSON

Документ описывает контракт фреймов, который использует текущий bootstrap signaling runtime.

## 1. Верхний уровень фрейма

```json
{
  "v": "1",
  "id": "string",
  "type": "string",
  "payload": {}
}
```

- `v`: версия протокола (`"1"`)
- `id`: уникальный идентификатор фрейма
- `type`: тип фрейма
- `payload`: объект, специфичный для типа

## 2. Регистрация

Клиент отправляет `register` после готовности сокета.
Соединение считается установленным только после `register_ack`.
`payload.peerId` — это стабильный идентификатор пользователя (`peerId v2`).

### 2.1 `register` (клиент -> сервер)

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

`auth` опционален для обратной совместимости со старыми серверами.

Комментарии на стороне сервера:
- сервер проверяет подпись по каноническому полезному грузу регистрации;
- текущий коллаут предпочитает канонический полезный груз v2 и может оставить fallback для совместимости;
- если `identityProfile.stableUserId` присутствует, он должен совпадать с `payload.peerId`.

### 2.2 `register_ack` (сервер -> клиент)

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

Таймаут клиента для `register_ack` короткий (логика переподключения во время выполнения обрабатывает повторы).

## 3. Фреймы сигнализации

### 3.1 `signal` (клиент -> сервер)

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

`payload.type`, используемый текущим клиентом:
- сигнализация транспорта: `offer`, `answer`, `ice`
- контроль вызова/медиа: `call_invite`, `call_accept`, `call_reject`, `call_end`, `call_busy`, `call_media_ready`, `call_video_state`, `call_video_state_ack`, `call_video_flow_ack`

### 3.2 Ретрансляция `signal` (сервер -> клиент)

Сервер пересылает тот же конверт сигнала на `payload.to`.

## 4. Heartbeat (Пульс)

Клиент периодически отправляет `ping`.
Сервер может ответить `pong` (или совместимым фреймом ack, если поддерживается реализацией сервера).

## 5. Обнаружение пиров (опционально)

Клиент может отправить `peers_request`.
Если поддерживается, сервер отвечает `peers`:

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

Поведение во время выполнения для неподдерживающих серверов:
- если сервер возвращает `error` с `UNKNOWN_TYPE` для `peers_request`, клиент отмечает обнаружение пиров как неподдерживаемое и продолжает сигнализацию нормально.

Заметки во время выполнения клиента (текущая реализация):
- после `register_ack` клиент немедленно отправляет `peers_request`, затем периодически;
- каждый фрейм `peers` рассматривается как снимок текущих онлайн-идентификаторов пиров на этом сервере начальной загрузки;
- клиент вычисляет переходы `онлайн/офлайн` из дифференциала снимков и выводит локальную временную метку `lastSeen` когда пир исчезает из снимка.

## 5.1 Фреймы присутствия (опциональное расширение)

Серверы могут предоставить явные фреймы присутствия вместо режима только снимков.

### `presence_snapshot` (сервер -> клиент)

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

### `presence_update` (сервер -> клиент)

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

## 6. Фрейм ошибки

```json
{
  "v": "1",
  "id": "srv-error-...",
  "type": "error",
  "payload": {
    "code": "ERROR_CODE",
    "message": "Понятное человеку сообщение"
  }
}
```

## 7. Минимальные требования к серверу

1. Принимать `register` и связывать `peerId -> websocket`.
2. Отправлять `register_ack`.
3. Пересылать фреймы `signal` целевому пиру.
4. Поддерживать heartbeat (`ping`/`pong`).
5. Возвращать `error` для недопустимых/неподдерживаемых фреймов.
