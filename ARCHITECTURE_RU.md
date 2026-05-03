# ARCHITECTURE

Обновлено: 2026-04-30

## 1. Назначение

PeerLink — Flutter-мессенджер с децентрализованным ядром. На практике проект использует гибридную архитектуру:
- децентрализованные peer/overlay-компоненты,
- централизованный bootstrap signaling для установки сессий,
- relay-доставка сообщений.

## 2. Снимок AS-IS

Сейчас работает:
- DI-сборка через `NetworkDependencies.create()`.
- Стартовая оркестрация через `AppBootstrapCoordinator`.
- `NodeFacade` как единая точка входа UI в core.
- `MeshNode` как оркестратор runtime.
- Overlay router + dedup cache.
- HTTP relay-клиент с предварительным отбором живых relay, bounded active pool, quorum-write/quorum-ack и трекингом статусов.
- Reliable-envelope пайплайн, relay poll loop, ack flow.
- Group relay path для групповых чатов.
- Доставка personal media через relay blob + зашифрованный direct blob-reference payload.
- Blob-транспорт для группового текста/медиа (upload blob + metadata delivery).
- Server-side проверка членства группы на relay write path.
- Синхронизация состава группы через `/relay/group/members/update`.
- Ротация group key при изменении состава участников.
- Chunked blob upload (`chunk` + `complete`) с fallback на single upload.
- Для encrypted group media используется компактный бинарный payload-формат `PLG2` (legacy decode path сохранен).
- Криптообработка больших group media вынесена из UI isolate в background isolate.
- В fetch GET path добавлен transient retry/backoff при обрывах соединения, включая преждевременное закрытие соединения до HTTP-заголовков.
- Relay runtime-пути теперь предпочитают только живые relay и ограничивают рабочий набор максимум 3 серверами для message/media операций.
- Relay control write, fetch и blob fetch выполняются параллельно по выбранным relay, чтобы не накапливать таймауты от недоступных серверов.
- Blob fetch расширяется за пределы текущего live shortlist после `404` от всех shortlist-кандидатов, прежде чем считать blob отсутствующим.
- Стек звонков с выделенными компонентами:
  - `CallNegotiationController`,
  - `CallVideoController`,
  - `CallVideoState`.
- TURN allocator и настройка TURN серверов из UI.

Ограничения:
- Bootstrap signaling остается централизованным по контракту, но runtime удерживает несколько bootstrap WebSocket-каналов одновременно через агрегатор.
- DHT-слой минимальный (`KademliaProtocol` как pass-through каркас).
- Runtime encryption для reliable-сообщений включен конфигом (`enableEncryption: true`).
- `PeerSession` сейчас поддерживает только direct transport mode.

## 3. Текущий граф зависимостей

```text
UI
  -> NodeFacade
    -> MeshNode
      -> Identity / Session / Signature
      -> TransportManager
        -> PeerSession
          -> WebRtcTransport (direct)
      -> OverlayRouter
      -> RelayClient (HTTP)
      -> ReliableMessagingService
      -> ChatService
      -> CallService
      -> BootstrapSignalingService
      -> TurnAllocator
      -> RoutingTable / RecordStore / DhtTransport / KademliaProtocol
      -> NetworkEventBus
```

## 4. Границы слоев

### 4.1 UI (`lib/ui`)

- Экраны, виджеты, state-контроллеры.
- Доступ к core только через `NodeFacade`.
- Runtime-локализация живет в `lib/ui/localization`: `AppLocaleController` сохраняет выбранный язык в settings storage, `AppStrings` дает lookup/formatting API и Flutter localization delegates для `MaterialApp`, а словари по языкам лежат в `lib/ui/localization/dictionaries`.
- Для экранов стандартизован шаблон композиции:
  - `*_screen.dart` для orchestration/state wiring,
  - `*_view.dart` для layout-виджетов,
  - `*_styles.dart` для констант дизайна.
