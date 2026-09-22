# NETWORK_FLOW

Обновлено: 2026-09-19

Документ описывает то, как текущий runtime реально работает сейчас, а не только желаемую архитектуру на бумаге.

## 1. Startup Flow (AS-IS)

```text
main.dart
  -> AppCompositionRoot.createBaseDependencies()
    -> StorageService.init()
    -> AppAppearanceController / AppLocaleController
  -> инициализация Firebase/уведомлений
  -> AppCompositionRoot.createRuntimeDependencies()
    -> NetworkDependencies.create(storage)
    -> Identity/Session/Signature
    -> TransportManager
    -> OverlayRouter
    -> BootstrapSignalingService
    -> TurnAllocator
    -> DhtTransport + KademliaProtocol
    -> HttpRelayClient + ReliableMessagingService + ChatService + CallService
    -> MeshNode.initialize()
    -> NodeFacade
    -> узкие node capability APIs / ChatRuntimeApi для мигрированных consumers
    -> AppUiDependencies
      -> app push/deep-link/call/lifecycle/badge coordinators
  -> UiApp
  -> применение сохранённой server configuration
    -> ServerHealthCoordinator.initialize()
    -> одна стартовая sync device/policy для push
    -> запуск availability refresh в фоне
  -> AppBootstrapCoordinator.postBootstrap(...) в фоне
```

UI не ждёт availability-probe bootstrap/relay/TURN/push. Конфигурация серверов
применяется до создания UI, а health snapshot обновляются асинхронно.

`MeshNode.initialize()` подписывается на signaling stream и peer discovery stream.

## 2. Connection Flow (сообщения)

`NodeFacade.sendPayload(targetKind: ChatPayloadTargetKind.direct)` остается
compatibility entrypoint. Новый и мигрированный код по возможности должен
зависеть от узких contracts вроде `MessagingApi`/`NetworkApi`.

Direct send path:
1. `MeshNode.connectTo(peerId)`
2. `MeshNode` ждет готовности signaling.
3. Создает/переиспользует `PeerSession`.
4. `PeerSession.connect()` сейчас пытается только **direct WebRTC**.

Активного failover direct->turn->relay для message `PeerSession` сейчас нет.

`NodeFacade.sendPayload(targetKind: ChatPayloadTargetKind.group)` использует тот же входной API, но runtime-путь переключается на relay group fanout с явным списком `recipients`.

## 3. Message Send Flow

```text
ChatController
  -> ChatRuntimeApi.sendPayload
    -> ChatRuntimeNodeAdapter / NodeFacade
    -> MeshNode.connectTo(peerId)
    -> ChatService.sendMessage
      -> ReliableMessagingService.send
        -> подпись/упаковка RelayEnvelope + store через HttpRelayClient
```

Важно:
- доставка сообщений в runtime сейчас relay-based,
- шифрование reliable-сообщений в runtime активно (`enableEncryption: true`),
- UI-статус отправки отделен от relay ack: `sendReceipt.sent=true` дает 1 галку, входящий `message_receipt delivered` дает 2 галки, входящий `message_receipt read` дает 3 галки,
- relay runtime теперь предпочитает живые relay и держит небольшой рабочий набор, поэтому dead relay не должны определять пользовательскую задержку отправки, если healthy серверы уже доступны.

Relay discovery и object routing намеренно имеют разные semantics:

- configured relay servers — это локальный Settings-owned pool;
- advertised relay topology peer хранится отдельно в `PeerRelayDirectory` с
  TTL 30 дней и может дать приоритет healthy intersection sender/receiver при
  новой direct store-операции;
- successful write возвращает точные relay locations; `blobRelayServers`
  передаётся в direct/group media reference и первым используется для targeted
  blob fetch;
- metadata входящего `ChatService` обновляет только peer directory и никогда
  не merge-ит чужие relay endpoints в persistent configured pool.

