# ARCHITECTURE

Обновлено: 2026-07-21

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
- `PushApiClient` для подписанных запросов в `push.js` (`/devices/register`, `/devices/unregister`, `/events/push`), при этом высокоуровневая сборка событий вынесена в `PushEventFactory`, `PushRuntimeMetadataBuilder` и `PushEventService`.
- Call-push интеграция в `lib/core/node` частично декомпозирована:
  - `MeshCallPushHelper` — registration/unregister device token и call push fanout через `/events/push`,
  - `MeshNode` оставляет у себя orchestration signaling/transport/session lifecycle и только делегирует call-push операции.
- FCM runtime-модуль в `lib/core/firebase` декомпозирован:
  - `FirebaseMessagingService` — coordinator и внешний API,
  - `FirebasePushTokenLifecycle` — permission/token lifecycle и APNS/FCM sync,
  - `FirebasePushInboundService` — inbound orchestration,
  - `FirebasePushPayloadProcessor` — обработка push payload, merge server config и account/group update handling,
  - `FirebasePushPresentationHandler` — foreground/open/native-fallback handling и локальные уведомления,
  - `FirebasePushCallbackRegistry` / `firebase_push_models.dart` — callback registry и shared push models.
- Внутренний push/call payload model унифицирован через `FirebasePushPayload`: UI open path, FCM open/foreground/native-fallback и iOS CallKit path не должны держать параллельные call-payload DTO.
- `AppBadgeService` владеет состоянием badge иконки приложения и синхронизирует platform badge как сумму непрочитанных сообщений и пропущенных звонков.
- Для всех push-событий используется единый контракт `/events/push`: подписывается весь `payload` приложения, а сервер работает как transport-only fanout слой без собственной message/call-семантики.
- Если в `payload` присутствуют `servers` / `priority_servers`, они считаются runtime-метаданными приложения и обрабатываются только клиентом.
- `AccountIdentity` поверх device identity: `accountId`, `displayName`, список устройств и QR/deep link `peerlink://pair` для привязки второго устройства без изменения текущей device-based маршрутизации.
- Overlay router + dedup cache.
- HTTP relay-клиент с предварительным отбором живых relay, bounded active pool, quorum-write/quorum-ack и трекингом статусов.
- Reliable-envelope пайплайн декомпозирован на facade/service, inbound/session/poll controller-ы, pending store/retry scheduler и codec helpers.
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
      -> PushApiClient (HTTP)
      -> FirebaseMessagingService
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
- Chat-модули декомпозированы на отдельные компоненты (`chat_screen_view`, `chat_screen_helpers`, `chat_screen_unread_divider`, `chat_screen_media_actions`, `chat_screen_app_bar`, `chat_screen_message_list`, `chat_screen_audio_actions`, `chat_screen_actions`, `chat_screen_scroll_coordinator`, `chat_screen_lifecycle`, `chat_screen_viewport_state`, `chat_screen_presenter`, `chat_screen_back_swipe_coordinator`, `chat_screen_composer_coordinator`, `chat_controller_parts`, `chat_controller_media`).
- `ChatScreen` теперь удерживает только orchestration/state wiring; AppBar, message list overlays, voice-recording flow, dialog/action flow, lifecycle wiring, viewport state, presentation-логика, composer/send/reply flow и back-swipe gesture вынесены в отдельные screen-модули.
- Inbound-классификация входящих сообщений вынесена в `chat_inbound_classifier.dart` (`ChatInboundClassifier`) с явными decode-зависимостями через конструктор.
- Outbound codec/transfer-id логика вынесена в `chat_outbound_codec.dart` (`ChatOutboundCodec`) и используется из `ChatController` через `import`.
- Декомпозиция `ChatController` продолжена сервисами `chat_repository.dart`, `chat_summary_service.dart`, `chat_file_queue_service.dart`, `chat_outbound_service.dart`, `chat_inbound_service.dart`, `chat_read_state_service.dart`, `chat_contacts_service.dart`, `chat_group_service.dart`; контроллер должен оставаться orchestration/facade слоем.
- Group crypto вынесена из `ChatController` в `lib/core/security/group_message_crypto_service.dart`, рядом с `group_key_service.dart`; UI/state слой не должен содержать собственную реализацию pack/unpack и encrypt/decrypt для group payload.
- `memberPeerIds` в group meta и runtime-потоках должны храниться в каноническом виде (`trim + unique + sort`), чтобы одинаковый состав участников не создавал ложные persistence-изменения только из-за порядка элементов.
- Локальный group avatar path должен коммититься только после успешной рассылки `groupMembers(action=avatar)`; staging-файл при ошибке fan-out не должен оставлять локальное состояние группы в частично обновленном виде.
- Верхние страницы Contacts/Chats/Settings используют компактный layout с AppBar без описательных header-текстов; строки контактов, чатов и истории звонков разделяют одни compact spacing/internal-padding константы через `CompactCardTileStyles`.
- Строки контактов показывают аватар, один display label (имя контакта или короткий peer id) и last-seen; строки чатов показывают аватар, название, последнее сообщение и badge непрочитанных без last-seen.
- Строки контактов открывают action menu по долгому нажатию для переименования сохраненного display name без изменения peer ID.
- Действие `Пригласить` в Contacts создает QR/direct-open ссылку `peerlink://invite` и удобную для отправки landing-ссылку `https://simplegear.org/invite`; оба формата содержат локальный Peer ID и доступную конфигурацию серверов, а входящие invite-ссылки сначала merge-ят серверные настройки, затем добавляют/обновляют контакт. Self-invite merge-ит server config и пропускает создание контакта.
- Действие `Поделиться конфигурацией` в Settings создает HTTPS-ссылку `https://simplegear.org/config?payload=...` только с текущей доступной конфигурацией серверов. Web landing script маршрутизирует server-config payload в `peerlink://config?...`; app-side config deep link напрямую merge-ит `bootstrap/relay/turn/push`, а QR scan/import сохраняет явный диалог выбора режима импорта.
- Доставка deep links на macOS нативная: `MainFlutterWindow` конфигурирует `DeepLinkChannel` созданным `FlutterViewController`, `AppDelegate` рано регистрирует URL handler-ы, а custom scheme (`peerlink://invite|pair|config|call`) и поддерживаемые web-ссылки передаются во Flutter. Android runner поддерживает тот же набор custom/web ссылок через app links.
- Блок `Аккаунт и устройства` в Settings показывает текущий `accountId`, количество известных устройств, QR `peerlink://pair` для привязки своего второго устройства и scan-flow для импорта pairing payload.
- Строки истории звонков используют компактные внутренние поля, меньший блок status-icon и плотный separator между строками.
- Общая типографика централизована через `AppTheme.fontFamily` и применяется к text styles, AppBar, NavigationBar, inputs, dialogs и snackbars.
- Стартовое позиционирование прокрутки чата работает single-flight: `ChatScreen` планирует только один проход к низу/непрочитанному за раз, чтобы убрать дублирующиеся прыжки при открытии, а режим bottom несколько кадров догоняет список, пока восстановленные медиа еще могут менять высоту.
- Позиционирование к первому unread через probe ленивого списка ждет, пока смонтируется divider или message key, и не полагается только на ratio по индексу, который ломается на высоких failed media-placeholder.
- Переход по reply использует монотонный smooth-scan, чтобы смонтировать исходное сообщение перед финальным `ensureVisible`, вместо видимых чередующихся probe-прыжков.
- Пометка прочитанного в уже открытом чате учитывает низ списка: входящие обновления автоматически читаются только если пользователь уже был рядом с низом, иначе unread-состояние сохраняется.
- Выбор initial history window и unread-якоря при открытии чата пропускает входящие media-placeholder со статусом `Ошибка загрузки`, поэтому старые ошибки не уводят загруженное окно и viewport от новых сообщений.
- Пузырь видеофайла использует существующий `video_player`, чтобы показать paused preview-кадр с play-overlay, и возвращается к темному placeholder-у, если preview инициализировать нельзя.
- Settings использует агрегированные карточки bootstrap/relay/turn на главном экране и отдельные list-screen экраны для управления каждой группой серверов.
- `SettingsScreen` декомпозирован: `settings_screen.dart` держит только lifecycle/wiring, composition/layout вынесены в `settings_screen_content.dart`, `settings_screen_identity_section.dart`, `settings_screen_account_devices_section.dart`, `settings_screen_server_sections.dart`, `settings_screen_preferences_sections.dart`, общий re-export account-секций идет через `settings_screen_account_sections.dart`, общие section/account widgets живут в `settings_screen_shared_widgets.dart` и `settings_screen_account_widgets.dart`, а dialog/action flow разнесен по `settings_screen_avatar_actions.dart`, `settings_screen_pairing_actions.dart`, `settings_screen_system_actions.dart`.
- Для bootstrap Settings показывает не legacy-ярлык `Активен`, а раздельные runtime/health статусы: `подключен` для реально открытого signaling channel, `доступен` для успешного probe без текущего channel, `недоступен` для failed probe.
- В `lib/ui/state` декомпозирован `SettingsController`: presentation статусов серверов вынесен в `settings_server_status_presenter.dart`, invite encode/parse — в `settings_invite_codec.dart`, pairing flow — в `settings_pairing_flow_service.dart`.

