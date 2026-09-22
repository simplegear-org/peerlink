# CHANGELOG

В этом файле фиксируются заметные изменения релизов приложения PeerLink.


## [3.14.2+2026092201] - 2026-09-22

### Изменено

- Изменение состава группы теперь доступно только owner. Клиент отклоняет
  membership-изменения от не-owner и конфликтующие owner-метаданные, поэтому
  недоверенное control-сообщение не может изменить или восстановить группу.
- Исправлен remote-video после renegotiation между Android и iOS: synthetic
  stream сохраняет owner peer receiver-трека, а native incoming stream
  передаётся renderer целиком. Это устраняет зависание видео из-за устаревшего
  native track wrapper.
- Отложенный timestamp-based `call_invite` старше двух минут отбрасывается до
  CallKit и in-app UI, поэтому после восстановления push/resume не возникает
  зомби-звонок.
- Android app-модуль переведён на AGP built-in Kotlin, а
  `url_launcher_android` обновлён для совместимости. Legacy opt-out нового DSL
  остаётся только из-за ограничения текущего Flutter Gradle Plugin.


## [3.14.1+2026092001] - 2026-09-20

### Изменено

- Android build stack обновлён до Flutter 3.47.5, AGP 9.0.1 и Gradle 9.1.
  В release-сборке сохранены R8 minify и resource shrinking.
- Для совместимости с AGP 9 обновлены Android-зависимости: `audioplayers`,
  `file_picker`, `flutter_secure_storage`, `mobile_scanner`, `record`,
  `saver_gallery`, `share_plus`, `video_player` и
  `flutter_webrtc 1.6.2+hotfix.3`. Вызовы file picker и сохранения в галерею
  переведены на актуальные API.
- AGP 9 пока работает с документированными Flutter compatibility opt-out для
  legacy DSL и Kotlin Gradle Plugin: они ещё нужны `flutter_webrtc` и
  `url_launcher_android`.
- Предупреждение upstream о декодировании bitmap в `FrameCapturer` осталось и
  в `flutter_webrtc 1.6.2+hotfix.3`; локальный fork не добавлялся. Известное
  Android-зависание remote video по-прежнему требует real-device regression
  проверки.
- Старт больше не ждёт availability-probe серверов до показа UI: сохранённая
  конфигурация серверов всё так же применяется первой, а health refresh идёт в фоне.
- Одновременные push device-state sync используют одну активную операцию, без
  повторной регистрации устройства и загрузки access-policy при запуске.

## [Unreleased]

## [3.14.0+2026091701] - 2026-09-17

### Изменено

- Добавлены локальное поле Profile «Обо мне», cache remote profile metadata и
  reusable страницы peer profile/group info. В peer-card и списке участников
  приоритет у локального имени контакта перед именем PeerLink и Peer ID; self-card скрывает
  peer-only действия, а роли owner/admin отображаются при наличии group metadata.
- В информации о группе используются compact-карточки участников; owner и admin
  могут добавлять участников и удалять другого non-owner participant свайпом влево.
- В peer/group card добавлены независимые persisted-переключатели уведомлений
  «Сообщения» и «Звонки». По умолчанию они включены; schema-v2 access-policy
  sync передаёт direct/group mute channels, а push-сервер подавляет только
  соответствующий fanout, не меняя relay delivery или block state.
- Фото в карточке профиля теперь сохраняет пропорции исходного изображения,
  не обрезается в круг и масштабируется на доступную ширину карточки.
- Добавлено cross-repo regression-покрытие mute/unmute, независимости
  messages/calls и block, а также schema-v1 compatibility.
- Исправлена быстрая последовательная смена notification mute: свежий snapshot
  синхронизируется после уже активного push-policy запроса.


## [3.13.2+2026091601] - 2026-09-16

### Изменено

- Одно нажатие в Contacts теперь создает подписанную короткую invite-ссылку.
- Relay ACK теперь адресно идёт во все exact message replicas после durable
  delivery. Partial cleanup ретраится позже и не делает delivery failed; ACK
  не удаляет media blob, retention которого определяется собственным TTL.
- Relay ACK tombstone теперь сохраняет recipient/message/время ACK/expiry и
  ограничен durable TTL garbage collection.
- Архитектура Invite разделена на domain/application/infrastructure в
  `features/invites`; `InviteApi` и `PendingInviteStore` отвязывают
  coordinator от HTTP и Settings UI. Android Install Referrer принадлежит
  Invite platform infrastructure.
- После принятия short invite принимающий peer best-effort отправляет
  пригласившему своё настроенное имя и аватар.


## [3.13.1+2026091002] - 2026-09-10

### Изменено

- Обычные приглашения контактов стали one-action flow: Contacts создаёт
  подписанную короткую ссылку и сразу открывает системный Share Sheet.
- В Settings добавлено редактирование локального имени PeerLink. Имя передаётся
  только как optional display metadata invite, а вручную заданные имена
  контактов сохраняются.
- Обработка invite теперь валидирует версию, срок, invite ID и identity binding
  до применения server configuration, контакта и direct chat.
- Создание invite теперь обращается к публичному API `tangash.org`, а shared
  ссылка по-прежнему использует `simplegear.org`.
- Website fallback short invite теперь открывает установленное приложение без
  показа legacy payload.
- Добавлены integration-проверки invite-клиента/coordinator и persistence на
  backend.
- Username теперь передаётся известным peer через существующий profile
  control-message, а QR-сканирование сразу отправляет профиль сканирующего
  владельцу QR. Ручные имена сохраняются; старое имя, равное Peer ID,
  обновляется как fallback.
- User QR содержит optional имя PeerLink и подставляет его в поле «Имя» после
  сканирования.
- Добавлены Android App Links, iOS Universal Links, durable pending-invite
  resume, Android Install Referrer recovery, безопасный iOS fallback и
  redacted invite lifecycle diagnostics.


## [3.13.0+2026091001] - 2026-09-10

### Изменено

- Добавлена общая relay replication policy: до трёх кандидатов с durable
  quorum 1/1, 2/2 или 2/3 для messages и media blobs.
- Blob upload теперь возвращает точные successful relay locations; direct и
  group media reference передают опциональные `blobRelayServers`, а получатель
  использует их первыми для targeted blob fetch, сохраняя legacy fallback.
- Relay topology discovery отделён от object routing: metadata relay из
  входящего chat-сообщения сохраняется в TTL-ограниченном
  `PeerRelayDirectory` и больше не merge-ит чужие endpoints в persistent
  configured relay pool.
- Добавлено regression-покрытие relay routing и architecture boundaries.
- Chunked media upload теперь делает одну попытку к relay с таймаутом пять
  секунд и затем переключается на следующий; упавший relay локально
  исключается на две минуты, поэтому устаревший общий health не задерживает
  следующие медиа.

### Проверено

- `dart format .`
- `flutter analyze`
- `flutter test test/architecture` (48 тестов)
- `flutter test test/core/relay/http_relay_client_test.dart`
- `flutter test` (449 тестов)

## [3.12.9+2026090902] - 2026-09-09

### Изменено

- Moderation выделен в bounded context `lib/features/moderation` с слоями
  `domain`, `application` и `infrastructure`.
- Добавлены узкие contracts `ModerationReportsApi`, `AccessPolicyApi` и
  `ModerationStatusApi`; Chat safety и inbound используют contracts.
- Retry durable outbox перенесён в `ModerationLifecycleService` (startup,
  resume и восстановление connectivity), вне Chat lifecycle.
- HTTP client, delivery и storage-backed report outbox перенесены в
  moderation infrastructure; старые `core/runtime` пути оставлены как
  compatibility exports.
- Добавлены architecture guards для moderation boundaries.
- Relay blob теперь реплицируется на все доступные relay выбранного рабочего
  набора (не более 3), а не только на quorum. Timeout во время chunked upload
  исключает relay из текущей операции; сохранение продолжается на остальных.
- Progress исходящей репликации стал одной монотонной шкалой до 100%, без
  повторного завершения для каждого relay.
- Входящее relay-media игнорирует запоздалые исходящие progress-статусы и не
  может показать «Отправка 100%» после получения.

### Проверено

- `dart format .`
- `flutter analyze`
- `flutter test test/architecture` (48 тестов)
- `flutter test`
- `flutter test test/core/relay/http_relay_client_test.dart`
- `flutter test test/features/chat/application/chat_media_restore_service_test.dart`
- `flutter analyze` для изменённых relay/chat файлов.


## [3.12.8+2026090901] - 2026-09-09

### Изменено

- Добавлен `ChatHistoryApi` для загрузки и выгрузки истории, пагинации,
  unread anchor, persistence и поиска message offset.
- Прямая mutation сообщений в `ChatController` переведена за `ChatMessagesApi`.
- Добавлены узкие `ChatCleanupApi` и `ChatSafetyApi`: cleanup, moderation,
  access policy, инициализация group keys и relay status больше не попадают в
  presentation state.
- Добавлены architecture guards для history, прямой mutation `Chat.messages` и
  запрещённых cleanup/moderation/crypto/relay imports.

### Проверено

- `dart format .`
- `flutter analyze`
- `flutter test test/architecture` (43 теста)
- `flutter test test/features/chat` (15 тестов)
- `flutter test` (438 тестов)


## [3.11.9+2026090802] - 2026-09-08

### Изменено

- Добавлен сценарий **«Заблокировать и пожаловаться»** для нарушителей.
- При блокировке пользователь и его контент теперь немедленно скрываются, одновременно создаётся жалоба для модерации.
- Добавлена очередь жалоб при отсутствии соединения и автоматическая повторная отправка.
- Улучшена обработка заблокированных пользователей в личных и групповых чатах.
- Жалобы интегрированы с существующей панелью модерации.
- Добавлен контроль 24-часового SLA обработки жалоб с предупреждением о приближении срока и статусом `OVERDUE`.
- Обновлены Terms & Safety с явной политикой нулевой терпимости к недопустимому контенту и нарушителям.
- Обновлена версия условий с обязательным принятием новой политики безопасности.
- Сохранена metadata-only модель модерации без передачи содержимого E2EE-сообщений, медиа, истории переписки и ключей шифрования.
- Добавлены автоматические тесты блокировки, жалоб, offline retry, скрытия контента, разблокировки и принятия условий.


## [3.11.8+2026090801] - 2026-09-08

### Исправлено