Message receipt path:
- после durable-сохранения входящего direct/group сообщения или media-placeholder получатель best-effort отправляет автору direct reliable payload `__peerlink_message_receipt_v1__` со статусом `delivered`;
- после `ChatReadStateService.markChatAsRead(...)` получатель отправляет `read` receipt за реально помеченные входящие сообщения;
- для групп receipt отправляется автору сообщения, а UI отправителя агрегирует состояние по правилу `хотя бы один участник`: непустой `deliveredAtByPeer` = 2 галки, непустой `readAtByPeer` = 3 галки;
- receipt payload классифицируется как service-событие и не отображается в истории чата.

Group runtime path:
- групповой текст и групповое медиа отправляются через group relay flow,
- медиа и текст используют blob-модель (`upload blob -> group metadata`),
- шифрование payload для group media использует компактный бинарный формат `PLG2` (декодирование legacy-формата сохранено),
- тяжелые операции шифрования/дешифрования больших медиа вынесены в background isolate для сохранения отзывчивости UI,
- для больших blob клиент использует chunked upload (`/relay/blob/upload/chunk` + `/complete`) с fallback на одиночный `/relay/blob/upload`.
- owner группы синхронизирует актуальный состав через `/relay/group/members/update`,
- relay выполняет проверку членства на group write-path,
- получатель применяет `groupMembers(action=add/remove)`, только если transport
  sender совпадает с уже известным локальным owner; owner/admin из payload не
  являются источником authority, а `leave` остаётся member-originated потоком,
- group key ротируется при add/remove участников.
- если group media blob уже загружен, но group write получает отказ членства из-за устаревшего состава на relay, клиент выполняет direct reliable fallback с зашифрованной blob-ссылкой для каждого участника и очищает pending group payload после успеха,
- `group-members-update owner mismatch` не ретраится бесконечно: это terminal state для pending membership update.
- синхронизация личных аватаров: sender публикует blob в relay и отправляет control-событие `kind=profileAvatar` с `blobId`, получатель подтягивает blob и обновляет локальный cache.
- синхронизация аватара группы: owner загружает avatar blob в relay и отправляет service payload `groupMembers` с `action=avatar` и `avatarBlobId`; получатели скачивают blob и обновляют локальный avatar cache группы.
- обновление аватара группы идет вне обычного chat/media потока (service path), поэтому legacy-клиенты не должны отображать его как сообщение в чате.
- удаление группового чата по инициативе owner'а распространяется service-control payload-ом `groupChatDelete` всем известным участникам до локальной очистки; получатели принимают его только от известного owner, удаляют локальный чат и сохраняют tombstone группы, чтобы старые relay/invite-события не восстановили его. Не-owner отправляет `groupMembers` с `action=leave`, owner удаляет его из relay membership и ротирует group key, затем вышедший участник удаляет локальную копию.
- пустая relay-конфигурация считается выключенным/пустым состоянием polling-а; startup и background polling не должны бросать исключение, если relay-серверы не настроены.
- путь push-события:
  - после успешной runtime-операции приложение при необходимости отправляет подписанный `/events/push` в `push.js`,
  - событие содержит `recipientUserIds`, произвольный `payload` приложения, опциональный `notification` и опциональный `delivery`,
  - сервер проверяет подпись и делает fanout по токенам устройств получателей, не преобразуя `payload`,
  - access-policy schema v2 содержит отдельные direct/group списки mute для
    messages/calls; сервер подавляет только соответствующий notification fanout,
    а reliable relay envelope по-прежнему сохраняется и fetch-ится обычно,
  - FCM payload включает и `notification`, и `data/payload` для лучшей видимости уведомлений на iOS в фоне,
  - клиент использует такой push как ускоритель, но все равно выполняет `pollRelay()` на startup, resume и connectivity restore.

- маршрут входящего group relay payload:
  - `ReliableRelayPollController` передает `groupId` в inbound pipeline,
  - `ReliableInboundProcessor` сохраняет `groupId` в `ReliableMessageEnvelope`,
  - `ChatService` при наличии `groupId` публикует messageReceived event в chat target группы, а не в peer отправителя.