### 4.2 Core Entry (`lib/core/node`)

- `NodeFacade`: стабильный API для UI.
- Здесь находятся унифицированные точки входа для messaging/blob: `sendPayload(...)`, `uploadBlob(...)`, `downloadBlob(...)`.
- `MeshNode`: композиция, lifecycle, маршрутизация signaling и peer session orchestration.
- `MeshCallPushHelper`: call-oriented push registration и fanout (`/devices/register`, `/devices/unregister`, `/events/push`).
- `MeshSignalRouter`: выделенный routing seam для границы signaling -> `CallService` / peer transport внутри `MeshNode`.

### 4.3 Runtime (`lib/core/runtime`)

- `NetworkDependencies`: сборка dependency graph.
- `AppBootstrapCoordinator`: post-bootstrap конфигурация (сервера, background-задачи).
- Сервисы хранения и репозитории (`StorageService` как facade, `storage_service_paths`, `storage_service_migrations`, `storage_service_media`, репозитории контактов/логов звонков).
- `StorageService` теперь выступает как orchestration/facade-слой над storage helper-модулями и не должен обратно разрастаться.
- Storage runtime декомпозирован на:
  - `storage_service_paths.dart` — root/media path resolve и path helper-ы,
  - `storage_service_migrations.dart` — secure-storage load, legacy migrations, summary repair и embedded-media prune,
  - `storage_service_media.dart` — file/media persistence, legacy media restore, cleanup и storage size helpers.