- Исправлено восстановление входящих relay-media в direct и group чатах на
  Android: после завершения загрузки файл один раз проходит расшифровку,
  сохранение, обновление сообщения и очистку retry-state без возврата в цикл
  скачивания.
- `localFilePath` сохраняется до best-effort генерации thumbnail, поэтому ошибка
  превью больше не отменяет успешно восстановленное медиа.
- Автоматический relay retry оставлен только для реальных ошибок загрузки и
  доступности relay; ошибки расшифровки, сохранения и persistence не запускают
  скачивание заново.
- Прерванный сохранённый статус теперь восстанавливается как `Повторная
  загрузка`, а новый прогресс может заменить устаревшую `Ошибка загрузки`.
- Добавлены отдельные локализованные статусы загрузки, расшифровки, сохранения и
  ошибок этих этапов. После успешного сохранения статус очищается.

### Диагностика

- Добавлены безопасные `[relay_media]` и `[chat_media]` stage-логи для download,
  decrypt, save, поиска/замены/persistence сообщения, очистки retry-state и
  генерации thumbnail.
- Эти диагностические записи сохраняются в логе приложения даже в режиме
  `Только ошибки` и дублируются в Android log output.
- Progress-логи ограничены изменением целого процента, чтобы ротация больше не
  вытесняла начало операции и group restore stages.
- Ошибки сохранения медиа содержат destination path, exception и stack trace,
  но не содержат encrypted payload или ключи.

### Проверено

- `flutter analyze`
- `flutter test` (428 тестов)
- Release-сборка установлена на Android обновлением без очистки данных.
- Direct и group relay media успешно восстановлены на устройстве; сохранённый
  direct trace подтвердил download, decrypt, save, SQLite persistence и retry
  clear.


## [3.12.7+2026090701] - 2026-09-07

### Изменено

- Продолжен архитектурный рефакторинг `ChatController`: добавлен
  `ChatMediaApi` / `ChatControllerMediaApi` как UI-facing media application
  facade.
- File send/cancel, queue resume, outgoing relay-media resume, incoming media
  restore/resume, thumbnails, progress/status helpers и media lifecycle
  disposal вынесены за `ChatMediaApi`.
- Снижена прямая связанность `ChatController` с concrete media coordinators и
  добавлен architecture guard против возврата direct media workflow imports.

### Проверено

- `dart format .`
- `flutter analyze`
- `flutter test`
- `flutter test test/architecture`
- `flutter test test/features/chat`
- `flutter test test/core/messaging`
- `flutter test test/core/relay`
- `flutter test test/ui/state`


## [3.12.6+2026090604] - 2026-09-06

### Изменено

- Продолжен архитектурный рефакторинг `ChatController`: giant callback
  contract в `ChatControllerComposition.create()` заменён на cohesive
  presentation/application ports.
- `ChatControllerDependencies` сокращён с широкого top-level dependency bag до
  grouped bundles для persistence, messaging, groups, media/lifecycle и safety.
- Добавлены application facades `ChatMessagesApi` и `ChatGroupsApi`, чтобы
  message/group workflows в `ChatController` не зависели напрямую от множества
  concrete chat services.
- Добавлены architecture guards для composition ports, grouped dependency
  surface и использования message/group facade в `ChatController`.

### Проверено

- `dart format .`
- `flutter analyze`
- `flutter test test/architecture`
- `flutter test`


## [3.12.5+2026090603] - 2026-09-06

### Изменено

- Оптимизация и рефактор `StorageService`


## [3.12.4+2026090602] - 2026-09-06

### Изменено

- Продолжена миграция PR5 на узкие capability API: добавлен `PresenceApi`,
  presence/restriction/settings/call-history UI surfaces и settings/runtime
  support services переведены с broad `NodeFacade` на узкие API или явные
  callbacks.
- Settings application services перенесены в `features/settings/application`,
  старые пути `lib/ui/state/settings_*` оставлены как временные compatibility
  exports.
- Завершён следующий срез сужения capabilities для `ChatController`: введён
  `ChatRuntimeApi` для runtime-нужд Chat, а production wiring идёт через
  `ChatRuntimeNodeAdapter` в `lib/app/composition`.
- `ChatController`, chat application services и связанные chat-тесты переведены
  с прямого `NodeFacade` на `ChatRuntimeApi` без изменения runtime behavior.
- Chat screens теперь читают local peer identity через `ChatController`, не
  проваливаясь через controller к runtime facade.
- Добавлены architecture guards, запрещающие `ChatController` и
  `features/chat/application` импортировать unrestricted `NodeFacade`.

### Проверено

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`
- `flutter test test/core/node/reliable_call_control_adapter_test.dart test/core/node/mesh_node_smoke_test.dart test/core/calls/call_service_test.dart test/architecture/feature_boundary_test.dart`


## [3.12.3+2026090601] - 2026-09-06

### Изменено

- Добавлен safety-net manifest test для CI/architecture/capability/critical-flow
  coverage; singleton runtime state убран из `NetworkDependencies.create`.
- Завершён первый срез PR7 runtime cleanup: call log/native call bridges
  перенесены в `features/calls`, contacts — в `features/contacts`,
  avatar/profile service — в `features/profile`, chat Drift database — в
  `features/chat/infrastructure`.
- Старые runtime/UI пути оставлены как временные compatibility exports.
- Добавлены architecture guardrails для explicit `core/runtime` inventory,
  migrated forwarding exports и запрета concrete cross-feature imports.
- Завершён PR8 MeshNode integration boundaries: введён `CallControlTransport`,
  добавлен `ReliableCallControlAdapter`, а Calls ↔ Chat reliable-control wiring
  вынесен из `MeshNode` в `NetworkDependencies`.
- Добавлены `MeshNodeRuntimeAdapterFactory` / `MeshNodeRuntimeAdapters`, чтобы
  сборка push, moderation, device sync, policy sync и signal-router helpers
  больше не была скрыта внутри constructor `MeshNode`.
- Добавлены тесты для call-control adapter, injected call-control transport,
  MeshNode callback-wiring guardrail и MeshNode `StorageService` construction
  / integration-helper construction guardrails.

### Проверено

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`
- `flutter test test/core/node/reliable_call_control_adapter_test.dart test/core/node/mesh_node_smoke_test.dart test/core/calls/call_service_test.dart test/architecture/feature_boundary_test.dart`


## [3.12.2+2026090504] - 2026-09-05

### Изменено

- Добавлены узкие node capability contracts: `MessagingApi`, `CallsApi`,
  `IdentityApi`, `NetworkApi`, `ModerationApi` и `RuntimeEventsApi`.
- `NodeFacade` сохранён как compatibility aggregate и теперь реализует новые
  узкие contracts.
- App push/deep-link/call coordinators и active call screen переведены с
  unrestricted `NodeFacade` на минимально нужные capability API.
- Добавлены contract и architecture tests, чтобы мигрированные app/call
  surfaces не возвращались к broad `NodeFacade` imports.
- Начат PR6 Chat vertical ownership в `lib/features/chat`.
- `Chat` и `Message` перенесены в `features/chat/domain`.
- `ChatRepository` перенесён в `features/chat/infrastructure`, а его тесты
  перенесены в `test/features/chat/infrastructure`.
- Non-presentation chat application services/coordinators/helpers перенесены в
  `features/chat/application`; `ChatController` и contact/forward UI-adjacent
  сервисы оставлены в `lib/ui/state`.
- Старые пути `lib/ui/models` и часть `lib/ui/state/chat_*` оставлены как
  временные compatibility exports.
- Добавлен architecture boundary test, запрещающий `features/chat` импортировать
  UI implementation code.

### Проверено

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`


## [3.12.1+2026090503] - 2026-09-05

### Изменено

- Добавлены `AppCompositionRoot` / `AppDependencies` как top-level application
  composition layer; runtime graph по-прежнему делегируется в
  `NetworkDependencies`.
- Добавлен `AppUiDependencies`, чтобы UI-facing controllers, repositories и
  presentation services создавались вне `UiApp`.
- Создание main app storage/runtime dependencies вынесено из `main.dart`, а
  architecture guardrails обновлены так, чтобы разрешать это только в
  `lib/app/composition`.
- Initial FCM push callback registration вынесен из `UiApp.initState` в
  `AppPushCoordinator`, при этом UI navigation оставлена через injected
  callbacks.
- PR4 завершён: push-open relay polling, deep-link dispatch,
  call-state/CallKit orchestration, lifecycle resume handling и app badge sync
  вынесены в app-level coordinators.

### Проверено

- `dart format lib/app test/app lib/ui/ui_app.dart lib/main.dart`
- `flutter analyze`
- `flutter test test/app/push/app_push_coordinator_test.dart test/app/deep_links/app_deep_link_coordinator_test.dart test/app/calls/app_call_coordinator_test.dart test/app/lifecycle/app_lifecycle_coordinator_test.dart`
- `flutter test`


## [3.12.0+2026090502] - 2026-09-05

### Изменено

- Добавлена CI-валидация format/analyzer/tests.
- Добавлены architecture/import-boundary tests для presentation dependency
  construction, composition ownership, feature boundaries и platform bridge
  imports.
- Production storage ownership сделан явным: `main.dart` создаёт общий
  `StorageService` и передаёт его в `NetworkDependencies.create(...)`.
- Убрано скрытое создание `StorageService()` из основного runtime graph в
  network, push, notification, CallKit и server-merge wiring.
- FCM background handler оставлен явным background-isolate composition root со
  своим storage lifecycle.
- `test/` добавлен в manifest публичного source mirror.

### Проверено

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`


## [3.11.2+2026090501] - 2026-09-05

### Изменено

- Версия приложения поднята до `3.11.2+2026090501`.
- Категория приложения для Apple-платформ изменена с `Utilities` на
  `Social Networking`.
- Официальная hosted-зависимость `flutter_webrtc` обновлена с `1.5.0` до
  `1.6.1`, а iOS WebRTC SDK — с `144.7559.09` до `150.7871.01`, чтобы удалить
  ссылку на запрещенный App Store API
  `RPSystemBroadcastPickerView.buttonPressed:`. Локальный fork не используется.

### Проверено

- `flutter analyze`
- `flutter test`
- `flutter build ios --release --no-codesign`
- В собранном iOS-приложении отсутствует строка
  `RPSystemBroadcastPickerView.buttonPressed:`.