Personal media path:
- медиа в личном чате сначала загружается в relay blob storage,
- перед upload выбирается до 3 живых relay; blob реплицируется на все выбранные
  доступные relay. One-shot upload идёт параллельно, large chunked upload —
  последовательно по relay (до 5 chunks одновременно внутри одного relay),
- для chunk upload выполняется одна попытка с таймаутом пять секунд, после чего
  клиент сразу переключается на следующий relay; упавший relay локально
  исключается на две минуты, даже если общий health ещё устарел. Blob
  сохраняется на всех оставшихся доступных relay. Прогресс репликации не
  перезапускается для каждого relay и достигает 100% только в конце,
- затем sender отправляет зашифрованный `direct_blob_ref`, включая точные
  `blobRelayServers` при их наличии, по обычному reliable personal message
  каналу,
- получатель резолвит blob reference и восстанавливает файл из relay blob storage,
- прием личного медиа теперь работает только через зашифрованный `direct_blob_ref` и загрузку blob из relay; legacy-путь `fileMeta/fileChunk` удален,
- direct blob download сначала использует `blobRelayServers` без изменения
  локальной relay-конфигурации, затем сохраняет legacy fallback по configured
  pool для старых reference; также используется retry/timeout-обертка,
- если текущий shortlist живых relay возвращает только `404` для blob, blob fetch расширяется на остальные сконфигурированные relay перед тем, как считать blob отсутствующим,
- если восстановление входящего медиа оборвалось из-за transient network switch или временной недоступности relay, клиент автоматически продолжает retry позже при активном приложении,
- если приложение background/killed во время incoming relay media restore, persisted placeholder может возобновиться при следующем открытии чата, resume приложения или восстановлении connectivity,
- Android foreground service для media restore не используется, поэтому `FOREGROUND_SERVICE_DATA_SYNC` не требуется,
- если пользователь нажимает на входящий файл, пока его relay restore уже активен, существующий restore остается единственной активной загрузкой для этого сообщения,
- видимый progress incoming relay-media монотонный, потому что несколько relay-candidate могут сообщать progress для одного blob fetch,
- входящее relay-media не принимает запоздалые исходящие (`transfer.outgoing.*`)
  progress-статусы, поэтому после загрузки не может отобразиться «Отправка 100%»,
- после достижения 100% видимый статус последовательно отражает загрузку, расшифровку и сохранение; после успешного persistence сообщения статус очищается,
- retry разрешён только для ошибок download/доступности relay; decrypt, save и message-update failures terminal и отображаются отдельными статусами,
- `localFilePath` сохраняется до генерации thumbnail; thumbnail best-effort и не может повторно запустить relay download или отменить восстановленное медиа,
- retry upload/download, incoming retry state, timers и result handling для relay media централизованы в `RelayMediaTransferService` / `RelayMediaRetryCoordinator`.

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
- `HttpRelayClient.ack(/relay/ack)` отправляется только после успешной durable-обработки.
- Для chat-сообщений relay ack откладывается до момента, когда `ChatController` обработал событие и сохранил локальное сообщение/placeholder; это защищает метаданные медиа от потери, если приложение закрыли во время входящей relay-загрузки.
- Multi-relay fetch сохраняет exact locations envelope. ACK параллельно
  отправляется во все известные replicas, в том числе вне локального
  configured relay pool. Partial ACK не отменяет delivery и committed cursor;
  failed cleanup повторяется на следующем poll/reconnect, а TTL replica служит
  fallback.
- ACK удаляет только message envelope. Связанный media blob остаётся до
  истечения независимого blob TTL.
- ack-запрос подписывается и включает `from` + `signingPub`.
- формат payload подписи ack: `id|from|to|timestampMs`.
- ответ relay `401 invalid signature` явно пишется в runtime-лог `HttpRelayClient`.
- relay fetch считает преждевременное закрытие HTTP-соединения до заголовков transient relay failure: такой relay помечается unhealthy, а poll возвращает пустую пачку/переключается на другие relay вместо всплывающего исключения в UI.
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