- Очистка runtime-хранилища теперь работает только по явному выбору пользователя:
  - в Settings можно очищать конкретные категории (`Media files`, `Messages database`, `Logs`, `Settings and service data`),
  - heuristic orphan-media cleanup намеренно удален, потому что он небезопасен при наличии legacy-путей восстановления медиа.
- Блок `Хранилище` в Settings теперь открывается по тапу на всю карточку со стрелкой вправо, в том же навигационном паттерне, что и карточки серверов.
- `IdentityService` формирует стабильный `peerId` (v2) и хранит legacy id как метаданные совместимости.
- Identity/security слой декомпозирован: `IdentityService` должен оставаться orchestration/facade-слоем, `identity_key_store.dart` владеет key-store abstraction/secure-storage bridge, `identity_storage_support.dart` — storage/keypair/install-id helper-логикой, `identity_membership_crypto.dart` — membership/update signing и verify payload-ами.
- `SelfHostedDeployService`: SSH-оркестрация деплоя личного серверного стека, этапный прогресс (`1/14 ... 14/14`), post-deploy проверки доступности и фиксированные self-hosted endpoint-ы `wss://<ip>:443` / `https://<ip>:444`.
- `AvatarService` теперь живет в `lib/core/runtime`: хранит локальный avatar cache, embedded backup/restore, blob download и best-effort avatar announce/remove/query flow.
- Сервисы проверки серверов теперь разделяют общий контракт `ServerAvailabilityProvider`, чтобы будущая runtime-оркестрация могла единообразно работать с probing для bootstrap/relay/turn.
- `ServerHealthCoordinator` владеет общими health-сервисами bootstrap/relay/turn и запускает их после app bootstrap, поэтому runtime и Settings используют одно и то же состояние доступности без дублирующихся probe loop.
- Эти health-сервисы также используют общий polling/backoff engine, поэтому cadence повторных проверок унифицирован для bootstrap/relay/turn, а повторные неудачи автоматически увеличивают интервал probing.
- При общем refresh availability due-probes выполняются параллельно, чтобы несколько мертвых bootstrap/relay/turn endpoint-ов не суммировали startup/foreground latency последовательными timeout-ами.
- Bootstrap health refresh работает single-flight и переводит WebSocket connect timeout в availability snapshot `unavailable`, а не пробрасывает timeout exception из периодических проверок.
- `HttpRelayClient` и `TurnAllocator` подключены к coordinator-backed lookup-ам доступности relay/turn, поэтому runtime-выбор серверов использует те же shared health snapshot, что и Settings.
- Coordinator также реагирует на возврат приложения в foreground и на смену сетевой связности, инициируя общий refresh health-состояния без необходимости открывать Settings.
- Критичные relay-path теперь могут запросить адресный coordinator-backed refresh только для текущего relay shortlist, если общий relay snapshot устарел, без перепроверки всего relay-набора.
- TURN call setup теперь тоже может запросить адресный coordinator-backed refresh только для текущего TURN shortlist, если общий TURN snapshot устарел, без перепроверки всего TURN-набора.
- Версия приложения берется из `pubspec.yaml` (`version: x.y.z+n`) и автоматически прокидывается Flutter в Android/iOS.

