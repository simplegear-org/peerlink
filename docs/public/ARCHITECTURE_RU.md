# ARCHITECTURE

Обновлено: 2026-09-19

## 1. Назначение

PeerLink — Flutter-мессенджер с децентрализованным ядром. На практике проект использует гибридную архитектуру:
- децентрализованные peer/overlay-компоненты,
- централизованный bootstrap signaling для установки сессий,
- relay-доставка сообщений.

## 2. Снимок AS-IS

Сейчас работает:
- Явная top-level application composition живет в
  `lib/app/composition`: `AppCompositionRoot` создает общий storage,
  runtime dependencies и presentation-shell dependencies; `AppDependencies`
  открывает bootstrap/UI только top-level lifetime-owned зависимости.
- App-level orchestration живет в `lib/app`: `AppUiDependencies` собирает
  UI-facing controllers/services, а `AppPushCoordinator`,
  `AppDeepLinkCoordinator`, `AppCallCoordinator`, `AppLifecycleCoordinator` и
  `AppBadgeCoordinator` владеют push-open, deep-link, call, lifecycle и badge
  orchestration через injected UI callbacks.
- DI-сборка runtime через `NetworkDependencies.create(storage: ...)`; app/bootstrap
  root владеет общим `StorageService` instance и явно передает его в runtime graph.
  `NetworkDependencies.create` создаёт owned graph на каждый вызов и больше не
  держит singleton runtime state.
- Стартовая оркестрация через `AppBootstrapCoordinator`.
- Сохранённая server configuration применяется до готовности UI, но availability
  probing bootstrap/relay/TURN/push запускается в фоне и не задерживает первый
  доступный UI.
- `NodeFacade` как internal aggregate/core entrypoint на период migration, с
  узкими capability contracts в `lib/core/node/node_capability_apis.dart`
  (`MessagingApi`, `CallsApi`, `IdentityApi`, `NetworkApi`, `ModerationApi`,
  `PresenceApi`, `RuntimeEventsApi`) для consumers, которым не нужен весь
  runtime surface.
- `MeshNode` как оркестратор runtime.
- `PushApiClient` для подписанных запросов в `push.js` (`/devices/register`, `/devices/unregister`, `/devices/access-policy`, `/events/push`), при этом высокоуровневая сборка событий вынесена в `PushEventFactory`, `PushRuntimeMetadataBuilder` и `PushEventService`; moderation HTTP живет отдельно в `ModerationApiClient`.
- Call-push интеграция в `lib/core/node` частично декомпозирована:
  - `MeshCallPushHelper` — registration/unregister device token и call push fanout через `/events/push`,
  - `MeshNode` оставляет у себя orchestration signaling/transport/session lifecycle и только делегирует call-push операции.
- FCM runtime-модуль в `lib/core/firebase` декомпозирован:
  - `FirebaseMessagingService` — coordinator и внешний API,
  - `FirebasePushTokenLifecycle` — permission/token lifecycle и APNS/FCM sync,
  - `FirebasePushInboundService` — inbound orchestration,
  - `FirebasePushPayloadProcessor` — обработка push payload, merge server config и account/group update handling,
  - `FirebasePushPayloadParsers`, `FirebasePushServerStorageMerger`, `FirebasePushServerUpdateParser`, `FirebasePushLogFormatter` — нормализация payload, merge/update parsing серверов и форматирование diagnostics,
  - `FirebasePushPresentationHandler` — foreground/open/native-fallback handling и локальные уведомления,
  - `FirebasePushCallbackRegistry` / `firebase_push_models.dart` — callback registry и shared push models.
- Внутренний push/call payload model унифицирован через `FirebasePushPayload`: UI open path, FCM open/foreground/native-fallback и iOS CallKit path не должны держать параллельные call-payload DTO.
- `AppBadgeService` владеет состоянием badge иконки приложения и синхронизирует platform badge как сумму непрочитанных сообщений и пропущенных звонков.
- `PeerAccessControlService` владеет локальными privacy/block правилами: contacts-only включен по умолчанию, `blockedPeers` хранится локально, а исходящие звонки к blocked peer запрещаются в `CallService`.
- `PushAccessPolicySyncService` отправляет schema-v2 privacy/block и
  notification-mute snapshot (`allowMessagesOnlyFromContacts`, контакты,
  `blockedPeerIds`, четыре direct/group списка message/call mute,
  `policyVersion`, `updatedAt`, `snapshotHash`) в `push.js` через
  `/devices/access-policy`. Изменение mute использует тот же sync path, но
  остаётся независимым от block state. При `stale` ответе сервис повторяет
  snapshot с версией выше `effectivePolicyVersion`; сервер фильтрует только
  соответствующий push fanout до APNs/FCM и никогда не relay delivery. iOS
  Notification Service Extension и App Group для этой схемы не используются.
- Для всех push-событий используется единый контракт `/events/push`: подписывается весь `payload` приложения, а сервер работает как transport-only fanout слой без собственной message/call-семантики.
- Если в `payload` присутствуют `servers` / `priority_servers`, они считаются runtime-метаданными приложения и обрабатываются только клиентом.
- `AccountIdentity` поверх device identity: `accountId`, `displayName`, список устройств и QR/deep link `peerlink://pair` для привязки второго устройства без изменения текущей device-based маршрутизации.
- Overlay router + dedup cache.
- HTTP relay-клиент с предварительным отбором живых relay, bounded active pool,
  quorum-write, best-effort ACK по точным replicas и трекингом статусов.