## [3.11.1+2026090102] - 2026-09-01

### Изменено

- Клиент `POST /devices/access-policy` теперь читает `stale` ответ push-сервера
  и повторяет snapshot с версией выше `effectivePolicyVersion`, чтобы unblock не
  оставлял на сервере старый `blockedPeerIds` после отката локальной версии.


## [3.11.0+2026090101] - 2026-09-01

### Изменено

- Добавлен единый путь синхронизации push device-state: регистрация токенов и
  access-policy snapshot теперь выполняются вместе на startup/resume,
  регистрации push-token, изменении push-серверов, block/unblock и изменении
  режима contacts-only.
- Ошибки регистрации push-устройства больше не блокируют отправку
  access-policy snapshot на доступные push-серверы.
- Timestamp для access-policy sync нормализуется до UTC milliseconds перед
  подписью, чтобы совпадать с canonical signature format push-сервера.
- iOS signing теперь использует один app target/profile; Notification Service
  Extension и App Group entitlement не используются для server-side push
  blocking.
- При старте с полностью пустой конфигурацией серверов приложение теперь
  best-effort скачивает `https://simplegear.org/config/initial-server-config.json`
  и импортирует bootstrap/relay/TURN/push из публичного QR `Конфигурация
  серверов`; недоступность сайта не блокирует запуск.


## [3.10.2+2026082701] - 2026-08-27

### Изменено

- Модерация разделена на отдельные bounded-сервисы: HTTP-клиент `/moderation/*`, delivery orchestration, policy snapshot и UI-gate больше не размазаны по push/UI слоям.
- После отправки апелляции экран ограничения аккаунта скрывается, но сохраненный ban продолжает блокировать отправку сообщений и звонки до `unban`.
- Клиент применяет `moderation_policy action=unban` и очищает локальный ban.
- Warning теперь показывается fullscreen-экраном с кнопкой `Продолжить`; Settings показывает текущий warning/ban красным под Peer ID/QR.
- iOS native push bridge теперь сразу передает silent `moderation_policy` в Flutter, если приложение/engine живы.
- Повторный вход не показывает fullscreen warning/ban повторно, если warning уже подтвержден или appeal уже отправлена.
- Клиент проверяет `signedStatus` moderation policy при заданном `MODERATION_STATUS_SIGNING_PUBLIC_KEY` и отклоняет неподписанные/поддельные moderation events.

### Проверено

- `dart analyze`
- `flutter test test/core/runtime/moderation_api_client_test.dart test/ui/state/app_restriction_controller_test.dart test/ui/screens/chat_report_actions_test.dart test/core/runtime/moderation_report_service_test.dart test/core/runtime/moderation_policy_service_test.dart test/core/firebase/firebase_push_payload_test.dart`


## [3.10.1+2026082601] - 2026-08-26

### Изменено

- Клиент сохраняет `moderation_policy` push-события: warning показывает предупреждение, ban открывает экран ограничения аккаунта и оставляет только отправку апелляции.
- Warning/ban текст строится на локали пользователя и включает количество жалоб и число уникальных жалобщиков без раскрытия Peer ID.
- Клиент опрашивает `/moderation/status` на startup/resume и принудительно перерегистрирует push token, чтобы moderator warn/ban применялся после рестарта push-сервера.
- При сохраненном ban приложение не показывает обычные входящие push-сообщения/звонки и не открывает коммуникационный UI.
- Жалобы на UGC теперь metadata-only: текст/медиа сообщения не отправляются модератору, а выбранное сообщение скрывается локально у репортера.
- Для групповых сообщений report таргетит автора сообщения и передает только metadata (`groupId`, message id/type/timestamp), без содержимого.
- Push registration новых клиентов отправляет v2 identity binding в существующем `/devices/register`, чтобы сервер мог привязать `peerId` к `signingPub` без дополнительного запроса.


## [3.10.0+2026082401] - 2026-08-24

### Добавлено

- В Settings добавлен блок `Приватность и безопасность` с переключателем приема сообщений и звонков только от контактов, кратким описанием политик безопасности и переходом к списку заблокированных Peer ID.
- Добавлена локальная блокировка Peer ID: заблокированный отправитель не создает видимые входящие сообщения, звонки и push-уведомления.
- Исправлена блокировка звонков: исходящий вызов к заблокированному Peer ID теперь не стартует, а Android fullscreen notification и iOS CallKit проверяют native-копию blacklist до показа входящего звонка.
- В личном чате и во вкладке `Контакты` добавлены действия `Заблокировать` / `Разблокировать`.
- В списке контактов заблокированные контакты помечаются значком блокировки.
- Добавлен отдельный экран заблокированных пользователей; если Peer ID сохранен в контактах, показывается имя контакта.
- Добавлены переводы новых privacy/safety строк для EN/RU/ES/FR/ZH.

### Изменено

- Версия приложения поднята до `3.10.0+2026082401`.
- Входящие bootstrap/push call invite-ы и открытие push теперь проверяют локальные privacy/block правила до показа звонка или уведомления.

### Проверено

- `flutter analyze`
- `flutter test test/core/calls/call_service_test.dart test/core/runtime/peer_access_control_service_test.dart test/ui/state/chat_inbound_service_test.dart`
- `flutter build apk --debug`
- `flutter build ios --debug --no-codesign`


## [3.9.4+2026082301] - 2026-08-23

### Изменено

- Android release-сборка включает R8 minify и resource shrinking; совместимость
  AGP 9+ требовала отдельной проверки Flutter, Gradle и plugins.
- Журнал вызовов теперь показывает актуальное имя из контактов, если контакт сохранен; без контакта остается короткий peer id.
- Входящий accept runtime-enrichment wait увеличен до 8 секунд, чтобы новая версия успевала принять bootstrap/TURN metadata перед ответом на звонок.
- Критичные команды звонка (`call_invite`, `call_accept`, `call_reject`, `call_end`) теперь дублируются через direct reliable control payload `__peerlink_call_control_v1__` и дополнительно повторяются bounded-таймерами поверх bootstrap signaling.
- После активного звонка остановка входящего RTP/media stats при продолжающемся outbound traffic больше не считается живым каналом: звонок переходит в видимое восстановление и инициирует ICE restart offer.

### Исправлено

- Исправлен сценарий, где кнопка `Ответить` могла завершаться ошибкой `Signaling еще не готов`: при временно недоступном bootstrap ответ отправляется резервным reliable-каналом, а signaling продолжает восстановление.
- Исправлен сценарий, где `Отклонить`/`Завершить` могли не доходить до второй стороны и оставлять ее в бесконечном дозвоне.
- Исправлен terminal-сброс звонка, когда у звонящего экран закрывался локально, а у принимающего оставался активный экран со статусом `Транспорт звонка прерван`.
- Исправлен сброс звонка сразу после ответа из-за позднего reliable-повтора `call_invite`: повтор текущего `peerId/callId` больше не превращается в `call_busy`.
- Исправлен сброс Android release-звонка сразу после ответа: добавлены app-level R8 keep rules для `flutter_webrtc` / native WebRTC классов.
- Из offer/answer guard-ов убраны небезопасные Android-вызовы `getLocalDescription()`, чтобы избежать native null-SDP crash сразу после ответа на звонок.
- Исправлен сценарий после смены сети во время звонка: UI больше не показывает мертвый media path как обычный активный звонок только из-за роста счетчиков `Канал`.

### Проверено

- `flutter test test/core/calls`
- `flutter analyze`
- `flutter build apk --release`


## [3.9.3+2026082201] - 2026-08-22

### Изменено

- Обновлены release metadata до `3.9.3+2026082201` и source snapshot tag `source-v3.9.3-build-2026082201`.
- Android/iOS WebRTC dependency закреплена на `flutter_webrtc 1.5.0`, чтобы избежать Android-регрессии с зависанием поздно включенного remote video.
- Номер версии на главном экране Settings оставлен только в разделе About/Legal, без дублирующего footer сверху.

### Исправлено

- Исправлена обработка call-end push/deep-link payload: `call_invite` с `callAction=end` больше не открывает входящий звонок и сначала завершает runtime-сессию.
- Outgoing call timeout теперь привязан к актуальному call epoch после reset runtime tracking, чтобы поздний timer не задевал новый звонок.
- Локальная миниатюра своего видео в звонке прозрачная при выключенной камере и получает непрозрачный черный фон только при активной трансляции видео.
- Пометка чата прочитанным теперь throttled и bottom-aware с более строгим порогом, чтобы снизить лишние read-события при прокрутке.


## [3.9.2+2026081501] - 2026-08-15

### Изменено

- Обновлены release metadata до `3.9.2+2026081501` и source snapshot tag `source-v3.9.2-build-2026081501`.

### Исправлено

- Исправлены TURN credentials для self-hosted deploy: теперь стабильно используется настроенная учетная запись `peerlink`.
- Исправлена валидация public snapshot для changelog-записей с build suffix.


## [3.9.1] - 2026-08-14

### Изменено

- Очищены публичные README: теперь они ссылаются только на файлы и workflows,
  которые входят в public source mirror.
- Уведомление об AI-authorship перенесено вверх в английском README.
- В Settings About & Legal разделены версия продукта, open-source license,
  ссылка на исходный код конкретной версии и действие third-party licenses.
- Добавлены MPL-2.0 source headers в project-authored platform/tooling файлы.
- Обновлены public snapshot metadata для `3.9.1+2026081401`.

### Исправлено

- Усилен public mirror tooling: добавлены генерация source metadata и проверка
  согласованности snapshot.
- Исправлен parsing в release preparation: Flutter hook output больше не
  попадает в release version.

## [3.9.0] - 2026-08-14

### Лицензирование

- Snapshot-ы исходного кода PeerLink X начиная с этого релиза
  распространяются под Mozilla Public License 2.0 (MPL-2.0).
- Более ранние публичные релизы распространялись под MIT.
- Может быть доступно отдельное коммерческое лицензирование.
- Публичный GitHub-репозиторий ведется как append-only mirror публичных
  source snapshot-ов, а не как копия внутренней истории разработки.

## [3.8.0] - 2026-08-12

### Добавлено

- Добавлен receipt/read-state для исходящих сообщений: 1 галка после подтвержденной отправки в relay, 2 галки после durable-сохранения у получателя, 3 галки после прочтения.
- Для групповых чатов 2/3 галки появляются по правилу `хотя бы один участник доставил/прочитал`; per-peer receipt maps сохраняются в JSON сообщения.