### 4.4 Messaging (`lib/core/messaging`, `lib/core/relay`)

- `ReliableMessagingService` теперь выступает как orchestration/facade-слой над reliable messaging подмодулями и не должен обратно разрастаться.
- Reliable messaging декомпозирован на:
  - `ReliableInboundProcessor` — decode reliable envelope, replay window, plain/secure inbound delivery и pending secure inbound queue,
  - `ReliableSessionController` — session establish/prekey fetch, handshake init/response, handshake retry и post-session flush,
  - `ReliableRelayPollController` — relay fetch cursor, poll/backoff loop, signature verify и ack path,
  - `ReliablePendingOperationStore` — persistence pending direct/group payload и group-members операций,
  - `ReliableRetryScheduler` — retry timer и durable retry/backoff policy,
  - `ReliableCodec` — envelope type и signature/header payload builders.
- Relay ack привязан к durable delivery: direct/group chat envelope подтверждается только после awaitable-пути через `NetworkEventBus`, когда `ChatController` сохранил локальное сообщение или media placeholder.
- `HttpRelayClient`: интеграция `/relay/store`, `/relay/group/store`, `/relay/group/members/update`, `/relay/fetch`, `/relay/ack`, blob endpoint-ов.
- `RelayMediaTransferService` и `RelayMediaRetryCoordinator` теперь живут в `lib/core/relay`: relay media upload/download, restore result-модели и persisted retry orchestration больше не находятся в `ui/state`.
- Relay стратегия:
  - активный пул ограничен,
  - runtime-операции сначала выбирают только живые relay и используют не более 3 серверов,
  - запись и ack выполняются в quorum,
  - fetch агрегируется по активному пулу и использует отдельный cursor на каждый relay,
  - если healthy relay доступны, dead relay исключаются из активного пути доставки.