- Relay topology и object routing разделены: configured relay остаются
  локальным Settings-owned pool, relay от peer хранятся в
  TTL-ограниченном `PeerRelayDirectory`, а точные successful locations
  messages/blob используются для targeted operations. Входящий Chat metadata
  не merge-ит чужие relay в persistent configured pool.
- Reliable-envelope пайплайн декомпозирован на facade/service, inbound/session/poll controller-ы, pending store/retry scheduler и codec helpers.
- Group relay path для групповых чатов.
- Доставка personal media через relay blob + зашифрованный direct blob-reference payload.
- Direct media bytes в личных чатах шифруются до relay upload; `direct_blob_ref` помечается `mediaCipher=direct_session_v1`.
- Локальные preview thumbnail-ы для изображений хранятся рядом с managed media, backfill-ятся при загрузке истории и удаляются вместе с сообщением. Видео-preview намеренно использует компактный placeholder с play-overlay.
- Blob-транспорт для группового текста/медиа (upload blob + metadata delivery).
- Восстановление входящих relay-медиа использует persisted retry state и может продолжаться при повторном открытии чата, resume и восстановлении connectivity; Android foreground service для этого не используется.
- Server-side проверка членства группы на relay write path.
- Синхронизация состава группы через `/relay/group/members/update`.
- Ротация group key при изменении состава участников.
- Входящие `groupMembers(action=add/remove)` применяются только если transport
  sender совпадает с owner, уже известным из локального состояния или
  persisted group metadata; owner/admin из payload не являются authority.
- До signed назначения admin-роли управлять участниками в UI и application
  service может только owner.
- Chunked blob upload (`chunk` + `complete`) с fallback на single upload.
- Для encrypted group media используется компактный бинарный payload-формат `PLG2` (legacy decode path сохранен).
- Криптообработка больших group media вынесена из UI isolate в background isolate.
- В fetch GET path добавлен transient retry/backoff при обрывах соединения, включая преждевременное закрытие соединения до HTTP-заголовков.
- Relay runtime-пути теперь предпочитают только живые relay и ограничивают рабочий набор максимум 3 серверами для message/media операций.
- Relay control write, fetch и blob fetch выполняются параллельно по выбранным relay, чтобы не накапливать таймауты от недоступных серверов.
- Blob fetch расширяется за пределы текущего live shortlist после `404` от всех shortlist-кандидатов, прежде чем считать blob отсутствующим.
- Стек звонков декомпозирован на bounded controller/orchestrator-модули для peer bootstrap, connection, negotiation, media readiness, video signaling/transceivers/quality, remote control, terminal lifecycle, runtime tracking, epoch timers и diagnostics.
- Call-control слой использует два канала для критичных команд (`call_invite`, `call_accept`, `call_reject`, `call_end`): быстрый bootstrap signaling с bounded retry и резервный direct reliable control payload `__peerlink_call_control_v1__`, чтобы потеря signaling-пакета или временно разные bootstrap-состояния не оставляли вторую сторону в бесконечном дозвоне. Повторная доставка `call_invite` для уже текущего `peerId/callId` идемпотентна во всех не-idle фазах и не переводится в `call_busy`. Terminal lifecycle также отправляет финальный `call_end` тем же двойным путем до локального сброса runtime.
- TURN allocator и настройка TURN серверов из UI.

Ограничения:
- Bootstrap signaling остается централизованным по контракту, но runtime удерживает несколько bootstrap WebSocket-каналов одновременно через агрегатор.
- DHT-слой минимальный (`KademliaProtocol` как pass-through каркас).
- Runtime encryption для reliable-сообщений включен конфигом (`enableEncryption: true`).
- `PeerSession` сейчас поддерживает только direct transport mode.

## 3. Текущий граф зависимостей

```text
main.dart / app bootstrap
  -> AppCompositionRoot
    -> AppDependencies
      -> StorageService
      -> AppAppearanceController / AppLocaleController
      -> NetworkDependencies
      -> AppUiDependencies
        -> AppPushCoordinator / AppDeepLinkCoordinator
        -> AppCallCoordinator / AppLifecycleCoordinator / AppBadgeCoordinator
UI
  -> AppDependencies / NodeFacade
    -> MeshNode
      -> Identity / Session / Signature
      -> TransportManager
        -> PeerSession
          -> WebRtcTransport (direct)
      -> OverlayRouter
      -> RelayClient (HTTP)
      -> PushApiClient (HTTP)
      -> ModerationDeliveryService -> ModerationApiClient (HTTP)
      -> FirebaseMessagingService
      -> ReliableMessagingService
      -> ChatService
      -> CallService
      -> BootstrapSignalingService
      -> TurnAllocator
      -> RoutingTable / RecordStore / DhtTransport / KademliaProtocol
      -> NetworkEventBus
```

## 3.1 Application Composition (`lib/app`)

- `AppCompositionRoot` — top-level composition root Flutter-процесса.
- Он создает общий `StorageService`, конфигурирует storage-backed app services,
  создает runtime dependencies через `NetworkDependencies` и UI-facing
  dependencies через `AppUiDependencies`.
- `AppDependencies` — owned dependency container, а не global service locator.
  Bootstrap/UI получают зависимости явно через него.
- `AppPushCoordinator` владеет app-level FCM callback registration,
  opened-push call handling, moderation/group callback dispatch и relay polling
  для opened message pushes; UI сохраняет tab navigation ownership через
  injected callbacks.
- `AppDeepLinkCoordinator` владеет app deep-link parsing/dispatch для
  invite/config/pair/call ссылок.
- `AppCallCoordinator` владеет call-state subscriptions, terminal call-log
  recording, CallKit open-call events и missed-call badge refresh triggers.