- Chat-модули декомпозированы на отдельные компоненты (`chat_screen_view`, `chat_screen_helpers`, `chat_screen_unread_divider`, `chat_screen_media_actions`, `chat_controller_parts`, `chat_controller_media`).
- Верхние страницы Contacts/Chats/Settings используют компактный layout с AppBar без описательных header-текстов; строки контактов, чатов и истории звонков разделяют одни compact spacing/internal-padding константы через `CompactCardTileStyles`.
- Строки контактов показывают аватар, один display label (имя контакта или короткий peer id) и last-seen; строки чатов показывают аватар, название, последнее сообщение и badge непрочитанных без last-seen.
- Строки контактов открывают action menu по долгому нажатию для переименования сохраненного display name без изменения peer ID.
- Действие `Пригласить` в Contacts создает QR/direct-open ссылку `peerlink://invite` и удобную для отправки landing-ссылку `https://simplegear.org/invite`; оба формата содержат локальный Peer ID и доступную конфигурацию серверов, а входящие invite-ссылки добавляют/обновляют контакт и merge-ят серверные настройки. Публичная landing-страница также описывает PeerLink на поддерживаемых языках интерфейса и ведет на открытые app/server репозитории.
- Строки истории звонков используют компактные внутренние поля, меньший блок status-icon и плотный separator между строками.
- Общая типографика централизована через `AppTheme.fontFamily` и применяется к text styles, AppBar, NavigationBar, inputs, dialogs и snackbars.
- Стартовое позиционирование прокрутки чата работает single-flight: `ChatScreen` планирует только один проход к низу/непрочитанному за раз, чтобы убрать дублирующиеся прыжки при открытии, а режим bottom несколько кадров догоняет список, пока восстановленные медиа еще могут менять высоту.
- Позиционирование к первому unread через probe ленивого списка ждет, пока смонтируется divider или message key, и не полагается только на ratio по индексу, который ломается на высоких failed media-placeholder.
- Переход по reply использует монотонный smooth-scan, чтобы смонтировать исходное сообщение перед финальным `ensureVisible`, вместо видимых чередующихся probe-прыжков.
- Пометка прочитанного в уже открытом чате учитывает низ списка: входящие обновления автоматически читаются только если пользователь уже был рядом с низом, иначе unread-состояние сохраняется.
- Выбор initial history window и unread-якоря при открытии чата пропускает входящие media-placeholder со статусом `Ошибка загрузки`, поэтому старые ошибки не уводят загруженное окно и viewport от новых сообщений.
- Пузырь видеофайла использует существующий `video_player`, чтобы показать paused preview-кадр с play-overlay, и возвращается к темному placeholder-у, если preview инициализировать нельзя.
- Settings использует агрегированные карточки bootstrap/relay/turn на главном экране и отдельные list-screen экраны для управления каждой группой серверов.

### 4.2 Core Entry (`lib/core/node`)

- `NodeFacade`: стабильный API для UI.
- Здесь находятся унифицированные точки входа для messaging/blob: `sendPayload(...)`, `uploadBlob(...)`, `downloadBlob(...)`.
- `MeshNode`: композиция, lifecycle, маршрутизация signaling.

### 4.3 Runtime (`lib/core/runtime`)

- `NetworkDependencies`: сборка dependency graph.
- `AppBootstrapCoordinator`: post-bootstrap конфигурация (сервера, background-задачи).
- Сервисы хранения и репозитории (`StorageService`, репозитории контактов/логов звонков).
- Очистка runtime-хранилища теперь работает только по явному выбору пользователя:
  - в Settings можно очищать конкретные категории (`Media files`, `Messages database`, `Logs`, `Settings and service data`),
  - heuristic orphan-media cleanup намеренно удален, потому что он небезопасен при наличии legacy-путей восстановления медиа.
- Блок `Хранилище` в Settings теперь открывается по тапу на всю карточку со стрелкой вправо, в том же навигационном паттерне, что и карточки серверов.
- `IdentityService` формирует стабильный `peerId` (v2) и хранит legacy id как метаданные совместимости.
- `SelfHostedDeployService`: SSH-оркестрация деплоя личного серверного стека, этапный прогресс (`1/14 ... 14/14`), post-deploy проверки доступности и фиксированные self-hosted endpoint-ы `wss://<ip>:443` / `https://<ip>:444`.
- Сервисы проверки серверов теперь разделяют общий контракт `ServerAvailabilityProvider`, чтобы будущая runtime-оркестрация могла единообразно работать с probing для bootstrap/relay/turn.
- `ServerHealthCoordinator` владеет общими health-сервисами bootstrap/relay/turn и запускает их после app bootstrap, поэтому runtime и Settings используют одно и то же состояние доступности без дублирующихся probe loop.
- Bootstrap health refresh работает single-flight и переводит WebSocket connect timeout в availability snapshot `unavailable`, а не пробрасывает timeout exception из периодических проверок.
- `HttpRelayClient` и `TurnAllocator` подключены к coordinator-backed lookup-ам доступности relay/turn, поэтому runtime-выбор серверов использует те же shared health snapshot, что и Settings.
- Coordinator также реагирует на возврат приложения в foreground и на смену сетевой связности, инициируя общий refresh health-состояния без необходимости открывать Settings.
- Критичные relay-path теперь могут запросить адресный coordinator-backed refresh только для текущего relay shortlist, если общий relay snapshot устарел, без перепроверки всего relay-набора.
- TURN call setup теперь тоже может запросить адресный coordinator-backed refresh только для текущего TURN shortlist, если общий TURN snapshot устарел, без перепроверки всего TURN-набора.
- Версия приложения берется из `pubspec.yaml` (`version: x.y.z+n`) и автоматически прокидывается Flutter в Android/iOS.