- Push fanout:
  - все push-события приложения отправляются подписанным `/events/push`,
  - приложение само формирует `payload` (`type`, `relay`, `servers`, `priority_servers` и прочие поля), а `push.js` только валидирует подпись и делает fanout по устройствам адресатов,
  - `push.js` отправляет одновременно `notification` и `data`, чтобы повысить видимость уведомлений на iOS в фоне.
  - в состояниях `background/killed` текст системного push-alert не модифицируется клиентом: отображается ровно `notification.title/body`, который отправитель сформировал, а `push.js` транзитно переслал через провайдер push.
  - для iOS добавлен native-to-Flutter fallback: если при cold start `getInitialMessage()` не вернул payload после тапа по уведомлению, клиент получает последний push payload из `AppDelegate` через `peerlink/push_payload/methods` и применяет merge серверов.
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

- `CallService` должен оставаться тонким orchestration/facade-слоем над call helper-модулями и peer/runtime callback wiring, а не обратно собирать в себе все call-flow ветки.
- Декомпозиция `CallService` уже вынесена в helper-слои:
  - `CallCommandHelper` — публичные user/system команды (`start/accept/reject/end`),
  - `CallControlSignalHelper` / `CallControlSignalRouter` — ожидание signaling-ready и маршрутизация `call_*` control-сигналов,
  - `CallConnectOrchestrationHelper` — start/connect timeout/TURN fallback orchestration,
  - `CallNetworkPolicyHelper` — TURN availability, transport label и timeout policy,
  - `CallPeerBindingHelper` / `CallPeerLifecycleHelper` — bind callback-ов `AudioCallPeer`, attach/reset peer lifecycle,
  - `CallLifecycleResetHelper` — fail/end transition и возврат в idle,
  - `CallMediaReadinessHelper` / `CallMediaTimeoutHelper` — active transition и recovery loop при отсутствии двустороннего media flow,
  - `CallStateUpdateHelper` — технические state mutation для stats и remote video state,
  - `CallPendingRemoteEndRegistry` — suppress/TTL логика ранних `call_end`.
- `AudioCallPeer` теперь выступает как тонкий orchestration/facade-слой над call-контроллерами и не должен обратно разрастаться.
- `CallPeerSessionController` управляет peer bootstrap, incoming/outgoing session flow и cleanup/reset.
- `CallPeerSessionController.disposePeerConnection()` является единым terminal cleanup path для peer runtime timers/pollers; локальное дублирование отмены таймеров выше по стеку возвращать нельзя.
- `CallNegotiationController` управляет `rtcConfig`, renegotiation, ICE restart и recovery policy; repeated restart/reoffer path дополнительно ограничен cooldown-ами, чтобы unstable network/media stall не разгоняли плотный recovery loop.
- `CallVideoController` управляет video state machine, transceiver/video-handle sync и quality policy.
- `CallMediaFlowController` управляет audio/video flow detection, stats polling и fallback логикой media-flow; stats polling intentionally остается умеренным, а repeated waiting-trace throttled, чтобы call diagnostics не становились hot path.
- `CallPeerEventController` управляет binding WebRTC peer events к runtime state updates.
- `CallLocalMediaController` управляет local mute/speaker/camera/media-type toggles.
- `CallConnectionStateController` управляет connected-state policy и моментом перехода transport в connected.
- `CallService` suppress-ит полностью идентичные `CallState` и не считает byte-counter updates полноценными state-transition trace-событиями, чтобы активный звонок не создавал лишний UI/state churn.
- `CallMediaStreamController` и `VideoStreamView` считаются частью hot media path: synthetic remote stream нельзя публиковать в UI пустым, no-op merge того же remote track не должен триггерить `onRemoteStream`, а renderer не должен повторно rebinding-ить тот же `MediaStream`/track без фактической смены источника.
- `IosCallkitService` должен оставаться native bridge-слоем и не должен обратно забирать в себя orchestration merge серверов или payload normalization.
- Для снижения риска первого нативного WebRTC cold start после обновления приложения audio path использует одноразовый `audio-only` warm-up перед первым боевым `getUserMedia`, не затрагивая video transceiver/media-type flow.
- Текущая политика звонков: TURN-only для всех типов сети.