- `AppLifecycleCoordinator` владеет app resume orchestration.
- `AppBadgeCoordinator` владеет app-icon badge sync для unread messages и
  missed calls.
- FCM background handler остается отдельным background isolate composition root,
  где platform constraints требуют отдельного lifecycle.

## 4. Границы слоев

### 4.1 UI (`lib/ui`)

- Экраны, виджеты, state-контроллеры.
- Существующие broad consumers могут временно использовать `NodeFacade` во время
  migration; новый и уже мигрированный код должен получать узкие capability
  contracts. App push/deep-link/call coordinators, active/call-history call
  surfaces, presence, restriction, Settings и Chat presentation/application
  seams уже не импортируют unrestricted `NodeFacade`.
- Runtime-локализация живет в `lib/ui/localization`: `AppLocaleController` сохраняет выбранный язык в settings storage, `AppStrings` дает lookup/formatting API и Flutter localization delegates для `MaterialApp`, а словари по языкам лежат в `lib/ui/localization/dictionaries`.
- Для экранов стандартизован шаблон композиции:
  - `*_screen.dart` для orchestration/state wiring,
  - `*_view.dart` для layout-виджетов,
  - `*_styles.dart` для констант дизайна.
- Chat-модули декомпозированы на отдельные компоненты (`chat_screen_view`, `chat_screen_helpers`, `chat_screen_unread_divider`, `chat_screen_media_actions`, `chat_screen_app_bar`, `chat_screen_message_list`, `chat_screen_audio_actions`, `chat_screen_actions`, `chat_screen_mime_type`, `chat_screen_scroll_coordinator`, `chat_screen_unread_target_resolver`, `chat_screen_lifecycle`, `chat_screen_viewport_state`, `chat_screen_presenter`, `chat_screen_back_swipe_coordinator`, `chat_screen_composer_coordinator`, `chat_controller_parts`, `chat_controller_media`).
- Вертикальное владение Chat начато в `lib/features/chat`: `domain` владеет
  `Chat`/`Message`, `infrastructure` владеет `ChatRepository`, а
  `application` владеет chat payload models, outbound codec, receipt handling,
  read-state handling и message mutation. SQLite/Drift-хранилище чатов теперь
  принадлежит `lib/features/chat/infrastructure/chat_database.dart`, а старый
  путь `lib/core/runtime/chat_database.dart` временно оставлен как
  compatibility export. Persistence сообщений находится за
  `ChatMessageStore` / `ChatDatabaseChatMessageStore`, а persistence summaries —
  за `ChatSummaryStore` / `ChatDatabaseSummaryStore`, поэтому `StorageService`
  больше не публикует chat message/summary business API. Старые пути
  `lib/ui/models` и часть `lib/ui/state/chat_*` временно оставлены как
  compatibility exports.
- `ChatScreen` теперь удерживает только orchestration/state wiring; AppBar, message list overlays, voice-recording flow, dialog/action flow, lifecycle wiring, viewport state, presentation-логика, composer/send/reply flow и back-swipe gesture вынесены в отдельные screen-модули.
- Пересылка сообщений вынесена в `ChatForwardService`; `ChatScreen` только открывает target sheet и вызывает сервис через callbacks `sendMessage`/`sendFile`.
- Inbound-классификация входящих сообщений вынесена в `chat_inbound_classifier.dart` (`ChatInboundClassifier`) с явными decode-зависимостями через конструктор.
- Outbound codec/transfer-id логика живет в `features/chat/application/chat_outbound_codec.dart` (`ChatOutboundCodec`) и используется из `ChatController` через явный импорт.
- Декомпозиция `ChatController` продолжена сервисами `chat_repository.dart`, `chat_summary_service.dart`, `chat_file_queue_service.dart`, `chat_outbound_service.dart`, `chat_inbound_service.dart`, `chat_read_state_service.dart`, `chat_receipt_service.dart`, `chat_contacts_service.dart`, `chat_group_service.dart`, `chat_direct_lifecycle_service.dart`, application facade-ами `chat_messages_api.dart` / `chat_groups_api.dart` и bounded coordinator-ами для inbound subscription, file send/progress/transfer, group inbound/outbound, group-control inbound, cleanup, history load, message send/retry и incoming media restore; контроллер должен оставаться orchestration/facade слоем.
- Базовая сборка chat-state зависимостей живёт в `features/chat/application/chat_controller_dependencies.dart` и собирается через `lib/app/composition/chat_controller_composition.dart`. `ChatController` получает Chat-owned `ChatRuntimeApi`; production адаптирует временный `NodeFacade` через `ChatRuntimeNodeAdapter`, а architecture tests запрещают `ChatController` / `features/chat/application` импортировать unrestricted `NodeFacade`.
- `ChatControllerComposition.create()` получает cohesive presentation/application ports (`ChatPresentationStatePort`, `ChatConnectionStatePort`, `ChatMessageStatePort`, `ChatMediaStatePort`, `ChatGroupStatePort`, `ChatNotificationPort`, `ChatLifecyclePort`, `ChatInboundPort`, `ChatAccountPayloadPort`) вместо десятков отдельных callbacks из `ChatController`.
- `ChatControllerDependencies` отдаёт grouped dependencies для persistence, messaging, groups, media/lifecycle и safety, а не плоский список concrete services.
- Message workflows в `ChatController` проходят через `ChatMessagesApi`: send, retry, mark-read, receipt/status updates, unread/badge sync и message mutations.
- Group workflows в `ChatController` проходят через `ChatGroupsApi`: создание групп, участники, metadata/avatar updates, group delete payloads, key rotation/sync и group cleanup.
- History workflows в `ChatController` проходят через `ChatHistoryApi`: initial
  load, pagination, unread anchor, persistence/unload loaded history, message
  offset lookup и group-key initialization.