### Изменено

- Галки статуса исходящих сообщений теперь отображаются внахлест.
- В списке чатов справа сверху у строки теперь показываются receipt-галки последнего исходящего сообщения и время/дата последнего сообщения в формате `ЧЧ:ММ`, `ДД:ММ` или `ДД:ММ:ГГ`.
- Из меню скрепки чата удалены placeholder-пункты `Файл` и `Геопозиция`; оставлены `Галерея`, `Вставить`, `Отмена`.
- Номер версии приложения перенесен в самый верх главного экрана Settings с прежним footer-форматированием и межсекционным отступом.
- Release version поднята до `3.8.0+2026081201`.

### Проверено

- `dart analyze`
- `flutter test test/ui/state/chat_group_flow_service_test.dart test/ui/state/chat_inbound_service_test.dart test/core/runtime/storage_service_chat_messages_test.dart`

## [3.7.6] - 2026-08-12

### Изменено

- Стартовый viewport чата переведен на reversed list: открытие сначала стабилизирует низ списка, затем без видимого сканирования переходит к первому непрочитанному сообщению.
- Initial history window снова загружает последние сообщения, а первый persisted unread anchor ищется отдельно для стартового перехода.
- При закрытии экрана чата загруженные сообщения выгружаются из памяти после сохранения, чтобы снизить удержание тяжелых медиа-историй.
- Video preview в bubble теперь всегда показывает компактный черный placeholder с play-overlay; native video thumbnail generation на Android/iOS/macOS удален, image thumbnail generation сохранен.
- Зависимости обновлены под текущий релиз: Firebase Core/Messaging, file_picker, share_plus, flutter_secure_storage и sqlite3_flutter_libs.

### Исправлено

- Android release checklist и AI context фиксируют требование проверять наличие `lib/*/libsqlite3.so` в APK; `sqlite3_flutter_libs 0.6.0+eol` нельзя использовать без отдельной миграции native sqlite.
- Для iOS Podfile добавлен modular header для `FirebaseMessaging`.

### Проверено

- `flutter test test/ui/state/chat_repository_test.dart`

## [3.7.3] - 2026-08-11

### Изменено

- Исходящая отправка группового медиа теперь после успешной загрузки blob может доставить зашифрованную ссылку участникам напрямую, если relay group write отклонен из-за устаревшего состава группы.
- Успешный direct fallback для группового медиа очищает pending group payload, чтобы reliable scheduler не продолжал повторять уже доставленное сообщение.
- Ошибка `owner mismatch` при синхронизации состава группы считается терминальной для pending `groupMembers` операции и удаляется из очереди retry.
- Возобновленная отправка relay-медиа теперь помечает сообщение отправленным только после подтвержденного relay store receipt.

### Проверено

- `flutter test test/ui/state/chat_group_flow_service_test.dart test/ui/state/chat_outgoing_relay_media_resume_service_test.dart`
- `flutter analyze`

## [3.7.0] - 2026-08-09

### Добавлено

- В Settings добавлен раздел `Обмен серверами через push` с переключателями отправки своих серверов и приема серверов от других клиентов.

### Изменено

- Если отправка своих серверов выключена, push-события больше не включают блоки `servers` и `priority_servers`.
- Если прием чужих серверов выключен, входящие push/runtime payload-ы не merge-ят полученные bootstrap/relay/push/turn серверы в локальную конфигурацию.
- Переключатель приема чужих серверов доступен только при включенной отправке своих серверов; при выключении отправки прием автоматически выключается.
- Android release подготовлен как `3.7.0+2026080901`.

### Проверено

- Собраны Android release artifacts: `build/app/outputs/bundle/release/app-release.aab` и `build/app/outputs/flutter-apk/app-release.apk`.
- `flutter analyze` проходит без ошибок.
- APK проверен: `versionName=3.7.0`, `versionCode=2026080901`, release-подпись v2 валидна.

## [3.6.6] - 2026-08-06

### Добавлено

- Добавлены локальные thumbnail-ы для изображений и видео в чатах; Android/iOS/macOS native bridge извлекает пригодные кадры видео, а image thumbnail генерируется вне UI isolate.
- Добавлен кеш асинхронной проверки доступности локальных медиафайлов, чтобы message bubble не блокировали rebuild синхронными проверками файловой системы.

### Изменено

- iOS deployment target и Flutter framework `MinimumOSVersion` подняты до `15.0` под требование App Store Connect с весны 2027 года.
- Байты direct media в личных чатах шифруются до загрузки в relay, а metadata `direct_blob_ref` помечается `mediaCipher=direct_session_v1`.
- Подготовка, upload, локальное сохранение и thumbnail generation для direct/group media вынесены в общий `ChatMediaOutboundService`.
- Видео-bubble теперь показывает сохраненный thumbnail с play-overlay вместо инициализации `video_player` внутри каждого preview.
- Карточки серверов Settings и экспортируемые QR payload обновляются по availability stream, а загрузка storage breakdown кратковременно кешируется.
- Строки контактов обновляют presence построчно, без rebuild всего списка на каждый presence tick.
- Для desktop/web включено drag-scrolling через общий app scroll behavior.

### Исправлено

- Удален неиспользуемый доступ к системным контактам на iOS/macOS: нет `NSContactsUsageDescription`, macOS address-book entitlement и зависимости `flutter_contacts`.
- Thumbnail-файлы удаляются вместе с managed media при удалении сообщения.

## [3.6.5] - 2026-08-01

### Добавлено

- Android получил native FCM handler для `call_invite` data-push: в фоне входящий звонок показывается как high-priority fullscreen call notification и открывает `peerlink://call?...`.
- Добавлен Android bridge для очистки call notification из status bar после просмотра раздела звонков.

### Изменено

- Push входящего звонка в стандартном FCM path стал data-only; системное отображение теперь решает клиент.
- Foreground push на iOS и Android больше не показывает системные уведомления: сообщения обновляют UI/счетчики, звонки показывают экран входящего вызова.
- В активном iOS-приложении входящий VoIP push больше не регистрируется в CallKit; CallKit остается для фонового/закрытого состояния.
- Push-сервер нормализует FCM data payload к строковым значениям, включая JSON для вложенного блока `servers`.
- Поле ввода сообщения использует заглавную букву в начале предложений, многострочную клавиатуру и кнопку новой строки; отправка остается через UI-кнопку.
- При открытии клавиатуры экран чата поднимает список и composer над клавиатурой и удерживает позицию у последних сообщений.
- В сгруппированной истории звонков отображается статус последнего звонка, а не сумма пропущенных в группе.

### Исправлено

- Android больше не показывает push/local notification, когда приложение активно; сообщения обновляют счетчики чата, а звонки используют уже открытый экран входящего вызова.
- Android call notifications очищаются из status bar после просмотра информации о звонках в приложении.
- Пропущенный звонок на Android не помечается просмотренным автоматически при записи истории, поэтому badge приложения сохраняет счетчик до открытия раздела звонков.
- Устранена гонка в `peerlink_servers` signal test: ожидания `register_ack` создаются до отправки register frames.

## [3.6.4] - 2026-07-31

### Добавлено

- В меню долгого нажатия на сообщение добавлен пункт `Переслать`: после выбора открывается список чатов и контактов, отсортированный по свежести сообщений, а выбранное текстовое сообщение или медиа дублируется в целевой чат.
- Для пересылки медиа добавлен отдельный `ChatForwardService` и unit-тесты сортировки целей/отправки копии, чтобы не наращивать бизнес-логику в `ChatScreen`.
- При ошибке воспроизведения iPhone Dolby Vision/HDR видео на Android показывается понятное сообщение и кнопка открытия файла во внешнем приложении.

### Изменено

- Входящие relay-медиа, которые не успели полностью восстановиться из-за недоступности серверов, теперь остаются возобновляемыми и продолжают попытки при открытии чата, resume приложения и восстановлении сети.
- Пересылка медиа запускается после закрытия списка адресатов и использует асинхронные проверки файла, чтобы выбор адресата не блокировал UI.
- VSCode launch-профили сохранены с прежними именами, но больше не фиксируют конкретный `deviceId`; устройство выбирается отдельно в VSCode перед запуском нужного профиля.
- iOS metadata синхронизирована под релиз `3.6.4+2026073101`.

### Исправлено

- `RelayMediaRetryCoordinator` больше не считает временную недоступность relay окончательным отказом для незавершенных incoming media; подтвержденный `not_found` по-прежнему останавливает retry.
- Stale in-progress incoming media placeholders нормализуются и возобновляются через persisted retry state вместо зависания в состоянии `Получение из relay`.
- Android foreground-service restore удален, поэтому приложение больше не запрашивает `FOREGROUND_SERVICE_DATA_SYNC`.
- Android debug-сборка после изменений проходит успешно.

## [3.6.3] - 2026-07-30

### Изменено

- Отображаемое имя приложения на Android, iOS, macOS и в iOS CallKit обновлено на `PeerLink X`; bundle id, package id и custom scheme `peerlink://` не менялись.
- Текст шаринга приглашений и конфигурации серверов теперь мультиязычный и содержит две ссылки с одинаковым payload: основную `peerlink://...` для прямого открытия приложения и fallback `https://simplegear.org/...`.
- QR/direct-open для приглашений по-прежнему использует `peerlink://invite?payload=...`; экспорт конфигурации дополнительно получил direct-link формат `peerlink://config?payload=...`.
- Call runtime дополнительно декомпозирован на bounded-модули для media readiness, remote control, renegotiation, video signaling/transceivers/quality, terminal lifecycle, runtime tracking, epoch timers и diagnostics.
- Chat state дополнительно разнесен на focused inbound/outbound handler-ы, file/history/cleanup/message coordinator-ы, reply metadata resolver, account payload decoder и отдельные message bubble widget-модули.
- Обработка Firebase push payload разделена на parser-ы, server-storage merge/update parsing и formatter логов.
- Android release поднят до `3.6.3+2026073001`; итоговые артефакты имеют `versionName=3.6.3`, `versionCode=2026073001`.
- iOS generated build settings синхронизированы с `pubspec.yaml`: `MARKETING_VERSION=3.6.3`, `CURRENT_PROJECT_VERSION=2026073001`.

### Исправлено

