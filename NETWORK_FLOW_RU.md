# NETWORK_FLOW

Обновлено: 2026-04-22

Документ описывает то, как текущий runtime реально работает сейчас, а не только желаемую архитектуру на бумаге.

## 1. Startup Flow (AS-IS)

```text
main.dart
  -> StorageService.init()
  -> инициализация Firebase/уведомлений
  -> NetworkDependencies.create()
    -> Identity/Session/Signature
    -> TransportManager
    -> OverlayRouter
    -> BootstrapSignalingService
    -> TurnAllocator
    -> DhtTransport + KademliaProtocol
    -> HttpRelayClient + ReliableMessagingService + ChatService + CallService
    -> MeshNode.initialize()
    -> NodeFacade
  -> AppBootstrapCoordinator.postBootstrap(...)
  -> UiApp
```

`MeshNode.initialize()` подписывается на signaling stream и peer discovery stream.

## 2. Connection Flow (сообщения)

`NodeFacade.sendPayload(targetKind: ChatPayloadTargetKind.direct)`:
1. `MeshNode.connectTo(peerId)`
2. `MeshNode` ждет готовности signaling.
3. Создает/переиспользует `PeerSession`.
4. `PeerSession.connect()` сейчас пытается только **direct WebRTC**.

Активного failover direct->turn->relay для message `PeerSession` сейчас нет.

`NodeFacade.sendPayload(targetKind: ChatPayloadTargetKind.group)` использует тот же входной API, но runtime-путь переключается на relay group fanout с явным списком `recipients`.

## 3. Message Send Flow

```text
ChatController
  -> NodeFacade.sendMessage
    -> MeshNode.connectTo(peerId)
    -> ChatService.sendMessage
      -> ReliableMessagingService.send
        -> подпись/упаковка RelayEnvelope + store через HttpRelayClient
```

Важно:
- доставка сообщений в runtime сейчас relay-based,
- шифрование reliable-сообщений в runtime активно (`enableEncryption: true`),
- relay runtime теперь предпочитает живые relay и держит небольшой рабочий набор, поэтому dead relay не должны определять пользовательскую задержку отправки, если healthy серверы уже доступны.

Group runtime path:
- групповой текст и групповое медиа отправляются через group relay flow,
- медиа и текст используют blob-модель (`upload blob -> group metadata`),
- шифрование payload для group media использует компактный бинарный формат `PLG2` (декодирование legacy-формата сохранено),
- тяжелые операции шифрования/дешифрования больших медиа вынесены в background isolate для сохранения отзывчивости UI,
- для больших blob клиент использует chunked upload (`/relay/blob/upload/chunk` + `/complete`) с fallback на одиночный `/relay/blob/upload`.
- owner группы синхронизирует актуальный состав через `/relay/group/members/update`,
- relay выполняет проверку членства на group write-path,
- group key ротируется при add/remove участников.
- синхронизация личных аватаров: sender публикует blob в relay и отправляет control-событие `kind=profileAvatar` с `blobId`, получатель подтягивает blob и обновляет локальный cache.
- синхронизация аватара группы: owner загружает avatar blob в relay и отправляет service payload `groupMembers` с `action=avatar` и `avatarBlobId`; получатели скачивают blob и обновляют локальный avatar cache группы.
- обновление аватара группы идет вне обычного chat/media потока (service path), поэтому legacy-клиенты не должны отображать его как сообщение в чате.

Personal media path:
- медиа в личном чате сначала загружается в relay blob storage,
- затем sender отправляет зашифрованный `direct_blob_ref` по обычному reliable personal message каналу,
- получатель резолвит blob reference и восстанавливает файл из relay blob storage,
- прием личного медиа теперь работает только через зашифрованный `direct_blob_ref` и загрузку blob из relay; legacy-путь `fileMeta/fileChunk` удален,
- direct blob download использует retry/timeout-обертку,
- если восстановление входящего медиа оборвалось из-за transient network switch, клиент автоматически планирует несколько delayed retry.

## 4. Message Receive Flow

```text
ReliableMessagingService (poll каждые 2с)
  -> HttpRelayClient.fetch(/relay/fetch)
    -> transient retry/backoff на GET при обрывах/таймаутах соединения
    -> выбор живых relay + ограниченный рабочий набор
  -> проверка подписи + валидация envelope
  -> ChatService
  -> NetworkEventBus
  -> UI-контроллеры
```

Ack path:
- после успешной обработки отправляется `HttpRelayClient.ack(/relay/ack)`.
- ack-запрос подписывается и включает `from` + `signingPub`.
- формат payload подписи ack: `id|from|to|timestampMs`.
- ответ relay `401 invalid signature` явно пишется в runtime-лог `HttpRelayClient`.
- операции по выбранным relay выполняются параллельно, чтобы один недоступный сервер не добавлял полную последовательную задержку.
- при старте контактные аватары сначала восстанавливаются из локального embedded backup, если файл по сохраненному пути отсутствует; только затем runtime догружает недостающие аватары из сети.

## 5. Signaling Flow

Bootstrap signaling используется для:
- WebRTC transport signaling,
- call signaling (`call_invite`, `call_accept`, `offer`, `answer`, `ice` и call media control кадры).

`BootstrapSignalingService` реализует:
- reconnect/backoff,
- fast reconnect при смене сети,
- register/register_ack handshake,
- heartbeat (`ping`/`pong`).

## 6. Call Flow

Текущая политика `CallService`:
- режим звонка всегда TURN (независимо от Wi-Fi/4G),
- media setup через `AudioCallPeer` + выделенные controllers для negotiation/video,
- `media_ready` и video-state ack идут через signaling кадры.
- при нескольких TURN серверах ICE проверяет кандидаты доступных серверов и использует первый успешный маршрут.

## 7. DHT/Overlay Flow

- Overlay router и DHT transport есть и подключены.
- `KademliaProtocol` сейчас только пробрасывает входящий RPC в callback; полноценный iterative lookup не реализован.

## 8. Текущие пробелы

- Нужен bootstrap signaling (централизованный компонент).
- Нет активного failover stack для message transport sessions.
- Runtime encryption отключен.
- Групповой fan-out все еще завязан на `/relay/group/store` (пока без server-side topic/seq log).
- Нужны интеграционные тесты на reconnect/failover/call-regression.