### 4.6 Signaling (`lib/core/signaling`)

- `BootstrapSignalingService` по WebSocket.
- `BootstrapSignalingRuntimeState` хранит общий mutable runtime state signaling-модуля.
- `BootstrapSignalingSessionController` владеет `setServer`/connect/register flow.
- `BootstrapSignalingConnectivityController` владеет watch-логикой сетевой связности и fast-reconnect policy.
- `BootstrapSignalingReconnectController` владеет retry/backoff/circuit-breaker policy и reconnect trace.
- `BootstrapSignalingProtocolController` владеет register/signal/ping/peers protocol flow, retry queue и обработкой входящих frame.
- `BootstrapSignalingModels` содержит shared signaling value objects (`BootstrapPendingSignal`, `BootstrapReadyTimeout`, `BootstrapRegisterProof`).
- `MultiBootstrapSignalingService` агрегирует несколько bootstrap-подключений в единый runtime signaling layer.
- Реализованы reconnect, register, signal-кадры, optional peer discovery.
- Исходящий signaling (`call_invite`, `offer`, `answer`, `ice`) отправляется во все bootstrap-каналы, где целевой peer виден по `peers` snapshot; при отсутствии match используется fallback во все connected bootstrap.
- Регистрация использует стабильный `peerId` (v2); auth-proof включает `identityProfile`.
- Для self-hosted endpoint-ов по IP runtime принимает self-signed TLS-сертификаты в bootstrap и relay клиентах (только для IP-host).
- В self-hosted схеме HAProxy терминирует только `signal` (`:443`) и `relay` (`:444`); TURN/TURNS обслуживается напрямую `coturn` на `3478/5349`.
- Внутри signaling целевая декомпозиция уже переведена с `part` на отдельные import-based controller/model модули с явными зависимостями.

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
- Для `lib/core/calls` новые изменения сначала вносятся в существующие `Call*Controller`, и только если ответственность действительно новая — допускается новый controller.
- Документация должна отражать фактический runtime, а не только план.
- Нельзя бесконтрольно наращивать крупные файлы: для файлов больше `~800` строк в UI/state и `~500` строк в runtime новые фичи должны идти через выделение отдельного модуля (service/controller/helper) с отдельным файлом и подключением через `import`.
- Перед созданием нового сервиса обязательно проверять уже существующие сервисы в этом bounded context; дублирование ответственности между сервисами запрещено.
- Если подходящий сервис уже существует, но в нем не хватает функционала, нужно расширять этот сервис, а не создавать рядом новый дублирующий сервис.
- Перед добавлением функциональности в крупный файл обязателен архитектурный план декомпозиции (границы ответственности + точки тестирования).
- Для модулей с признаками god-object приоритетом должна быть декомпозиция; добавление новой логики без выноса считается архитектурным долгом и должно блокироваться на code review.
- `part` не является целевой формой декомпозиции: допускается только как краткоживущий миграционный этап, после чего логика должна быть переведена в отдельные сервисы/компоненты с явными зависимостями.

## 6. Ближайшие архитектурные приоритеты

1. Включить и стабилизировать encrypted messaging end-to-end.
2. Определить и реализовать стратегию transport-сессий для сообщений (direct-only vs failover).
3. Перевести group transport с recipient fan-out на server-side sequence log (topic style).
4. Расширить DHT от каркаса до рабочего lookup/RPC.
5. Снизить зависимость от bootstrap signaling (движение к overlay/DHT signaling).
6. Добавить интеграционные тесты signaling/reconnect/call stability.
