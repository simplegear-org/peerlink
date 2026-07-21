# CHANGELOG

В этом файле фиксируются заметные изменения релизов приложения PeerLink.

## [3.6.0] - 2026-07-21

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
- Обновлены `README_RU.md`, `ARCHITECTURE_RU.md` и `NETWORK_FLOW_RU.md`: зафиксирован transport-only подход `push.js` и новый контракт `/events/push`.

## [3.4.2] - 2026-06-09

### Изменено

- Продолжена декомпозиция call-слоя: orchestration connect/timeout/TURN fallback, control-signal routing, media readiness/recovery и state-transition helper-логика вынесены из `CallService` в отдельные helper-модули, а сам `CallService` дополнительно сокращен до orchestration/facade-роли.
- Для снижения риска старого сбоя первого звонка после cold start/update в audio-call bootstrap добавлен одноразовый `audio-only` warm-up перед первым боевым захватом локального media stream; также speaker-route теперь применяется после готовности локального потока.
- Из `MeshNode` вынесен call-push слой в `lib/core/node/mesh_call_push_helper.dart`: регистрация device token-ов и отправка `/events/call` больше не смешаны с signaling/peer-session orchestration.
- Обновлены `ARCHITECTURE_RU.md` и `BACKLOG_RU.md`: зафиксированы новая граница `MeshCallPushHelper` и текущий статус декомпозиции `mesh_node` / call-runtime слоя.

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
- Обновлены `ARCHITECTURE*.md`, `PROJECT_STRUCTURE_RU.md` и `AI_CONTEXT*.md`: зафиксирована фактическая модульная структура identity/security слоя и правило не возвращать storage/signature helper-ответственности обратно в `IdentityService`.
- Выполнена декомпозиция `lib/core/runtime/storage_service.dart`: facade `StorageService` сокращен до orchestration-слоя, а path-resolve, migration flow и media/storage cleanup вынесены в `storage_service_paths.dart`, `storage_service_migrations.dart` и `storage_service_media.dart`.
- Выполнена полная декомпозиция `lib/core/messaging/reliable_messaging_service.dart`: reliable messaging разделен на facade `ReliableMessagingService`, `ReliableInboundProcessor`, `ReliableSessionController`, `ReliableRelayPollController`, `ReliablePendingOperationStore`, `ReliableRetryScheduler` и `ReliableCodec`.
- `ReliableMessagingService` сокращен до orchestration/facade-слоя: poll loop, replay/decode, session/handshake lifecycle, pending persistence/retry и signature/header builders больше не живут в одном файле.
- Обновлены `ARCHITECTURE_RU.md` и `PROJECT_STRUCTURE_RU.md`: зафиксирована фактическая модульная структура reliable messaging и роли новых подмодулей.
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
- В `README_RU.md` добавлена явная документация VoIP push-контракта: `/devices/register-voip`, `/devices/unregister-voip`, `/events/call-voip`, обязательные APNs headers и готовый `.env` шаблон для `push.js`.
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
- Терминология runtime и документации приведена к реальной shipped-архитектуре:
  - прием personal media теперь документирован только как `direct_blob_ref` + загрузка blob из relay,
  - удалены устаревшие упоминания legacy direct chunk receive как активного compatibility path,
  - architecture/network/AI-context документы обновлены под unified API layer.
- Логи messaging-сервисов приведены к target-based формату (`target=peer:...` / `target=group:...`), чтобы упростить диагностику.

### Исправлено

- Уменьшено расхождение между direct и group реализациями восстановления медиа за счет удаления дублирующейся restore-логики.
- Удалены устаревшие ссылки в документации на deprecated поведение direct media receive.
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
- Документы `VERSIONING.md` и `VERSIONING_RU.md`.
- История релизов через `CHANGELOG.md` / `CHANGELOG_RU.md`.
- Улучшенная диагностика серверов в Settings для bootstrap, relay и turn: статус доступности и более удобная очистка устаревших записей.

### Изменено

- Документация проекта теперь явно описывает правила версионирования и bump релизов.
- Базовая версия PeerLink поднята с `1.0.0+1` до `1.0.1+2`.
- Повышена устойчивость bootstrap-подключения: приложение может держать несколько bootstrap-соединений одновременно и надежнее маршрутизировать signaling, если пользователи видны на разных серверах.
- Ускорена доставка сообщений и медиа через relay:
  - runtime предпочитает живые relay и обходит недоступные серверы, если healthy relay уже доступны,
  - активное использование relay ограничено небольшим рабочим набором вместо всего списка конфигурации,
  - пути доставки и загрузки медиа оптимизированы для уменьшения заметных задержек при частично недоступной relay-конфигурации.