- Из Android manifest удалены неиспользуемые и чувствительные разрешения, включая `MANAGE_EXTERNAL_STORAGE`, storage/media permissions, contacts/call-log, exact alarm, Wi-Fi change/state, `BLUETOOTH_ADMIN` и vendor badge permissions.
- В release APK/AAB подтверждено отсутствие `USE_EXACT_ALARM` и `MANAGE_EXTERNAL_STORAGE`; в итоговом manifest оставлены только разрешения, необходимые для QR, сети, уведомлений/push, WebRTC-аудио/звонков и background runtime.
- Добавлено покрытие реального SQLite `StorageService` для записи/чтения сообщений чата, чтобы регрессии persistence проверялись на фактическом database path.

## [3.6.1] - 2026-07-21

### Изменено

- Android/macOS app-link и custom-scheme обработка усилена для `peerlink://invite`, `peerlink://pair`, `peerlink://config`, `peerlink://call` и поддерживаемых `https://simplegear.org/...` ссылок; на macOS deep-link канал теперь конфигурируется из `MainFlutterWindow`, URL handler-ы регистрируются рано, а pending links сохраняются до старта Flutter.
- Server-config deep links теперь напрямую merge-ят вложенный payload `bootstrap/relay/turn/push`, а QR/manual import сохраняет явный диалог выбора режима импорта.
- Invite handling теперь merge-ит вложенную доступную конфигурацию серверов до проверки self-contact, поэтому self-invite ссылки могут импортировать серверные настройки.
- FCM runtime-слой дополнительно разделен на inbound orchestration, payload processing и presentation модули: `FirebasePushInboundService`, `FirebasePushPayloadProcessor`, `FirebasePushPresentationHandler`.
- Сборка push fanout вынесена в `PushEventFactory`, `PushRuntimeMetadataBuilder` и `PushEventService`; `PushApiClient` остается низкоуровневым signed HTTP client.
- Управление badge иконки приложения идет через `AppBadgeService`, который хранит unread/missed-call счетчики и синхронизирует platform badge.
- Opened push handling может сначала poll-ить hinted relay servers, а затем выполнять полный relay poll, чтобы ускорить восстановление, если у получателя еще нет актуального relay-набора отправителя.
- Incoming call push может сразу показать входящий звонок из UI open path, а call/video controllers получили дополнительные guard-ы для local media state, renderer reuse и stale call events.
- Для Android App Links добавлен `web/.well-known/assetlinks.json` на публичном сайте.

### Исправлено

- Self-hosted деплой больше не использует пайп для `sudo`-авторизации и сначала скачивает удаленный bootstrap-скрипт перед запуском, вместо прямого пайпа `wget` в `bash`; это убирает ложные падения с exit code `141`, а при ошибке удаленной команды теперь показываются последние строки вывода.
- Прогресс self-hosted деплоя, readiness retry и известные ошибки деплоя теперь идут через типизированные события/исключения и локализуются словарями приложения вместо hardcoded текста сервиса.
- Локальная iOS-установка `Release` теперь использует provisioning profile `AdHoc` вместо App Store профиля `iOSProd`.

## [3.4.5] - 2026-06-19

### Изменено

- Продолжен runtime-hardening звонков: файловое логирование больше не делает `flush` на каждую строку, а пишет batched, что снижает pressure на UI isolate во время активных аудио/видеозвонков.
- Для runtime call diagnostics дефолтный файловый log level переведен в `Только ошибки`; подробный trace по-прежнему доступен через Settings, но verbose call-path больше не включен по умолчанию.
- `CallMediaFlowController` разгружен: polling `getStats()` для media-flow/state update замедлен до `1s`, а повторяющийся trace ожидания remote video flow throttled, чтобы активный видеозвонок не создавал лишний log/state churn.
- `CallNegotiationController` получил cooldown на повторные `ICE restart` и `renegotiation`, поэтому recovery path больше не должен разгоняться в плотный restart loop при нестабильной сети или кратких media stalls.
- `CallService` теперь suppress-ит полностью одинаковые `CallState` и не пишет peer-state trace для обновлений, где меняются только счетчики байт, что уменьшает лишние stream events и rebuild pressure на экране звонка.
- `MultiBootstrapSignalingService` перестал писать файловый trace для частых call-media сигналов (`ice`, `call_media_ready`, `call_video_state`, `call_video_state_ack`, `call_video_flow_ack`), чтобы signaling fanout в активном звонке не создавал шумовой I/O hot path.
- Media path в `CallMediaStreamController` и `VideoStreamView` дополнительно разгружен: synthetic remote stream больше не публикуется в UI пустым, no-op track merge не вызывает `onRemoteStream`, а renderer не делает повторный `setSrcObject(...)`, если stream/track фактически не изменились.
- Исправлен call-runtime wiring defect в `AudioCallPeer`: callback wiring на call controllers больше не использует неинициализированные `late` controller references во время конструктора.

### Исправлено

- Focused-тест `call_media_timeout_helper_test.dart` обновлен под текущий `AudioCallPeer` API и снова проходит.

## [3.4.4] - 2026-06-12

### Изменено

- Продолжен hardening call-path: введен явный helper `IncomingCallBootstrapPolicy` для bounded wait на runtime enrichment во время accept, вместо неявного policy внутри `CallService`.
- Введена типизированная модель `CallSessionEpoch`, а владение активной call/runtime epoch в `CallService` и `AudioCallPeer` переведено с raw `int` на явный тип.
- Дальше стандартизовано structured call logging: общий call log context теперь включает `callId`, `peerId`, `epoch`, role, transport mode и media type в `CallService` и `AudioCallPeer`, а peer-level логи дополнительно несут последний наблюдаемый WebRTC signaling state.
- Добавлен явный helper и guard-ы для invariant `one active peer per callId`: чужой media signaling с тем же `callId` больше не может переиспользовать или перепривязать другой активный peer.
- Нормализация push/call payload доведена до одного внутреннего model object `FirebasePushPayload`: UI open path, FCM foreground/open/native-fallback и iOS CallKit path больше не держат отдельные call-payload модели.
- `IosCallkitService` декуплирован от прямой orchestration merge серверов и теперь остается native bridge-слоем с внешним callback seam для обработки push payload/runtime metadata.
- Централизован terminal cleanup peer runtime: отмена `audio stats`/`video flow`/`ICE grace`/`quality upgrade` timers теперь идет через общий `CallPeerSessionController.disposePeerConnection()` path без локального дублирования в `AudioCallPeer`.
- Добавлено smoke-покрытие orchestration-слоя: `CallService` покрыт стабильным control-cycle smoke-тестом, а `MeshSignalRouter` покрыт routing smoke-тестами как выделенный seam вокруг `MeshNode`.
- Добавлены focused-тесты для `IncomingCallBootstrapPolicy`, `CallSessionEpoch`, structured call log context, поведения invariant-helper `one active peer per callId`, media-routing сценария с чужим peer и тем же `callId`, ожидания signaling reconnect, video-upgrade state update и подавления stale timer после dispose peer.

## [3.4.3] - 2026-06-10

### Изменено

- Push-контракт приложения и `push.js` переведен на единый универсальный endpoint `POST /events/push`: клиент теперь отправляет `recipientUserIds`, произвольный `payload`, опциональные `notification` и `delivery`, а сервер работает как transport-only fanout слой без отдельных `/events/message`, `/events/call` и `/events/call-voip`.
- `PushApiClient`, `MeshNode` и `MeshCallPushHelper` обновлены под новый универсальный контракт; call/message/group/account push-пути больше не требуют серверного thin wrapper-а для отдельных типов событий.

## [3.4.2] - 2026-06-09

### Изменено

- Продолжена декомпозиция call-слоя: orchestration connect/timeout/TURN fallback, control-signal routing, media readiness/recovery и state-transition helper-логика вынесены из `CallService` в отдельные helper-модули, а сам `CallService` дополнительно сокращен до orchestration/facade-роли.
- Для снижения риска старого сбоя первого звонка после cold start/update в audio-call bootstrap добавлен одноразовый `audio-only` warm-up перед первым боевым захватом локального media stream; также speaker-route теперь применяется после готовности локального потока.
- Из `MeshNode` вынесен call-push слой в `lib/core/node/mesh_call_push_helper.dart`: регистрация device token-ов и отправка `/events/call` больше не смешаны с signaling/peer-session orchestration.

## [3.4.1] - 2026-06-08

### Изменено

- В Settings добавлен переключаемый уровень файлового логирования приложения: `Только ошибки` или `Подробный`; выбранный режим сохраняется между перезапусками.
- Из hot path UI убран шумный файловый лог `UiApp.build`, поэтому `app.log` в подробном режиме больше не забивается строками о каждом rebuild.
- Для диагностики входящих group-сообщений и восстановления relay-media добавлены подробные логи: этапы group inbound path, попытки скачивания blob и тайминги download/transform/save.
- Foreground push для `message` / `direct_update` / `group_update` теперь тоже запускает `pollRelay()` и merge серверных метаданных, но без принудительного переключения вкладки.
- Исправлен inbound-контекст группового чата: входящее group-сообщение теперь сохраняет реального отправителя отдельно от target чата через `senderPeerId`, поэтому `groupId` больше не путается с peer отправителя.
- Для emoji-only сообщений добавлен отдельный UI-режим: `1-3` эмодзи показываются крупно, без обычной рамки bubble и с легкой анимацией появления.
- Обновлены `README.md` и `README_RU.md`: описаны новый переключатель уровня логов, `pollRelay()` по foreground push и актуальное диагностическое поведение логов.

## [3.4.0] - 2026-06-08

### Изменено

- Из runtime и payload-контрактов приложения удалены legacy peer-id метаданные: `legacyPeerId` / `legacyUserId` больше не экспортируются в identity profile, bootstrap auth proof, invite payload и account-pairing payload, а account-device identity больше не хранит legacy peer id поля.
- Identity/pairing/invite flow и связанные тесты переведены на единую актуальную модель со стабильными `peerId` / `deviceId` без legacy fallback-полей.
- Файловое логирование приложения возвращено с фильтрацией: в runtime-лог теперь попадают только warning/error-диагностика, а шумные info/debug сообщения больше не пишутся в лог-файл.
- Поведение ротации логов сохранено: активный `app.log` по-прежнему ротируется на `1 MB`, архивы по-прежнему создаются как `app_<timestamp>.log`, и хранится только `5` последних архивов.
- Очистка логов в Settings и экран `Хранилище` приведены к одному поведению: действие `Очистить логи` теперь удаляет и текущий лог, и архивы ротации, поэтому размер категории `Логи` на экране `Хранилище` соответствует результату очистки.
- Обновлены `README.md`, `README_RU.md` и пользовательские тексты интерфейса под текущее поведение логов и новое название действия `Очистить логи`.