- Cleanup и safety workflows проходят через `ChatCleanupApi` и `ChatSafetyApi`;
  presentation state не должен импортировать cleanup, moderation,
  access-control, group-key или relay-transfer implementations.
- Decode account pairing/membership payload-ов вынесен в `chat_account_payload_decoder.dart`, а формирование reply metadata — в `chat_reply_metadata_resolver.dart`; `ChatController` не должен возвращать эти helper-ответственности в свое тело.
- `ChatContactsService` использует общий `ContactsRepository` из
  `features/contacts`; отдельное чтение contacts storage в chat-state слое не
  должно возвращаться.
- PeerLink contacts остаются внутренней адресной книгой приложения по Peer ID; системные Contacts/address book не используются и не должны запрашиваться platform permissions.
- Contact domain и persistence ownership теперь живут в
  `lib/features/contacts`: `domain/contact.dart`,
  `infrastructure/contacts_repository.dart` и
  `contact_name_resolver.dart`. Старые пути `lib/ui/models/contact.dart` и
  `lib/core/runtime/contacts_repository.dart` временно оставлены как
  compatibility exports.
- Общие presentation formatters для Settings/account/storage/call экранов живут в `settings_screen_formatters.dart`, без локальных копий `formatBytes`, `shortId`, `formatDateTime`.
- Group crypto вынесена из `ChatController` в `lib/core/security/group_message_crypto_service.dart`, рядом с `group_key_service.dart`; UI/state слой не должен содержать собственную реализацию pack/unpack и encrypt/decrypt для group payload.
- `memberPeerIds` в group meta и runtime-потоках должны храниться в каноническом виде (`trim + unique + sort`), чтобы одинаковый состав участников не создавал ложные persistence-изменения только из-за порядка элементов.
- Для `groupMembers(action=add/remove)` авторизация должна разрешаться по
  pre-existing локальному owner до изменения `memberPeerIds`; owner/admin из
  payload не могут предоставить это право. `leave` остаётся отдельным
  member-originated потоком.
- Локальный group avatar path должен коммититься только после успешной рассылки `groupMembers(action=avatar)`; staging-файл при ошибке fan-out не должен оставлять локальное состояние группы в частично обновленном виде.
- Верхние страницы Contacts/Chats/Settings используют компактный layout с AppBar без описательных header-текстов; строки контактов, чатов и истории звонков разделяют одни compact spacing/internal-padding константы через `CompactCardTileStyles`.
- `MessageBubble` остается composition wrapper-ом; text/emoji, reply preview, status row, file/audio/video preview и transfer progress живут в отдельных `message_bubble_*` widget-модулях.
- `MessageBubbleStatusRow` показывает исходящие receipt-статусы внахлест: 1 галка для sent, 2 для delivered, 3 для read.
- Строки контактов показывают аватар, один display label (имя контакта или короткий peer id) и last-seen; строки чатов показывают аватар, название, последнее сообщение и badge непрочитанных без last-seen.
- Строки контактов помечают локально заблокированный Peer ID icon `block`; long-press меню контакта поддерживает rename и block/unblock.
- Строки чатов дополнительно показывают справа сверху receipt-галки последнего исходящего сообщения и timestamp последнего сообщения; timestamp форматируется как `ЧЧ:ММ`, `ДД:ММ` или `ДД:ММ:ГГ` в зависимости от даты.
- Attachment sheet в чате показывает только реализованные действия `Галерея` и `Вставить` плюс `Отмена`; placeholder-пункты `Файл`/`Геопозиция` удалены из UI.
- Строки контактов открывают action menu по долгому нажатию для переименования сохраненного display name без изменения peer ID.
- Действие `Пригласить` в Contacts одним tap вызывает `InviteFlowCoordinator.createInviteUrl()`: coordinator подписывает manifest локальной identity, отправляет его на `https://tangash.org/invites`, а UI сразу открывает системный Share Sheet со ссылкой `https://simplegear.org/i/<token>`. `peerlink://invite?payload=...` и `https://simplegear.org/invite?payload=...` остаются только legacy-форматами QR/direct-import. При входящем short invite coordinator валидирует manifest, применяет нужную server configuration, затем проверяет identity, добавляет/обновляет контакт и открывает/reuse direct chat.
- Invite имеет явное ownership: validation `InviteManifest` — domain,
  `InviteApi` и `PendingInviteStore` — application contracts, HTTP и Android
  Install Referrer — infrastructure. Retryable failure сохраняет только
  валидный token через Invite store и возобновляется на startup/app resume.
  `[invite]` diagnostics не содержит token, identity, manifest или error.
- Profile username использует существующий control-message transport avatar/profile: Settings рассылает обновление известным peers, QR-сканирование отправляет профиль сканирующего владельцу QR. Inbound update сохраняется через ContactsRepository, заменяет invite/fallback и старое имя, равное Peer ID, но не ручное имя, отличное от Peer ID. User QR содержит username как display metadata для поля «Имя».
- После успешного принятия short invite принимающий peer best-effort отправляет
  пригласившему своё настроенное имя и аватар через profile transport; ошибка
  profile sync не отменяет создание контакта и direct chat.