### 4.4 Messaging (`lib/core/messaging`, `lib/core/relay`)

- `ReliableMessagingService`: envelope encode/decode, replay checks, relay polling.
- Relay ack привязан к durable delivery: direct/group chat envelope подтверждается только после awaitable-пути через `NetworkEventBus`, когда `ChatController` сохранил локальное сообщение или media placeholder.
- `HttpRelayClient`: интеграция `/relay/store`, `/relay/group/store`, `/relay/group/members/update`, `/relay/fetch`, `/relay/ack`, blob endpoint-ов.
- Relay стратегия:
  - активный пул ограничен,
  - runtime-операции сначала выбирают только живые relay и используют не более 3 серверов,
  - запись и ack выполняются в quorum,
  - fetch агрегируется по активному пулу и использует отдельный cursor на каждый relay,
  - если healthy relay доступны, dead relay исключаются из активного пути доставки.
- Стратегия personal media/blob:
  - файл один раз загружается в relay blob storage с детерминированным direct-scope,
  - в личный чат доставляется зашифрованный `direct_blob_ref` по обычному reliable-message path,
  - прием personal media работает только через `direct_blob_ref` и загрузку blob из relay,
  - direct blob restore использует retry/timeout-обертку на скачивании,
  - после transient network error входящий media restore автоматически планирует ограниченный delayed retry.
- Blob стратегия в группах:
  - при больших payload: chunked upload (`/relay/blob/upload/chunk`, `/relay/blob/upload/complete`),
  - fallback: `/relay/blob/upload`,
  - получение: `/relay/blob/:blobId`,
  - media/blob receive path не должен последовательно зависать на недоступных relay, если уже есть живые кандидаты.
- Удаление группового чата у всех доступно только owner'у: owner использует direct service-control fan-out (`groupChatDelete`) известным участникам и сохраняет локальный tombstone группы после очистки, чтобы устаревшие group-сообщения/invite не восстановили чат; не-owner отправляет `groupMembers` leave-событие, удаляется из состава owner-путем и затем удаляет локальную копию.

### 4.5 Calls (`lib/core/calls`)

- `CallService` управляет state machine звонка.
- `AudioCallPeer` управляет media peer connection и треками.
- Переговоры/видео вынесены в отдельные контроллеры.
- Текущая политика звонков: TURN-only для всех типов сети.

### 4.6 Signaling (`lib/core/signaling`)

- `BootstrapSignalingService` по WebSocket.
- `MultiBootstrapSignalingService` агрегирует несколько bootstrap-подключений в единый runtime signaling layer.
- Реализованы reconnect, register, signal-кадры, optional peer discovery.
- Исходящий signaling (`call_invite`, `offer`, `answer`, `ice`) отправляется во все bootstrap-каналы, где целевой peer виден по `peers` snapshot; при отсутствии match используется fallback во все connected bootstrap.
- Регистрация использует стабильный `peerId` (v2); auth-proof может включать `legacyPeerId` и `identityProfile`.
- Для self-hosted endpoint-ов по IP runtime принимает self-signed TLS-сертификаты в bootstrap и relay клиентах (только для IP-host).
- В self-hosted схеме HAProxy терминирует только `signal` (`:443`) и `relay` (`:444`); TURN/TURNS обслуживается напрямую `coturn` на `3478/5349`.

### 4.7 Transport + Overlay + DHT

- `TransportManager` отправляет данные через зарегистрированные `PeerSession`.
- `PeerSession` сейчас direct-only.
- Overlay и DHT присутствуют, но DHT пока минимален.
- `AvatarService` хранит embedded backup для contact avatars, чтобы восстановление после перезапуска не зависело от немедленной сетевой синхронизации.

## 5. Архитектурные правила

- UI не зависит от transport/security internals.
- `NodeFacade` — единственная граница UI/core.
- Композиция runtime остается в `NetworkDependencies`.
- Новую call/media-логику выносить из `AudioCallPeer` в контроллеры/состояние.
- Документация должна отражать фактический runtime, а не только план.

## 6. Ближайшие архитектурные приоритеты

1. Включить и стабилизировать encrypted messaging end-to-end.
2. Определить и реализовать стратегию transport-сессий для сообщений (direct-only vs failover).
3. Перевести group transport с recipient fan-out на server-side sequence log (topic style).
4. Расширить DHT от каркаса до рабочего lookup/RPC.
5. Снизить зависимость от bootstrap signaling (движение к overlay/DHT signaling).
6. Добавить интеграционные тесты signaling/reconnect/call stability.