## [3.3.4] - 2026-06-08

### Изменено

- Исправлено восстановление group/direct событий после cold start и reinstall: runtime теперь дополнительно вызывает `pollRelay()` на startup, `AppLifecycleState.resumed` и при восстановлении сетевой связности, поэтому получение сообщений не зависит только от открытия приложения через push.
- Исправлена маршрутизация входящих relay group envelope: `groupId` больше не теряется по пути `ReliableRelayPollController -> ReliableInboundProcessor -> ChatService`, поэтому group payload публикуется в target группы, а не в peer отправителя.
- Выполнена декомпозиция `lib/core/security/identity_service.dart`: `IdentityService` сокращен до orchestration/facade-слоя, key-store вынесен в `identity_key_store.dart`, membership/update signing — в `identity_membership_crypto.dart`, а storage/keypair/install-id helper-логика — в `identity_storage_support.dart`.
- Выполнена декомпозиция `lib/core/runtime/storage_service.dart`: facade `StorageService` сокращен до orchestration-слоя, а path-resolve, migration flow и media/storage cleanup вынесены в `storage_service_paths.dart`, `storage_service_migrations.dart` и `storage_service_media.dart`.
- Выполнена полная декомпозиция `lib/core/messaging/reliable_messaging_service.dart`: reliable messaging разделен на facade `ReliableMessagingService`, `ReliableInboundProcessor`, `ReliableSessionController`, `ReliableRelayPollController`, `ReliablePendingOperationStore`, `ReliableRetryScheduler` и `ReliableCodec`.
- `ReliableMessagingService` сокращен до orchestration/facade-слоя: poll loop, replay/decode, session/handshake lifecycle, pending persistence/retry и signature/header builders больше не живут в одном файле.
- В `ios/Runner/Info.plist` отключен глобальный ATS-bypass `NSAllowsArbitraryLoads`; ручная проверка на текущем self-hosted стеке подтвердила рабочие подключения к bootstrap/relay/turn серверам по доменным именам и по IP, а также корректную доставку сообщений и звонков без этого флага.
- Добавлена индикация пропущенных звонков в навигации приложения: вкладка `Звонки` теперь показывает бейдж новых входящих пропущенных вызовов и сбрасывает его после открытия экрана звонков.
- Обновлен расчет бейджа иконки приложения: теперь учитывается сумма непрочитанных сообщений и новых пропущенных звонков (`сообщения + пропущенные звонки`), а не только непрочитанные сообщения.
- `Поделиться конфигурацией` теперь отправляет HTTPS-ссылку с payload (в том же стиле, что и приглашение) вместо сырого JSON, а импорт конфигурации из QR/ссылки теперь принимает `peerlink://config?...` и web-ссылки с `payload`, декодирует их и merge-ит `bootstrap/relay/turn/push`.
- Роутинг payload на landing/web странице теперь строго разделен по типу: привязка открывает `peerlink://pair?...`, приглашение — `peerlink://invite?...`, конфигурация — `peerlink://config?...` (без смешивания invite/config).
- Текст шаринга конфигурации серверов теперь отправляется с префиксом: `Конфигурация серверов PeerLink: <ссылка>`.
- На iOS deep-link роутинг теперь явно поддерживает ссылки конфигурации серверов (`peerlink://config` и `https://.../config`), поэтому config payload корректно доходит до Flutter при запуске/открытии приложения.
- QR/manual import конфигурации серверов сохраняет диалог выбора режима (`Объединить` / `Заменить`), а текущие app-side config deep links merge-ятся напрямую.
- Нормализация deep-link входа теперь извлекает URL из текстовых префиксов шаринга (например `Конфигурация серверов PeerLink: https://...`), чтобы payload-ссылка корректно распознавалась.
- Контракт `servers` в push payload расширен полем `push`: клиент теперь отправляет доступные `bootstrap/relay/push/turn` endpoint-ы в `/events/message`, `/events/call` и `/events/call-voip`.
- При приеме push клиент теперь merge-ит и применяет `push_servers` вместе с `bootstrap/relay/turn` (без дублей) через общий runtime слой `ServerHealthCoordinator`.
- Для `accountMembershipUpdate` добавлен push fallback: при revoke/add membership update отправляется `data.type=account_membership_update` в `/events/message`; клиент обрабатывает такой push тихо (без уведомления), сразу применяет update и при ошибке кладет его в pending `account_membership_updates.v1`.
- Для удаления участника из группового чата добавлен аналогичный push fallback: owner/инициатор membership update шлет `data.type=group_members_update` (`groupMembers` payload), а клиент применяет его тихо как обычный `groupMembers` control-update без показа уведомления.
- Выполнена декомпозиция chat state-слоя: storage/read-model, summary/group-meta persistence, file queue, outbound flow, inbound flow, read-state, contacts и group use-cases вынесены в отдельные сервисы (`chat_repository`, `chat_summary_service`, `chat_file_queue_service`, `chat_outbound_service`, `chat_inbound_service`, `chat_read_state_service`, `chat_contacts_service`, `chat_group_service`).
- Group crypto перенесена из `ChatController` в `lib/core/security/group_message_crypto_service.dart`, рядом с `group_key_service.dart`; бинарный `PLG2` pack/unpack и encrypt/decrypt больше не живут в UI/state.
- Исправлено удаление сообщений для unloaded chat: persisted message/summary теперь корректно обновляются даже если чат не загружен в in-memory `chats`.
- Group avatar update сделан безопаснее: локальный `avatarPath` коммитится только после успешной рассылки `groupMembers(action=avatar)`, а staging-файл удаляется при ошибке fan-out.
- `memberPeerIds` теперь канонизируются (`trim + unique + sort`) перед persistence/compare, чтобы одинаковый состав участников не вызывал лишние group-meta записи из-за разного порядка элементов.
- Для iOS добавлен нативный bridge `peerlink/push_payload/methods` (`consumeLatestPushPayload`): если после тапа по пушу `FirebaseMessaging.getInitialMessage()` вернул `null`, Flutter забирает последний payload из `AppDelegate` и все равно применяет `servers`.
- В iOS `AppDelegate` обработчик `didReceiveResponse` прокидывает событие в `super.userNotificationCenter(...)`, чтобы не терять доставку события в Firebase Messaging plugin.
- Регистрация `FirebaseMessaging.onBackgroundMessage(...)` перенесена в ранний этап `main()` до bootstrap приложения.
- Для исходящего аудиозвонка в `AudioCallPeer` убрана привязка локального audio-only `MediaStream` к video `SendOnly` transceiver при bootstrap и добавлена расширенная пошаговая диагностика `startOutgoing` (prepare/createOffer/setLocalDescription/sendOffer) для локализации нативных iOS падений на этапе установки звонка.
- Для iOS CallKit входящего вызова обновление caller теперь синхронно меняет и `localizedCallerName`, и `remoteHandle`: при наличии контакта на экране блокировки показывается имя, иначе остается `PeerID`.
- В runtime звонков добавлен VoIP push-сигнал завершения (`callAction=end`) при отбое исходящего вызова, а iOS-бридж завершает активный CallKit-вызов по `callId`, чтобы у принимающей стороны не зависал экран входящего.
- Локальные уведомления сообщений/звонков теперь подавляются в активном приложении (`AppLifecycleState.resumed`), чтобы убрать дубли поверх открытого чата/экрана звонка.
- В iOS VoIP/CallKit добавлена очередь отложенных bridge-событий (`call_incoming`/`call_action`): если Flutter event stream еще не поднят (приложение в фоне), события не теряются и доставляются при `onListen`, чтобы принятие звонка с системного экрана корректно запускало звонок в PeerLink.
- При ответе на звонок из системного CallKit iOS теперь поднимает приложение через `peerlink://call`, чтобы пользователь переходил в экран звонка PeerLink и WebRTC-сессия быстрее доходила до активного состояния.
- Для VoIP в `push.js` (`/Users/vladimir/peerlink_servers/push.js`) добавлена строгая валидация APNs topic (`*.voip`), поддержка override через `apns.topic` в запросе, явная ошибка `invalid_apns_topic` и расширенная диагностика `/health` (`apnsVoipTopicConfigured`, `apnsUseSandbox`).
- В `push.js` отправка VoIP в APNs переведена с `fetch` на нативный `http2` клиент, чтобы убрать протокольные ошибки (`Expected HTTP/`, `HPE_INVALID_CONSTANT`), а `/events/call` и `/events/call-voip` теперь возвращают `502 push_send_failed`, если все доставки звонка провалились (`sent=0`, `failed>0`).
- В `lib/core/firebase/firebase_messaging_service.dart` увеличено ожидание APNs token для iOS/macOS: количество попыток в `_waitForApnsTokenIfNeeded()` поднято с `10` до `20`.
- FCM теперь инициализируется по умолчанию на всех платформах, включая Android и Windows (убран platform-gate), чтобы токен всегда запрашивался и отправлялся в push runtime.
- Push-серверы переведены на ту же централизованную схему health-check, что и bootstrap/relay/TURN: добавлен runtime-провайдер `PushServersService` с polling `GET /health`, интеграция в `ServerHealthCoordinator` и единые `availability`-стримы/снапшоты.
- Экран `Push servers` теперь показывает реальное состояние доступности endpoint-ов (`доступен/ошибка/ожидание проверки`) вместо статического `настроен`.
- В `SettingsController` управление push-списком перенесено из локальных helper-методов в runtime-координатор, чтобы конфигурация и доступность шли через единый слой.
- На карточке push-серверов в Settings добавлены агрегированные счетчики `доступных/недоступных` по живому health-состоянию.
- Для push-провайдера добавлено runtime-логирование (`[push_service]`): инициализация, add/remove endpoint-ов, refresh и события poller/probe для диагностики доступности.
- Выполнена декомпозиция `SettingsController`: server-status presentation вынесен в `settings_server_status_presenter.dart`, invite encode/parse — в `settings_invite_codec.dart`, а pairing request/approve/reject flow — в `settings_pairing_flow_service.dart` (контроллер переведен на делегирование без изменения пользовательского поведения).
- Формат push endpoint унифицирован с внешним HAProxy: при добавлении в настройках вводится только `domain/IP`, а runtime автоматически нормализует адрес к `https://<host>:445` (вместо `http://<host>:4500`).
- В карточке `Peer ID` на экране `Настройки` теперь отображается текущий `FCM token` (с `SelectableText` для копирования), чтобы быстрее диагностировать push-регистрацию устройства.
- FCM для iOS/macOS теперь включен по умолчанию (`ENABLE_IOS_FCM=true` как default), чтобы токен запрашивался и синхронизировался с push runtime без обязательного `--dart-define`.
- На старте приложения добавлен timeout инициализации FCM (12с): если Firebase Messaging зависает (в т.ч. на macOS), bootstrap продолжает запуск и UI больше не застревает на шаге `Инициализация FCM`.
- В `lib/core/push/push_api_client.dart` зафиксирован whitelist push endpoint-ов клиента: разрешены только `/devices/register`, `/devices/unregister` и `/events/message`; любые другие пути отклоняются на клиенте.
- Bearer-токен для `push.js` теперь берется только из `--dart-define=PUSH_API_TOKEN=...` (без хранения в UI/settings); в `.vscode/launch.json` добавлены шаблоны `toolArgs` с плейсхолдерами `__SET_PUSH_SERVER_URL__` и `__SET_PUSH_API_TOKEN__`.
- Контракт push-событий сообщений расширен до `push-v1.1`: в `/events/message` добавлены подписанные `schemaVersion` и relay-метаданные (`relay.serverId`, `relay.scopeKind`, опционально `relay.blobId`, `relay.relayMessageId`) в клиенте (`PushApiClient`) и `push.js`.
- В `push.js` добавлена backward-compatible проверка подписи для legacy `/events/message` без `schemaVersion`, при этом для `push-v1.1` включена валидация relay-метаданных.
- В fanout `push.js` для group update теперь отправляются одновременно `notification` и `data`, чтобы повысить видимость уведомлений на iOS в фоне.
- В `PushApiClient` подпись событий `/events/message`, `/events/call`, `/events/call-voip` выровнена под текущий контракт `push.js`: в подпись входят поля события и `relay`/`schemaVersion` (для `push-v1.1`), а блок `servers` передается как отдельная payload-метадата и не участвует в `sig`.