- Действие `Поделиться конфигурацией` в Settings создает текст с direct app link `peerlink://config?payload=...` и fallback `https://simplegear.org/config?payload=...` только с текущей доступной конфигурацией серверов. App-side config deep link напрямую merge-ит `bootstrap/relay/turn/push`, а QR scan/import сохраняет явный диалог выбора режима импорта.
- Доставка deep links на macOS нативная: `MainFlutterWindow` конфигурирует `DeepLinkChannel` созданным `FlutterViewController`, `AppDelegate` рано регистрирует URL handler-ы, а custom scheme (`peerlink://invite|pair|config|call`) и поддерживаемые web-ссылки передаются во Flutter. Android runner поддерживает тот же набор custom/web ссылок через app links.
- Блок `Аккаунт и устройства` в Settings показывает текущий `accountId`, количество известных устройств, QR `peerlink://pair` для привязки своего второго устройства и scan-flow для импорта pairing payload.
- Строки истории звонков используют компактные внутренние поля, меньший блок status-icon и плотный separator между строками; display name резолвится из текущих контактов с fallback на короткий peer id.
- Общая типографика централизована через `AppTheme.fontFamily` и применяется к text styles, AppBar, NavigationBar, inputs, dialogs и snackbars.
- Стартовое позиционирование прокрутки чата работает single-flight: `ChatScreen` планирует только один проход к низу/непрочитанному за раз, чтобы убрать дублирующиеся прыжки при открытии, а режим bottom несколько кадров догоняет список, пока восстановленные медиа еще могут менять высоту.
- Позиционирование к первому unread через probe ленивого списка ждет, пока смонтируется divider или message key, и не полагается только на ratio по индексу, который ломается на высоких failed media-placeholder.
- Переход по reply использует монотонный smooth-scan, чтобы смонтировать исходное сообщение перед финальным `ensureVisible`, вместо видимых чередующихся probe-прыжков.
- Пометка прочитанного в уже открытом чате учитывает низ списка и throttled single-flight scheduling: входящие обновления автоматически читаются только если пользователь уже был рядом с низом, иначе unread-состояние сохраняется.
- Выбор initial history window и unread-якоря при открытии чата пропускает входящие media-placeholder со статусом `Ошибка загрузки`, поэтому старые ошибки не уводят загруженное окно и viewport от новых сообщений.
- Пузырь видеофайла показывает компактный черный placeholder с play-overlay; `video_player` не должен инициализироваться внутри каждого message bubble.
- `MessageFilePreview`/audio/video preview используют асинхронный кеш доступности локальных файлов, а не синхронные `existsSync()` в build path.
- Media viewer показывает user-friendly fallback для Android codec errors вроде `video/dolby-vision` / HDR 10-bit и дает открыть исходный файл во внешнем приложении.
- Settings использует агрегированные карточки bootstrap/relay/turn на главном экране и отдельные list-screen экраны для управления каждой группой серверов.
- Settings содержит блок `Приватность и безопасность` выше self-hosted/server sections: contacts-only переключатель, user-facing safety policy summary и переход на отдельный экран заблокированных Peer ID с display name из контактов.
- Номер версии приложения показывается в Settings только в About/Legal, без отдельного верхнего footer перед первой карточкой.
- Сводные карточки серверов Settings подписаны на availability stream, а QR payload для server config обновляется при изменении доступности bootstrap/relay/turn/push.
- `SettingsScreen` декомпозирован: `settings_screen.dart` держит только lifecycle/wiring, composition/layout вынесены в `settings_screen_content.dart`, `settings_screen_identity_section.dart`, `settings_screen_account_devices_section.dart`, `settings_screen_server_sections.dart`, `settings_screen_preferences_sections.dart`, общий re-export account-секций идет через `settings_screen_account_sections.dart`, общие section/account widgets живут в `settings_screen_shared_widgets.dart` и `settings_screen_account_widgets.dart`, а dialog/action flow разнесен по `settings_screen_avatar_actions.dart`, `settings_screen_pairing_actions.dart`, `settings_screen_system_actions.dart`.
- Для bootstrap Settings показывает не legacy-ярлык `Активен`, а раздельные runtime/health статусы: `подключен` для реально открытого signaling channel, `доступен` для успешного probe без текущего channel, `недоступен` для failed probe.
- В `lib/ui/state` декомпозирован `SettingsController`: presentation статусов серверов вынесен в `settings_server_status_presenter.dart`, invite encode/parse — в `settings_invite_codec.dart`, pairing flow — в `settings_pairing_flow_service.dart`. Он получает `IdentityApi`, `NetworkApi` и `MessagingApi` вместо unrestricted `NodeFacade`; settings application services живут в `lib/features/settings/application`, а старые `lib/ui/state/settings_*` пути временно оставлены как compatibility exports.
- `UiApp` владеет presentation-shell state, screen composition, tab selection и
  Navigator/UI effects. Зависимости получает через `AppDependencies`, а
  non-presentation orchestration делегирует app-level coordinators.
- Calls теперь владеет call history persistence и native call bridge adapters в
  `lib/features/calls`: `infrastructure/call_log_repository.dart` и
  `platform/*call*_service.dart`. Старые пути `lib/core/runtime/*call*`
  временно оставлены как compatibility exports.
- Calls больше не зависит от concrete Chat fallback wiring внутри `MeshNode`:
  `CallService` использует port `CallControlTransport`, а
  `NetworkDependencies` связывает `ReliableCallControlAdapter` поверх
  `ChatService` для reliable fallback path.

### 4.2 Core Entry (`lib/core/node`)

- `NodeFacade`: compatibility/aggregate facade для UI/core migration.
- `node_capability_apis.dart`: узкие public contracts для messaging, calls,
  identity, network, moderation, presence и runtime events. `NodeFacade`
  реализует эти contracts, пока broad facade остается доступен internally
  during migration.
- Здесь находятся унифицированные точки входа для messaging/blob: `sendPayload(...)`, `uploadBlob(...)`, `downloadBlob(...)`.
- `MeshNode`: композиция, lifecycle, маршрутизация signaling и peer session orchestration.
- `MeshCallPushHelper`: call-oriented push registration и fanout (`/devices/register`, `/devices/unregister`, `/events/push`).
- `MeshSignalRouter`: выделенный routing seam для границы signaling -> `CallService` / peer transport внутри `MeshNode`.
- В security-слое криптосессия называется `CryptoPeerSession`, чтобы не конфликтовать с transport `PeerSession`.

### 4.3 Runtime (`lib/core/runtime`)

- `NetworkDependencies`: сборка dependency graph.
- `AppBootstrapCoordinator`: post-bootstrap конфигурация (сервера, background-задачи).
- Runtime storage (`StorageService` как facade, `storage_service_paths`, `storage_service_migrations`, `storage_service_media`). Feature repositories/database implementations должны жить в owning feature modules; legacy `core/runtime` import paths временно остаются только forwarding exports.
- Moderation принадлежит `lib/features/moderation`: domain содержит report
  models, application — policy/report/access workflows и узкие contracts,
  infrastructure — HTTP, delivery и persistent outbox. Пути `core/runtime/*`
  для этих модулей оставлены только compatibility exports.
- `ModerationLifecycleService` повторяет pending reports на startup, resume и
  recovery connectivity; Chat lifecycle не владеет moderation outbox.
- `StorageService` теперь выступает как orchestration/facade-слой над storage helper-модулями, держит runtime state на instance lifetime и не должен обратно разрастаться.
- SQLite chat storage хранит уникальность сообщений в пределах конкретного чата: ключ `(peerId, messageId)` не допускает вытеснения сообщения из одного чата записью с таким же `messageId` в другом чате.
- Real SQLite coverage для chat persistence идет через `ChatDatabaseChatMessageStore` в `test/core/runtime/storage_service_chat_messages_test.dart`.
- История звонков принадлежит `lib/features/calls/infrastructure/call_log_repository.dart`; `StorageService` оставляет только raw calls box для repository и cross-cutting badge logic.
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
- `SelfHostedDeployService`: SSH-оркестрация деплоя личного серверного стека, этапный прогресс (`1/14 ... 14/14`), post-deploy проверки доступности и фиксированные self-hosted endpoint-ы `wss://<ip>:443` / `https://<ip>:444`; сборка shell-команды деплоя вынесена в `SelfHostedDeployCommandBuilder`.
- Общие helper-ы нормализации/валидации host-ов и записи IPv6 host в URI живут в `ServerRuntimeUtils`; локальные копии safe-host/IP-check логики в server services не нужны.
- `AvatarService` теперь живет в `lib/features/profile/application`: хранит
  локальный avatar cache, embedded backup/restore, blob download и best-effort
  avatar announce/remove/query flow. Старый путь
  `lib/core/runtime/avatar_service.dart` временно оставлен как compatibility
  export. Chat использует avatar inbound handling через узкий contract
  `ProfileAvatarInboundHandler`, а profile sync использует
  `ProfileAvatarTransport` / `ProfileAvatarNodeAdapter` вместо зависимости от
  unrestricted `NodeFacade`.
- Remote display name/about хранится в typed `PeerProfileStore` независимо от
  Contacts: inbound update неизвестного peer не создаёт контакт. Изменение
  локального профиля отправляется как best-effort reliable control traffic:
  offline-получатель может получить поставленное в очередь обновление после
  запуска, но отдельного end-to-end подтверждения или полного повторного
  profile sync при каждом следующем запуске пока нет.
- `PeerProfileReadService` формирует snapshot для peer-card из Profile,
  Contacts и moderation contracts. Для текущего peer используются локальные
  name/about и скрываются peer-only actions уведомлений и добавления контакта.
  В peer-card и `GroupInfoScreen` имя выбирается в порядке local contact name →
  remote PeerLink profile → сокращённый Peer ID; справа у участника отображается
  owner/admin, если роль есть в additive metadata `adminPeerIds`.
- Строки участников `GroupInfoScreen` используют общий compact card/swipe-delete
  UI из Chats/Contacts. Owner и известный admin получают кнопку добавления у
  счётчика участников и могут запустить существующие workflows добавления или
  удаления другого non-owner participant; удалить себя или owner этим действием
  нельзя. Swipe-удаление требует явного подтверждения до запуска workflow.
- Сервисы проверки серверов теперь разделяют общий контракт `ServerAvailabilityProvider`, чтобы будущая runtime-оркестрация могла единообразно работать с probing для bootstrap/relay/turn.
- `ServerHealthCoordinator` владеет общими health-сервисами bootstrap/relay/turn и запускает их после app bootstrap, поэтому runtime и Settings используют одно и то же состояние доступности без дублирующихся probe loop.
- При полностью пустой локальной серверной конфигурации `ServerHealthCoordinator` запускает `InitialServerConfigBootstrapper`: он best-effort скачивает `https://simplegear.org/config/initial-server-config.json`, проверяет `ServerConfigPayload` и merge-ит bootstrap/relay/TURN/push. Недоступность сайта или некорректный ответ только логируются и не останавливают startup.
- Эти health-сервисы также используют общий polling/backoff engine, поэтому cadence повторных проверок унифицирован для bootstrap/relay/turn, а повторные неудачи автоматически увеличивают интервал probing.
- `TurnPriorityFailurePolicy` владеет только transient-статистикой ошибок TURN
  и ограниченным снижением приоритета; за `TurnServersService` остаются
  persistence, runtime-конфигурация и availability probing TURN.