### Исправлено

- После декомпозиции reliable messaging сохранено текущее поведение direct/group send path, relay ack, replay protection, handshake retry и persisted retry; `dart analyze` по новым messaging-модулям проходит без замечаний.

## [3.1.1] - 2026-05-03

### Добавлено

- В `Контактах` кнопка `Пригласить` теперь открывает sheet с QR/deep link `peerlink://invite`; открытие ссылки добавляет пригласившего в контакты и merge-ит вложенную конфигурацию доступных серверов.
- Текст приглашения для отправки теперь использует кликабельную HTTPS landing-ссылку, при этом QR/direct-open остаются на `peerlink://invite`; импорт приглашений принимает оба формата.
- Добавлена публичная landing/invite-страница `https://simplegear.org` с переключателем языка всей страницы, ссылками на открытые репозитории, заглушками App Store / Google Play и настоящими web-иконками PeerLink вместо Flutter-дефолтов.
- Строки контактов теперь открывают меню по долгому нажатию с пунктом `Переименовать`, чтобы менять сохраненное отображаемое имя без изменения peer ID.
- В личном чате с незнакомым peer в меню с тремя точками теперь появляется пункт `Добавить контакт`.
- На экране чата после прокрутки вверх появляется плавающая кнопка со стрелкой вниз; нажатие ведет к первому непрочитанному сообщению, если оно есть, иначе возвращает чат вниз.
- Добавлена базовая модель `AccountIdentity`: отдельный `accountId`, `displayName` и список устройств аккаунта `devices`; текущий `peerId/nodeId` сохраняется как device identity без изменения маршрутизации.
- В `Настройки` добавлен блок `Аккаунт и устройства`: можно показать QR/deep link `peerlink://pair` и привязать второе устройство к тому же `accountId`; импорт также merge-ит доступную конфигурацию серверов.
- В привязке второго устройства появился промежуточный шаг подтверждения: после сканирования `peerlink://pair` импорт больше не применяется мгновенно, а сохраняется как pending pairing request до явного подтверждения на принимающем устройстве.
- Привязка второго устройства переведена на flow `scan -> request -> approve`: второе устройство теперь отправляет запрос на уже доверенное устройство аккаунта, а финальный merge `accountId` и server config выполняется только после входящего approval-сообщения.

### Изменено

- Экраны управления Bootstrap, Relay, TURN и деталями хранилища упрощены: технические заголовки серверов остаются едиными, описание показывается обычным текстом, а строки идут компактным прямым списком без дополнительных секций-оберток.
- Из строк категорий хранилища убраны дублирующие красные предупреждения; подробности опасного действия остаются в диалоге подтверждения удаления.
- QR экспорта конфигурации серверов теперь содержит только текущие доступные bootstrap, relay и TURN-серверы; pending/недоступные серверы исключаются, а пустые списки остаются валидными.
- Старт приложения и background relay polling теперь считают пустой список relay-серверов выключенным/пустым состоянием, а не бросают `No message relay servers configured`.
- Ссылки приглашений теперь ведут на `https://simplegear.org/invite`; mobile deep-link routing по-прежнему принимает старый GitHub Pages invite-host для совместимости.
- macOS secure storage теперь использует общие безопасные опции обычного macOS Keychain вместо Data Protection Keychain, а identity/session ключи идут через общий `SecureStorageWrapper` с файловым fallback, чтобы локальные release-сборки без Keychain Sharing не падали с `-34018`.
- Инициализация локальных уведомлений теперь передает `macOS`-настройки плагину `flutter_local_notifications`, чтобы macOS-сборка не падала на старте с `macOS settings must be set`.
- macOS AppIcon asset catalog обновлен из текущей основной иконки PeerLink.
- В macOS entitlements добавлено разрешение исходящей сети `com.apple.security.network.client`, чтобы sandboxed release/debug-сборки могли подключаться к bootstrap, relay и TURN-серверам.
- macOS теперь зеркалирует нужные iOS-разрешения для звонков и медиа: добавлены usage descriptions для камеры/микрофона/локальной сети/контактов/уведомлений, entitlements для microphone/camera/incoming network/user-selected files/address book, а переключатель speakerphone на desktop безопасно игнорируется вместо падения.
- На экране чата добавлен свайп вправо по всей области сообщений, включая текстовые и медиа-bubble, для возврата к списку всех чатов.
- На экранах Bootstrap, Relay, TURN и Хранилище добавлен такой же свайп вправо назад по всей области содержимого.
- Удаление группового чата owner'ом теперь рассылается всем известным участникам и сохраняет локальный tombstone, чтобы старые relay/invite-события не восстановили удаленную группу; удаление не-owner'ом теперь сначала отправляет событие выхода из группы, а затем чистит локальную копию.
- Создание группового чата защищено от быстрых повторных нажатий: sheet блокирует кнопку на время создания, а controller объединяет дублирующие in-flight запросы.

### Исправлено

- Исходящие relay-операции reliable-слоя теперь сохраняются до фактической отправки: direct-сообщения, group-сообщения и group membership update переживают перезапуск приложения и продолжают retry, если отправка оборвалась во время handshake или сетевого сбоя.
- Relay polling теперь различает `все выбранные relay недоступны` и обычный пустой inbox, поэтому во время outage не накапливается ложный idle backoff как при нормальном отсутствии сообщений.
- Relay POST и blob-upload HTTP path теперь используют transient retry/timeout-изоляцию на уровне socket connect/open/close/body-read, поэтому поздние `dart:io` сетевые ошибки деградируют в отказ конкретного relay вместо падения приложения.
- Bootstrap WebSocket `ready` timeout теперь обрабатывается как обычная ошибка подключения с reconnect, без выброса `TimeoutException` из `setServer`; закрытие полуоткрытого socket ограничено по времени, чтобы startup не зависал на мертвом endpoint-е.
- Relay HTTP ошибки connect/header/body-read теперь переводятся во временный отказ конкретного relay вместо всплывающих `dart:io` исключений; quorum-записи используют bounded active relay pool, поэтому один relay может упасть во время записи без срыва отправки, если живых relay достаточно.
- Сервисы доступности bootstrap, relay и TURN переведены на единый polling/backoff engine: Settings и runtime используют один и тот же health snapshot, недоступные серверы уходят в экспоненциальный retry-backoff вместо фиксированного spam-probing, а coordinator refresh больше не срывается полностью, если один provider вернул ошибку.

## [2.9.1] - 2026-04-30

### Добавлено

- В `Настройки` добавлено runtime-переключение языка интерфейса:
  - стартовый набор языков: `EN`, `RU`, `ES`, `ZH`, `FR`,
  - выбранный язык сохраняется локально и применяется сразу,
  - верхняя навигация, Settings, Contacts, Chats, Calls, действия в чате, статусы медиа и экран звонка используют общий слой локализации,
  - тексты локализации хранятся в отдельных словарях по языкам в `lib/ui/localization/dictionaries`.

### Исправлено

- Проверки доступности bootstrap-, relay- и TURN-серверов теперь используют управляемые таймеры вместо socket/client-level timeout helper-ов: долгие проверки помечают endpoint недоступным без всплывающих внутренних `TimeoutException`, а relay/TURN refresh выполняется single-flight.

## [2.8.8] - 2026-04-28

### Изменено

- Интерфейс приложения переведен на новую палитру под текущую иконку:
  - глобальная тема стала темно-синей с яркими сине-циановыми акцентами,
  - обновлены общие поверхности, навигация, диалоги, кнопки, поля ввода и индикаторы прогресса,
  - экран звонка и QR-оверлеи визуально приведены к новой темной системе.
- В Settings добавлено runtime-переключение внешнего вида:
  - пользователь может выбрать `blue`, `black`, `turquoise` или `violet`,
  - выбранная палитра сохраняется локально и применяется сразу,
  - переключение launcher-иконки подключено и для iOS alternate icons, и для Android launcher aliases.