- Начальная конфигурация применяется до UI, а явный общий refresh health-состояния
  выполняется в фоне: недоступные endpoint-ы обновляют availability snapshot без
  увеличения стартовой задержки.
- При общем refresh availability due-probes выполняются параллельно, чтобы несколько мертвых bootstrap/relay/turn endpoint-ов не суммировали startup/foreground latency последовательными timeout-ами.
- Bootstrap health refresh работает single-flight и переводит WebSocket connect timeout в availability snapshot `unavailable`, а не пробрасывает timeout exception из периодических проверок.
- `HttpRelayClient` и `TurnAllocator` подключены к coordinator-backed lookup-ам доступности relay/turn, поэтому runtime-выбор серверов использует те же shared health snapshot, что и Settings.
- Coordinator также реагирует на возврат приложения в foreground и на смену сетевой связности, инициируя общий refresh health-состояния без необходимости открывать Settings.
- Критичные relay-path теперь могут запросить адресный coordinator-backed refresh только для текущего relay shortlist, если общий relay snapshot устарел, без перепроверки всего relay-набора.
- TURN call setup теперь тоже может запросить адресный coordinator-backed refresh только для текущего TURN shortlist, если общий TURN snapshot устарел, без перепроверки всего TURN-набора.
- Версия приложения берется из `pubspec.yaml` (`version: x.y.z+n`) и автоматически прокидывается Flutter в Android/iOS.
- iOS deployment target и Flutter framework `MinimumOSVersion` должны оставаться `15.0`.

### 4.4 Messaging (`lib/core/messaging`, `lib/core/relay`)

- `ReliableMessagingService` теперь выступает как orchestration/facade-слой над reliable messaging подмодулями и не должен обратно разрастаться.
- Reliable messaging декомпозирован на:
  - `ReliableInboundProcessor` — decode reliable envelope, replay window, plain/secure inbound delivery и pending secure inbound queue,
  - `ReliableSessionController` — session establish/prekey fetch, handshake init/response, handshake retry и post-session flush,
  - `ReliableRelayPollController` — relay fetch cursor, poll/backoff loop, signature verify и ack path,
  - `ReliablePendingOperationStore` — persistence pending direct/group payload и group-members операций,
  - `ReliableRetryScheduler` — retry timer и durable retry/backoff policy,
  - `ReliableCodec` — envelope type и signature/header payload builders,
  - `ReliableOperationId` — стабильное формирование id pending reliable-операций.
- Relay ack привязан к durable delivery: direct/group chat envelope
  подтверждается только после awaitable-пути через `NetworkEventBus`, когда
  `ChatController` сохранил локальное сообщение или media placeholder. ACK
  адресно идёт во все exact fetched replicas; partial cleanup ретраится и не
  делает доставленный envelope failed.
- `HttpRelayClient`: интеграция `/relay/store`, `/relay/group/store`, `/relay/group/members/update`, `/relay/fetch`, `/relay/ack`, blob endpoint-ов.
- `RelayMediaTransferService` и `RelayMediaRetryCoordinator` теперь живут в `lib/core/relay`: relay media upload/download, restore result-модели и persisted retry orchestration больше не находятся в `ui/state`.
- Relay стратегия:
  - активный пул ограничен,
  - runtime-операции сначала выбирают только живые relay и используют не более 3 серверов,
  - запись использует quorum, а ACK best-effort идёт во все exact message replicas,
  - fetch агрегируется по активному пулу и commit-ит cursor только после durable local processing,
  - если healthy relay доступны, dead relay исключаются из активного пути доставки.
- Push fanout:
  - все push-события приложения отправляются подписанным `/events/push`,
  - приложение само формирует `payload` (`type`, `relay`, `servers`, `priority_servers` и прочие поля), а `push.js` только валидирует подпись и делает fanout по устройствам адресатов,
  - `push.js` отправляет одновременно `notification` и `data`, чтобы повысить видимость уведомлений на iOS в фоне.
  - в состояниях `background/killed` текст системного push-alert не модифицируется клиентом: отображается ровно `notification.title/body`, который отправитель сформировал, а `push.js` транзитно переслал через провайдер push.
  - для iOS добавлен native-to-Flutter fallback: если при cold start `getInitialMessage()` не вернул payload после тапа по уведомлению, клиент получает последний push payload из `AppDelegate` через `peerlink/push_payload/methods` и применяет merge серверов.
- Стратегия personal media/blob:
  - файл один раз загружается в relay blob storage с детерминированным direct-scope,
  - байты direct media шифруются session crypto до relay upload,
  - в личный чат доставляется зашифрованный `direct_blob_ref` по обычному reliable-message path,
  - прием personal media работает только через `direct_blob_ref` и загрузку blob из relay,
  - direct blob restore использует retry/timeout-обертку на скачивании,
  - после transient network error или временной недоступности relay входящий media restore автоматически продолжает retry позже при активном приложении/open-chat/resume/connectivity restore,
  - `blob not found` остается terminal stop, чтобы не запускать бесконечный restore loop,
  - Android foreground service для media restore не используется, поэтому `FOREGROUND_SERVICE_DATA_SYNC` не нужен,
  - post-download pipeline выполняется в порядке decrypt → save → durable
    message/SQLite persistence → retry-state clear → UI notify → best-effort
    thumbnail; успешный persistence очищает transfer status,
  - retry разрешён только для download/relay availability failures; decrypt,
    save и message-update failures имеют отдельные terminal UI statuses.
  - message ACK не удаляет связанный media blob: retention blob определяется
    отдельным TTL, поэтому возможны повторное открытие, второе устройство и
    cache recovery.