- Экран `Settings` переработан для серверных групп:
  - bootstrap/relay/turn теперь показываются как агрегированные карточки на основном экране,
  - управление каждой группой перенесено на отдельный экран списка,
  - добавление bootstrap/relay/turn выполняется на соответствующих экранах списков,
  - заголовки и описания экранов серверов унифицированы.
- Блок `Хранилище` в Settings переведен на тот же паттерн навигации, что и серверные карточки:
  - отдельная кнопка `Подробнее` удалена,
  - переход выполняется по тапу на всю карточку,
  - справа показывается `chevron`.
- Экран `Контакты` упрощен:
  - удален описательный header-текст,
  - под названием экрана добавлена placeholder-ссылка `Пригласить`,
  - строки контактов теперь показывают только аватар, имя или короткий peer id и время последнего посещения.
- Верхние страницы `Чаты` и `Настройки` упрощены:
  - описательный текст страниц удален,
  - карточки чатов больше не показывают последнее посещение,
  - базовая типографика приложения теперь использует единое семейство шрифта через `AppTheme`.
- Единый компактный ритм карточек применен к `Контактам`, `Чатам` и `Настройкам`:
  - строки контактов/чатов используют меньшие внутренние поля, меньшие аватары и явный небольшой separator,
  - карточки Settings и строки списков серверов используют меньшие внутренние поля, радиусы и зазоры.
- Строки истории звонков стали компактнее и теперь используют общие spacing/radius/separator значения из `CompactCardTileStyles`.

### Исправлено

- Проверка доступности bootstrap-серверов больше не выводит WebSocket probe timeout как падающий `TimeoutException`: endpoint помечается недоступным, а параллельные refresh-запуски пропускаются.
- Контактные аватары больше не должны пропадать после перезапуска приложения:
  - `AvatarService` теперь хранит embedded backup для contact avatars,
  - при старте приложение сначала восстанавливает последний локально сохраненный аватар и только потом делает сетевой avatar sync.
- Улучшена устойчивость входящей загрузки медиа при смене сети:
  - direct blob download теперь использует retry/timeout-защиту,
  - если входящий файл оборвался на переходе `Wi‑Fi -> mobile`, клиент автоматически делает ограниченный delayed retry,
  - визуальное состояние `Ошибка загрузки` больше не выглядит как бесконечная загрузка.
- Предотвращена потеря метаданных входящего relay-медиа при закрытии приложения во время загрузки:
  - relay ack для сообщения теперь ждет, пока `ChatController` надежно сохранит локальное сообщение/placeholder,
  - несохраненные ссылки на медиа остаются в relay и могут быть доставлены повторно после перезапуска.
- Стабилизировано позиционирование прокрутки при открытии чата:
  - первый переход к низу/непрочитанному теперь выполняется single-flight,
  - повторное планирование `initialViewport` / `jumpToBottom` подавляется, пока первый проход ждет layout,
  - стартовый переход к низу несколько кадров подряд догоняет список, чтобы восстановленные медиа не оставляли viewport выше фактического конца чата,
  - переход к первому unread теперь ищет реальные divider/message keys, а не опирается на ratio по индексу рядом с высокими failed media-placeholder,
  - переход по reply к исходному сообщению теперь использует монотонный smooth-scan вместо видимых zig-zag probe-прыжков,
  - входящие обновления в открытом чате автоматически помечаются прочитанными только если пользователь уже был рядом с низом.
- При открытии чата initial history window и стартовая прокрутка больше не останавливаются на старых входящих media-placeholder со статусом `Ошибка загрузки`.
- Relay polling теперь считает `Connection closed before full header was received` временной ошибкой relay и не выпускает HTTP-исключение из fetch path в UI.

## [2.2.1+1] - 2026-04-21

### Изменено

- В core entry layer унифицирован runtime API для messaging/blob операций:
  - `NodeFacade.sendPayload(...)`
  - `NodeFacade.uploadBlob(...)`
  - `NodeFacade.downloadBlob(...)`
- Добавлена ротация файловых логов для mobile runtime:
  - активный `app.log` ограничен размером `1 MB`,
  - переполненный лог ротируется в timestamp-архивы `app_<ts>.log`,
  - хранится только `5` последних архивных лог-файлов,
  - при старте приложения oversized активный лог теперь тоже ротируется сразу.
- Внутренний messaging-слой переработан так, чтобы direct/group доставка использовала общие target-based контракты вместо параллельных пар API в `NodeFacade`, `ChatService` и `ReliableMessagingService`.
- Унифицирован flow восстановления медиа из relay в chat state:
  - общий pipeline скачивания blob и сохранения файла для direct и group media,
  - group-специфичные retry и decrypt шаги стали тонкими адаптерами над общим restore path,
  - декодирование group blob text/avatar теперь использует те же shared helper-ы.
- Терминология runtime приведена к реальной shipped-архитектуре:
  - прием personal media теперь документирован только как `direct_blob_ref` + загрузка blob из relay,
  - удалены устаревшие упоминания legacy direct chunk receive как активного compatibility path,
  - architecture/network/AI-context документы обновлены под unified API layer.
- Логи messaging-сервисов приведены к target-based формату (`target=peer:...` / `target=group:...`), чтобы упростить диагностику.

### Исправлено

- Уменьшено расхождение между direct и group реализациями восстановления медиа за счет удаления дублирующейся restore-логики.
- Усилена очистка локальных медиафайлов:
  - внутренние пути удаления сообщений теперь удаляют managed media до удаления состояния сообщения,
  - входящий delete-for-everyone и cleanup отмененных передач больше не оставляют orphaned media.
- Добавлен circuit breaker для bootstrap endpoint:
  - повторяющиеся `connect failed` теперь открывают cooldown для конкретного endpoint,
  - проблемные bootstrap endpoint перестают бесконечно молотить reconnect в течение окна охлаждения,
  - параллельные `setServer()` для одного и того же endpoint схлопываются, чтобы уменьшить reconnect storm и шум timeout-ошибок, влияющий на UI.

## [Running build hooks...Running build hooks...1.1.5+9] - 2026-04-19

### Изменено

- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- patch: release notes
- 'main' into dev
- patch: release notes
- patch: versions
- patch: versions
- patch: versions in settnigs screen
- patch: versions in settnigs screen
- minor: reply messages
- minor: reply messages

### Исправлено

- correct path
- correct
- fix: dev_commit


## [Running build hooks...Running build hooks...1.1.4+8] - 2026-04-18

### Изменено

- new identity, verify relay
- + group chats
- fix bug chat users, secure send group keys, group key service
- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- patch: release notes
- 'main' into dev
- patch: release notes
- patch: versions
- patch: versions
- patch: versions in settnigs screen
- patch: versions in settnigs screen

### Исправлено

- correct path
- correct
- fix: dev_commit


## [Running build hooks...Running build hooks...1.1.3+7] - 2026-04-18

### Изменено

- stable audi/video calls
- project optimization
- project optimization 2
- new identity, verify relay
- + group chats
- fix bug chat users, secure send group keys, group key service
- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- patch: release notes
- 'main' into dev
- patch: release notes
- patch: versions
- patch: versions

### Исправлено

- correct path
- correct
- fix: dev_commit


## [Running build hooks...Running build hooks...1.1.2+6] - 2026-04-18

### Изменено

- + settings share
- super calls, security signal server
- call from call screen
- stable audi/video calls
- project optimization
- project optimization 2
- new identity, verify relay
- + group chats
- fix bug chat users, secure send group keys, group key service
- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- patch: release notes
- 'main' into dev
- patch: release notes

### Исправлено

- correct path
- correct
- fix: dev_commit


## [Running build hooks...Running build hooks...1.1.1+5] - 2026-04-18

### Изменено

- + voice messages
- fix media bugs
- + Delete-for-everyone
- + base calls )))))) !!!!!!
- + settings share
- super calls, security signal server
- call from call screen
- stable audi/video calls
- project optimization
- project optimization 2
- new identity, verify relay
- + group chats
- fix bug chat users, secure send group keys, group key service
- #6 from tangash/dev
- swipe delete
- lastSeen
- AvatarService
- public peerlink
- #7 from tangash/dev
- - Resolve Docker Hub namespace
- #8 from tangash/dev
- #9 from tangash/dev
- Checkout
- #10 from tangash/dev
- + bootstrap/relay/turn services
- #11 from tangash/dev
- clear server
- + self hosted deploy, many bootstrap
- devops, versions, documents, relay delivery strategy
- Add multi-bootstrap runtime, Replace relay delivery strategy
- 'main' into dev
- dev_commit
- minor: servers runtime health layer
- 'main' into dev
- minor: servers runtime health layer
- навигация по reply в чате теперь определяет исходное сообщение по локальной истории, при необходимости догружает старые страницы и надежнее прокручивает к старым сообщениям

### Исправлено

- correct path
- correct
- fix: dev_commit
- улучшена стабильность перехода к исходному сообщению по тапу на reply, когда оно находится вне текущего viewport


## [Running build hooks...Running build hooks...1.1.0+4] - 2026-04-17

### Добавлено

- TODO

### Изменено

- TODO

### Исправлено

- TODO


## [Running build hooks...Running build hooks...1.1.0+3] - 2026-04-17

### Добавлено

- TODO

### Изменено

- TODO

### Исправлено

- TODO

Формат намеренно простой и ориентирован на релизы.

## [1.0.1+2] - 2026-04-17

Первый релиз, который ведется по формализованной схеме версионирования.

### Добавлено

- Управляемое версионирование приложения через `pubspec.yaml` как единый источник истины.
- Скрипт `tool/bump_version.dart` для `patch`, `minor`, `major`, `build` и `set`.
- История релизов через `CHANGELOG.md` / `CHANGELOG_RU.md`.
- Улучшенная диагностика серверов в Settings для bootstrap, relay и turn: статус доступности и более удобная очистка устаревших записей.

### Изменено

- Базовая версия PeerLink поднята с `1.0.0+1` до `1.0.1+2`.
- Повышена устойчивость bootstrap-подключения: приложение может держать несколько bootstrap-соединений одновременно и надежнее маршрутизировать signaling, если пользователи видны на разных серверах.
- Ускорена доставка сообщений и медиа через relay:
  - runtime предпочитает живые relay и обходит недоступные серверы, если healthy relay уже доступны,
  - активное использование relay ограничено небольшим рабочим набором вместо всего списка конфигурации,
  - пути доставки и загрузки медиа оптимизированы для уменьшения заметных задержек при частично недоступной relay-конфигурации.