- Blob стратегия в группах:
  - при больших payload: chunked upload (`/relay/blob/upload/chunk`, `/relay/blob/upload/complete`),
  - fallback: `/relay/blob/upload`,
  - получение: `/relay/blob/:blobId`,
  - media/blob receive path не должен последовательно зависать на недоступных relay, если уже есть живые кандидаты.
- Удаление группового чата у всех доступно только owner'у: owner использует direct service-control fan-out (`groupChatDelete`) известным участникам и сохраняет локальный tombstone группы после очистки, чтобы устаревшие group-сообщения/invite не восстановили чат; не-owner отправляет `groupMembers` leave-событие, удаляется из состава owner-путем и затем удаляет локальную копию.

### 4.5 Calls (`lib/core/calls`)

- `CallService` должен оставаться тонким orchestration/facade-слоем над call helper-модулями и peer/runtime callback wiring, а не обратно собирать в себе все call-flow ветки.
- `CallControlTransport` — Calls-owned port для reliable call-control fallback.
  `ReliableCallControlAdapter` — текущий integration adapter поверх Chat
  control messages; `MeshNode` не должен напрямую связывать callbacks
  `ChatService` и `CallService`.
- `MeshNodeRuntimeAdapterFactory` владеет сборкой MeshNode integration helpers
  для push, moderation и signal routing. `MeshNode` передаёт runtime
  callbacks/state через `MeshNodeRuntimeAdapterContext` и использует готовый
  `MeshNodeRuntimeAdapters`.
- Декомпозиция `CallService` уже вынесена в helper-слои:
  - `CallCommandHelper` — публичные user/system команды (`start/accept/reject/end`),
  - `CallControlSignalHelper` / `CallControlSignalRouter` — ожидание signaling-ready и маршрутизация `call_*` control-сигналов,
  - `CallInviteFreshnessPolicy` — отбрасывание timestamp-based входящего `callId` старше двух минут до CallKit/UI в путях push и signaling; legacy non-timestamp ID остаются совместимыми,
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
- Android offer/answer guard-ы не должны вызывать `RTCPeerConnection.getLocalDescription()` до появления local SDP; тип local description нужно выводить из `getSignalingState()`, чтобы не ловить native null-SDP crash в `flutter_webrtc` release-сборках.
- Live media stall после активного звонка больше не является только диагностикой: inbound-only/full media stall переводит звонок в `recovering`, сбрасывает media-flow baseline и инициирует ICE restart offer; recovery очищается только после новых входящих media stats.
- `CallVideoController` управляет video state machine, transceiver/video-handle sync и quality policy.
- `CallMediaFlowController` управляет audio/video flow detection, stats polling и fallback логикой media-flow; stats polling intentionally остается умеренным, а repeated waiting-trace throttled, чтобы call diagnostics не становились hot path.
- `CallMediaReadinessController`, `CallLiveMediaStallDetector`, `CallPostIceRecoveryFlowWatch`, stats/recovery tracker-ы и diagnostics formatter держат media readiness/recovery observation вне facade-слоя.
- Remote control, renegotiation, video signaling/transceiver/quality, camera flip, runtime snapshot/tracking, signal transition serialization, terminal lifecycle и epoch-safe timer logic живут в отдельных `call_*` модулях.
- `CallPeerEventController` управляет binding WebRTC peer events к runtime state updates.
- `CallLocalMediaController` управляет local mute/speaker/camera/media-type toggles.
- Local self-preview в call UI прозрачен при выключенном local video и получает непрозрачный черный фон только при активной отправке видео.
- `CallConnectionStateController` управляет connected-state policy и моментом перехода transport в connected.
- `CallService` suppress-ит полностью идентичные `CallState` и не считает byte-counter updates полноценными state-transition trace-событиями, чтобы активный звонок не создавал лишний UI/state churn.
- `CallMediaStreamController` и `VideoStreamView` считаются частью hot media path: synthetic remote stream нельзя публиковать в UI пустым, no-op merge того же remote track не должен триггерить `onRemoteStream`, а renderer не должен повторно rebinding-ить тот же `MediaStream`/track без фактической смены источника.
- Для Android synthetic remote stream остаётся Dart-side выбором receiver track
  с исходным peer owner, а нативный incoming `MediaStream` передаётся в
  `RTCVideoRenderer` целиком, без `trackId`; это не даёт renderer использовать
  устаревший native track wrapper после renegotiation.
- `IosCallkitService` должен оставаться native bridge-слоем и не должен обратно забирать в себя orchestration merge серверов или payload normalization.
- Для снижения риска первого нативного WebRTC cold start после обновления приложения audio path использует одноразовый `audio-only` warm-up перед первым боевым `getUserMedia`, не затрагивая video transceiver/media-type flow.
- Текущая политика звонков: TURN-only для всех типов сети.
- Android release policy: R8 minify и resource shrinking включены с явными keep rules для `flutter_webrtc`, native `org.webrtc` и `org.jni_zero`. Build stack использует Flutter 3.47.5, AGP 9.0.1, Gradle 9.1 и built-in Kotlin AGP; app-модуль не применяет legacy Kotlin Gradle Plugin. `android.newDsl=false` остаётся временным opt-out: Flutter Gradle Plugin 3.47.5 всё ещё обращается к legacy AGP application extension при новом DSL.

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
- `NodeFacade` остается compatibility aggregate для границы UI/core на период
  migration; новый и мигрированный код должен предпочитать узкие capability
  contracts.
- Top-level app composition находится в `AppCompositionRoot`; сборка runtime
  graph остается делегированной в `NetworkDependencies`.
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
