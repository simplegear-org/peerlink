# README

Обновлено: 2026-07-21

## Проект

PeerLink — кроссплатформенный Flutter-мессенджер с децентрализованным сетевым ядром.

Текущее состояние сочетает:
- прямой WebRTC-транспорт для peer-сессий overlay,
- WebRTC-звонки через TURN (политика TURN-only),
- relay-доставку сообщений по HTTP (store-and-forward),
- прикладную криптографию для identity/signature/session.

> Этот проект написан исключительно силами ИИ-агентов; я выступаю только в роли координатора и ведущего разработки. Ни один символ кода не написан вручную.

## Текущее состояние

- `flutter analyze` проходит.
- UI экраны Contacts / Chats / Calls / Settings рабочие.
- В UI чатов добавлено специальное отображение emoji-only сообщений:
  - сообщения, состоящие только из `1-3` эмодзи, показываются в крупном формате,
  - для таких сообщений убраны обычные рамка и фон bubble,
  - появление крупных эмодзи сопровождается легкой анимацией.
- Персистентность включена:
  - secure storage для метаданных/настроек,
  - Drift/SQLite для чатов,
  - файловая система для медиа.
  - очистка хранилища удаляет только те категории, которые пользователь выбрал явно; heuristic orphan-media cleanup удален как небезопасный для legacy-путей восстановления медиа.
- Bootstrap signaling по WebSocket используется для transport/call signaling.
- Runtime удерживает несколько bootstrap WebSocket-соединений одновременно.
- Исходящий signaling (`call_invite`, `offer`, `answer`, `ice`) отправляется во все bootstrap-каналы, где виден целевой peer; если peer нигде не виден, используется fallback во все connected bootstrap.
- Call runtime дополнительно разгружен для видеозвонков:
  - файловый лог по умолчанию теперь работает в режиме `Только ошибки`, а запись в `app.log` больше не делает `flush` на каждую строку,
  - шумный trace для частых call-media signaling кадров (`ice`, `call_media_ready`, `call_video_state*`) убран из обычного runtime path,
  - polling `getStats()` для media-flow/state update в звонке идет реже (`1s`),
  - повторные `ICE restart` и `renegotiation` теперь ограничены cooldown-ом, чтобы recovery не входил в плотный цикл при нестабильной сети,
  - remote/local media path suppress-ит пустые и no-op stream/track обновления, а video renderer не rebinding-ит один и тот же stream повторно.
- Включен базовый bootstrap presence: периодические snapshots пиров дают online/offline и локальный `last seen`.
- Личные аватары:
  - локальный аватар задается в `Settings` (тап по кружку рядом с `Peer ID`, выбор камера/галерея, crop в круговой области),
  - аватары отображаются на экранах `Contacts`, `Chats` и в заголовке `Chat`,
  - синхронизация между устройствами: control-сообщение `kind=profileAvatar` + загрузка payload через relay blob (`blobId` в announce),
  - аватары контактов теперь сохраняют резервную локальную копию, поэтому после перезапуска приложения показывается последний известный аватар до прихода нового обновления из сети.
- Аватары групп:
  - обновление аватара owner'ом рассылается как service-событие `groupMembers` (`action=avatar`) со ссылкой на relay blob,
  - обновление не отправляется как обычное chat/media сообщение (старые клиенты не должны показывать это как контент чата),
  - локальный путь `avatarPath` для группы сохраняется в group meta и восстанавливается после перезапуска приложения.
- Контракт bootstrap-сервера для presence:
  - поддерживает `peers_request` и возвращает только реально онлайн `peerId`,
  - добавляет в snapshot серверные данные `lastSeenMs`,
  - отправляет push `presence_update` при переходах `online/offline`.
- Self-hosted деплой из Settings:
  - прогресс деплоя этапный (`1/14 ... 14/14`) с фильтрацией шумных логов,
  - после маркера `Deployment complete!` выполняются проверки доступности сервисов,
  - перед запуском деплоя диалог показывает preview итоговых bootstrap/relay/turn endpoint-ов, которые будут собраны из введенного host,
  - результат проверок показывается явно: `Test connection bootstrap (ok/fail)`, `relay (ok/fail)`, `turn (ok/fail)`,
  - после старта контейнеров post-deploy проверки выполняются с коротким retry-окном, чтобы свежая установка не падала на transient readiness,
  - используется единый host-контракт и для домена, и для IP: `wss://PUBLIC_HOST:443`, `https://PUBLIC_HOST:444`, `turn:PUBLIC_HOST:3478?transport=udp`, `turn:PUBLIC_HOST:3478?transport=tcp`,
  - fallback на legacy endpoint-ы (`/signal`, `:3000`, `:4000`) больше не используется,
  - runtime для bootstrap и relay теперь принимает host-matching self-signed сертификаты для self-hosted endpoint-ов не только по IP, но и по домену,
  - рабочая схема: `wss://PUBLIC_HOST:443` (signal через HAProxy), `https://PUBLIC_HOST:444` (relay через HAProxy), а TURN идет напрямую в `coturn`,
  - рекомендуемые TURN-записи: `turn:PUBLIC_HOST:3478?transport=udp`, `turn:PUBLIC_HOST:3478?transport=tcp`.
- iOS ATS baseline:
  - глобальный bypass `NSAllowsArbitraryLoads` в `ios/Runner/Info.plist` отключен,
  - ручная проверка подтвердила рабочие подключения и обмен сообщениями/звонками с self-hosted серверами как по доменным именам, так и по IP (без включения `NSAllowsArbitraryLoads`).
- В Settings для bootstrap/relay/turn используются агрегированные карточки:
  - на главном экране показывается краткая сводка доступных/недоступных серверов,
  - нажатие открывает отдельный экран списка для каждой группы серверов,
  - добавление bootstrap/relay/turn перенесено на отдельные экраны соответствующих списков,
  - удаление по-прежнему выполняется свайпом влево с подтверждением.
- Ссылки приглашения и конфигурации серверов:
  - invite использует `peerlink://invite?payload=...` для QR/direct-open и `https://simplegear.org/invite?payload=...` для шаринга,
  - шаринг конфигурации серверов использует `https://simplegear.org/config?payload=...`,
  - оба типа ссылок содержат только текущую доступную конфигурацию серверов,
  - app-side deep links merge-ят серверы в существующие настройки; config-ссылки merge-ятся напрямую, а QR/manual import конфигурации сохраняет выбор `Объединить` / `Заменить`.
- Android/macOS native runners передают во Flutter `peerlink://invite|pair|config|call` и поддерживаемые `https://simplegear.org/...` ссылки; macOS хранит pending links при cold start, чтобы переход с сайта в приложение не терял payload.
- В Settings добавлен отдельный экран `Push servers`:
  - поддерживает добавление/удаление push endpoint-ов (`push.js`) для прямой регистрации токенов и group push-событий,
  - при миграции учитывается legacy-значение `push_server_url`, которое переносится в новый список `push_servers`.
- В Settings добавлен раздел `Хранилище`:
  - верхний блок показывает `Total app storage`,
  - переход на экран разбивки теперь выполняется по нажатию на всю карточку со стрелкой вправо, как в секциях серверов,
  - каждая категория поддерживает удаление свайпом влево с подтверждением и встроенным предупреждением о последствиях,
  - категория `Логи` включает текущий `app.log` и архивы ротации,
  - в Settings появился переключатель уровня логирования: `Только ошибки` или `Подробный`,
  - режим `Подробный` предназначен для диагностики и включает детальные trace-логи входящих group-сообщений и тайминги восстановления relay-media,
  - шумный лог `UiApp.build` из hot path удален и больше не засоряет файл на каждом rebuild,
  - действие `Очистить логи` удаляет и текущий лог, и архивы ротации.
- Навигация по reply в чате стала стабильнее:
  - при тапе по reply приложение теперь определяет позицию исходного сообщения по локальной истории,
  - при необходимости догружает более старые страницы, пока исходное сообщение не окажется в памяти,
  - перед прокруткой и подсветкой список надежнее доводится до нужного layout-состояния.
- Relay-доставка теперь предпочитает живые relay:
  - перед runtime-операциями выполняется быстрый health probe,
  - для путей текста и медиа используется только небольшой рабочий набор живых relay (до 3 серверов),
  - если healthy relay доступны, недоступные серверы пропускаются и не должны заметно тормозить доставку.
- Доставка медиа в личных чатах теперь тоже использует relay blob transport:
  - файл один раз загружается в relay blob storage,
  - в чат доставляется зашифрованный `direct_blob_ref`, а не legacy-пара `fileMeta/fileChunk`,
  - прием direct media теперь тоже работает только через `direct_blob_ref` и загрузку blob из relay,
  - direct blob restore использует retry/timeout-защиту при скачивании,
  - если входящий медиафайл оборвался из-за краткой смены сети, клиент автоматически делает ограниченный delayed retry.
- Relay polling и уведомления (push/local) интегрированы.
- FCM token lifecycle интегрирован с выделенным `push.js` сервисом:
  - регистрация/деактивация устройства идет напрямую в `push.js` (`/devices/register`, `/devices/unregister`) с Ed25519-подписью,
  - после успешной runtime-операции клиент best-effort отправляет событие `/events/push` для fanout по устройствам получателей.
  - восстановление group/direct событий не зависит только от открытия приложения через push: runtime дополнительно вызывает `pollRelay()` на startup, при `resume` и при восстановлении сети.
  - приложение само формирует `payload` для `/events/push`; сервер использует только `recipientUserIds`, `notification` и `delivery`, не преобразуя payload,
  - если внутри `payload` присутствует блок `servers`, клиент на приемной стороне merge-ит новые bootstrap/relay/push/turn серверы в локальную конфигурацию (без дублей, только если их еще нет).
  - для iOS добавлен нативный bridge `peerlink/push_payload/methods`: если `getInitialMessage()` вернул `null` после тапа по уведомлению, Flutter забирает последний payload из `AppDelegate` и применяет `servers`.
  - foreground push для `message`/`group_update` теперь тоже запускает `pollRelay()`, но без принудительного перехода на экран чатов.
  - opened push handling может сначала выполнить poll по relay hints из push payload, а затем полный relay poll.
  - входящий relay group envelope сохраняет `groupId` до `ChatService`, поэтому group payload маршрутизируется в чат группы, а не в direct-чат отправителя.
  - входящее group-сообщение теперь отдельно сохраняет реального отправителя в `senderPeerId`, чтобы group target и peer отправителя не смешивались во inbound flow.
  - на уровне клиента разрешены только `POST /devices/register`, `POST /devices/unregister`, `POST /events/push`; другие пути блокируются в `PushApiClient`.
  - сборка push events разделена между `PushEventFactory`, `PushRuntimeMetadataBuilder` и `PushEventService`; `PushApiClient` остается низкоуровневым signed HTTP transport.
  - badge иконки приложения синхронизируется через `AppBadgeService`, который хранит счетчики непрочитанных сообщений и пропущенных звонков.
  - bearer-токен для `push.js` берется только из `--dart-define=PUSH_API_TOKEN=...` (не из UI/settings),
  - для уже собранного приложения изменить `PUSH_API_TOKEN` нельзя: нужен новый билд с новым `--dart-define`.

### Контракт Push API

- Базовый URL задается через `PUSH_SERVER_URL`.
- Авторизация: `Authorization: Bearer <PUSH_API_TOKEN>`.
- Все write-запросы подписываются Ed25519 и содержат поля:
  - `id` (уникальный request id),
  - `from` (идентификатор отправителя),
  - `ts` (unix ms),
  - `sig` (base64 подписи),
  - `signingPub` (base64 публичного signing-ключа).
- Сервер применяет anti-replay по `id` (TTL), поэтому повтор одного `id` отклоняется.

#### ENV для `push.js` (VoIP + FCM)

```env
PORT=4500
PUSH_API_TOKEN=__SET_STRONG_TOKEN__

FCM_PROJECT_ID=__YOUR_FIREBASE_PROJECT_ID__
FCM_CREDENTIALS_JSON=__ONE_LINE_SERVICE_ACCOUNT_JSON__

APNS_TEAM_ID=__APPLE_TEAM_ID__
APNS_KEY_ID=__APPLE_KEY_ID__
APNS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
APNS_VOIP_TOPIC=<bundle_id>.voip
APNS_USE_SANDBOX=true
```

- `APNS_VOIP_TOPIC` должен быть полным topic и оканчиваться на `.voip`.
- Для production/TestFlight сборок ставьте `APNS_USE_SANDBOX=false`.

#### `POST /devices/register`

- Назначение: регистрация (или обновление) push-токена устройства.
- Payload:
  - `id`, `from`, `ts`, `sig`, `signingPub`,
  - `userId`, `deviceId`, `messageToken`, `messageProvider`, `platform`, `appVersion`.
  - `voipToken` опционален для iOS/macOS.
- Ответ: `{ ok: true, device: ... }`.

#### `POST /devices/unregister`

- Назначение: деактивация push-токена устройства.
- Payload:
  - `id`, `from`, `ts`, `sig`, `signingPub`,
  - `userId`, `deviceId`, `token`.
- Ответ: `{ ok: true|false }`.

#### `POST /events/push`

- Назначение: универсальный fanout endpoint для любых push-событий приложения.
- Payload:
  - `id`, `from`, `ts`, `sig`, `signingPub`,
  - `senderUserId`,
  - `recipientUserIds` (`string[]`, обязательное поле маршрутизации),
  - `payload` (`object`, произвольный JSON приложения, сервер пересылает его как есть),
  - `notification` (опционально): `title`, `body`,
  - `delivery` (опционально): `standard`, `voip`.
- Сервер не интерпретирует бизнес-семантику `payload`: не выделяет отдельно `message`/`call`/`group_update`, а использует только `recipientUserIds` для поиска устройств и `delivery` для выбора канала доставки.
- Если приложению нужно передать runtime-метаданные (`servers`, `priority_servers`, `relay`, `accountMembershipUpdate`, `groupMembers` и т.д.), они должны лежать внутри `payload`.
- Ответ: `{ ok, deduped, recipients, devices, sent, failed }`.

#### Рекомендации по FCM payload

- Для надежного UX на iOS рекомендуется отправлять одновременно:
  - `notification.title`,
  - `notification.body`,
  - `payload` (технические поля приложения: `type`, `groupId`, `directPeerId`, `senderUserId`, `relay`, `servers` и т.д.).
- В `background/killed` сообщение отображается как системный `alert`: клиент не может менять его текст перед показом, отображается ровно `notification.title/body`, присланный отправителем и транзитно пересланный сервером.
- Если отправлять только `payload` без текстовых полей, клиентский background handler может не показать локальное уведомление.
- Исключение: для `payload.type=account_membership_update` клиент обрабатывает push тихо (без показа уведомления) и пытается сразу применить update; при ошибке update кладется в pending-очередь `account_membership_updates.v1`.
- Аналогично `payload.type=group_members_update` обрабатывается тихо (без показа уведомления) и сразу применяется как `groupMembers` control-update.

#### Ошибки API

- `401 unauthorized` — bearer-токен не прошел проверку.
- `401 invalid signature` — подпись payload невалидна.
- `401 signature_timestamp_skew` — `ts` вне допустимого окна.
- `409 duplicate request id` — повторный `id` (anti-replay).
- `400 invalid_payload` / `missing ...` — ошибка схемы запроса.
- `502 push_send_failed` — ошибка провайдера push (FCM).
- В core entry layer теперь используется единый messaging/blob API:
  - `NodeFacade.sendPayload(...)` для direct/group доставки,
  - `NodeFacade.uploadBlob(...)` для загрузки blob в direct/group relay scope,
  - `NodeFacade.downloadBlob(...)` для восстановления blob независимо от исходного scope.
- Identity-модель использует стабильный `peerId` (v2). Legacy peer id сохраняется в метаданных для совместимости.
- Для групповых чатов путь доставки текста и медиа унифицирован через relay group flow.
- Для групповых blob включена отправка большими файлами через chunked upload.
- Для group media payload используется компактный бинарный формат шифрования (`PLG2`) с fallback-декодированием legacy-формата.
- Тяжелая криптообработка group media (большие payload) вынесена в background isolate, чтобы не фризить UI.
- Зафиксирована целевая account/device модель:
  - другие пользователи должны идентифицировать человека по `Account ID`, а не по `deviceId` / `peerId`,
  - каждое новое устройство при первом запуске генерирует свой стабильный `deviceId` и свой собственный standalone-аккаунт,
  - pairing не мигрирует аккаунт пользователя, а только переключает устройство из его локального standalone-аккаунта в уже доверенный аккаунт после явного подтверждения,
  - перед подтверждением pairing UI должен предупреждать, что текущий локальный `Account ID` будет заменен целевым аккаунтом,
  - при revoke устройство должно выходить из общего аккаунта и возвращаться к своему исходному standalone-аккаунту, созданному на первом запуске,
  - `deviceId` должен оставаться стабильным при pairing и revoke; меняется только активное членство устройства в аккаунте.

## Что реализовано

- DI-сборка через `NetworkDependencies`.
- Деривация identity:
  - стабильный `peerId` (v2) = hash(signing public key + installation id).
- Пост-инициализация через `AppBootstrapCoordinator`.
- Публичный API ядра через `NodeFacade`.
- Завершена декомпозиция chat-flow UI/логики (`ChatScreen*` и `ChatController*` разнесены по отдельным файлам).
- Для экранов стандартизован шаблон: `*_screen.dart` + `*_view.dart` + `*_styles.dart`.
- Chat UI для одного чата дополнительно разнесен на отдельные screen-модули: `chat_screen_app_bar`, `chat_screen_message_list`, `chat_screen_audio_actions`, `chat_screen_actions`, `chat_screen_scroll_coordinator`, `chat_screen_lifecycle`, `chat_screen_viewport_state`, `chat_screen_presenter`, `chat_screen_back_swipe_coordinator`, `chat_screen_composer_coordinator`.
- Chat UI helper-компоненты вынесены отдельно (`chat_screen_helpers`, `chat_screen_unread_divider`, `chat_screen_media_actions`).
- Переход к исходному сообщению по reply теперь использует локальный поиск позиции сообщения и адресную догрузку истории, что улучшает прыжки к очень старым сообщениям.
- Добавлен `AvatarService` (единый источник аватаров в UI, хранение пути/версии, push/pull синхронизация через relay blob + control announce).
- Добавлен `SelfHostedDeployService` (этапный прогресс, валидация endpoint-ов, пост-проверки bootstrap/relay/turn).
- Добавлен общий контракт `ServerAvailabilityProvider` для сервисов проверки серверов, чтобы probing bootstrap/relay/turn можно было единообразно оркестрировать в runtime.
- Добавлен общий `ServerHealthCoordinator`, который запускает health layer для bootstrap/relay/turn после app bootstrap и отдает в Settings единый runtime-источник данных о доступности серверов.
- `HttpRelayClient` и `TurnAllocator` теперь сначала смотрят на coordinator-backed health snapshot для relay/turn, а при неизвестном общем статусе сохраняют локальный runtime fallback.
- Общий health layer теперь автоматически делает refresh при возврате приложения в foreground и при смене сетевой связности, поэтому bootstrap/relay/turn быстрее восстанавливают актуальный статус после resume или переключения сети.
- Перед критичными relay-операциями клиент теперь адресно обновляет только текущий shortlist relay-серверов, если shared health устарел, а не перепроверяет весь список relay целиком.
- Перед построением TURN-конфига для звонка runtime теперь адресно обновляет только текущий shortlist TURN-серверов, если shared TURN health успел устареть, не перепроверяя весь TURN-список целиком.
- Оркестрация в `MeshNode` (signaling, peer sessions, relay-конфиг).
- Overlay routing + dedup cache.
- HTTP relay клиент использует ограниченный health-aware пул и quorum-стратегию:
  - активное использование relay ограничено,
  - runtime-операции сначала выбирают только живые relay и используют не более 3 серверов,
  - запись и ack идут в quorum,
  - fetch агрегируется по рабочему набору relay с отдельным cursor на каждый сервер,
  - операции по выбранным relay выполняются параллельно, чтобы не накапливать задержки на частично недоступной конфигурации.
- Reliable-envelope пайплайн с валидацией и polling relay.
- Подписи relay валидируются как на клиенте (receive path), так и на сервере (`/relay/store`, `/relay/group/store`, `/relay/group/members/update`, `/relay/ack`, blob upload/finalize).
- Relay выполняет server-side проверку членства группы для group fan-out и group blob upload.
- Изменения состава группы синхронизируются в relay через `/relay/group/members/update`.
- Ротация group key выполняется при изменении состава участников (add/remove).
- Интегрированы relay blob API:
  - `/relay/blob/upload`,
  - `/relay/blob/:blobId`,
  - `/relay/blob/upload/chunk`,
  - `/relay/blob/upload/complete`,
  - `/relay/group/members/update`.
- Для больших blob клиент сначала использует chunked-режим и откатывается на одиночный upload, если chunk endpoint недоступен.
- В fetch path клиента добавлены transient retry/backoff на GET для нестабильных соединений (`Connection closed ...`).
- Media/blob receive path оптимизирован так, чтобы не зависать на последовательном ожидании dead relay, если в конфигурации уже есть хотя бы один живой сервер.
- Стек звонков:
  - `CallService`,
  - `AudioCallPeer`,
  - выделенный `CallNegotiationController`,
  - выделенные `CallVideoController` и `CallVideoState`.
- Call runtime после дополнительного hardening теперь также suppress-ит лишние stats-only state updates, throttled repeated media-flow trace и избегает no-op renderer/stream rebinding в video path.
- Звонки сейчас принудительно идут через TURN для всех типов сети (для стабильности).
- Для self-hosted среды `signal/relay` терминируются на HAProxy, а `TURN/TURNS` обслуживаются напрямую `coturn` без TCP-проксирования через HAProxy.

## Текущие ограничения

- Signaling остается централизованным по контракту bootstrap-сервера, хотя runtime уже удерживает несколько bootstrap WebSocket-каналов одновременно.
- DHT-слой минимальный (`KademliaProtocol` без полноценного lookup workflow).
- Шифрование сообщений подключено, но в runtime сейчас `enableEncryption: false` в `NetworkDependencies` (режим совместимости/отладки).
- Failover `Direct -> TURN -> Relay` для message transport сейчас не активен: текущий `PeerSession` direct-only.
- Модель контактов и доставки пока частично device-centric:
  - часть messaging/call/contact flow все еще резолвит пиров по device-level id,
  - итоговая целевая модель — `Account ID`-first routing, где состав аккаунта внутри runtime резолвится в актуальные активные устройства.

## Технологии

- Flutter / Dart (`^3.11.0`)
- `flutter_webrtc`
- `cryptography`, `crypto`
- `drift`, `sqlite3_flutter_libs`
- `flutter_secure_storage`
- `provider`
- `connectivity_plus`
- `firebase_core`, `firebase_messaging`, `flutter_local_notifications`, `flutter_app_badger`

## Структура

```text
lib/
  main.dart
  core/
    calls/
    dht/
    discovery/
    firebase/
    messaging/
    node/
    notification/
    overlay/
    relay/
    runtime/
    security/
    signaling/
    transport/
    turn/
  ui/
    models/
    screens/
    state/
    theme/
    widgets/
```

- `lib/core/signaling/`:
  - `bootstrap_signaling_service.dart` — фасад bootstrap signaling runtime
  - `bootstrap_signaling_runtime_state.dart` — общий mutable runtime state signaling
  - `bootstrap_signaling_session_controller.dart` — `setServer`/connect/register flow
  - `bootstrap_signaling_connectivity_controller.dart` — watch сетевой связности и fast-reconnect
  - `bootstrap_signaling_reconnect_controller.dart` — retry/backoff/circuit-breaker и reconnect trace
  - `bootstrap_signaling_protocol_controller.dart` — register/signal/ping/peers flow, retry queue, inbound frame handling
  - `bootstrap_signaling_models.dart` — shared signaling value objects
  - `multi_bootstrap_signaling_service.dart` — агрегатор нескольких bootstrap-каналов

## Запуск

```bash
flutter pub get
flutter analyze
flutter run
```

Для push-интеграции токен задается на этапе сборки:

```bash
flutter run \
  --dart-define=PUSH_SERVER_URL=https://your-push-host:4500 \
  --dart-define=PUSH_API_TOKEN=your_secret_token
```

В `.vscode/launch.json` уже добавлены шаблоны `toolArgs` с плейсхолдерами:
- `__SET_PUSH_SERVER_URL__`
- `__SET_PUSH_API_TOKEN__`

## Основные документы

- `RELEASE_FLOW_RU.md`
- `RELEASE_CHECKLIST_RU.md`
- `CHANGELOG_RU.md`
- `VERSIONING_RU.md`
- `ARCHITECTURE_RU.md`
- `NETWORK_FLOW_RU.md`
- `SECURITY_MODEL_RU.md`
- `BOOTSTRAP_SIGNALING_PROTOCOL.md`
- `RELAY_PROTOCOL.md`
- `TASKS_RU.md`
- `AI_CONTEXT_RU.md`

## Версионирование

- Версия приложения ведется только через `pubspec.yaml`.
- Для штатного bump версии использовать `dart run tool/bump_version.dart <patch|minor|major|build>`.
- Для обычных коммитов в `dev` использовать `tool/dev_commit.sh "<сообщение>"`.
- Если в commit message есть `[patch]`, `[minor]`, `[major]` или `[build]`, `tool/dev_commit.sh` поднимает версию локально в `dev`, обновляет `CHANGELOG.md` и `CHANGELOG_RU.md`, а затем коммитит уже подготовленное versioned-состояние вместе с кодом.
- Если все же нужен временный development build bump прямо в `dev` без изменения semantic version, использовать `tool/dev_commit.sh --bump-build "<сообщение>"`.
- Для подготовки релиза целиком использовать `tool/prepare_release.sh <patch|minor|major|build>`: он поднимет версию и добавит заготовки в changelog.
- `tool/prepare_release.sh` теперь не оставляет пустые `TODO`-секции, а сразу заполняет новую changelog-запись автоматическим черновиком из git history.
- Для того же сценария добавлен GitHub Actions workflow `.github/workflows/release-version.yml` с ручным запуском через `workflow_dispatch`.
- После тега `app-v<version>` workflow `.github/workflows/app-release-build.yml` собирает Android/iOS артефакты и публикует GitHub Release.
- Workflow `.github/workflows/branch-release.yml` теперь дает полностью автоматический branch-flow:
  - push в `main` после merge PR: использует уже подготовленную в `dev` версию, рендерит release notes, делает analyze и mirror
  - push в `app` после merge PR: то же самое плюс deploy Android в Google Play Internal и iOS в TestFlight
- `tool/render_release_notes.sh <version> --lang en|ru` теперь умеет собирать и английскую, и русскую версию release notes, сначала берет секцию версии из соответствующего changelog, а если запись еще шаблонная, автоматически строит черновик из git history.
- Release workflow теперь складывает готовые notes в `build/release_notes/`, загружает обе версии как artifacts и добавляет обе в summary GitHub Actions job с явной подсказкой `template source -> rendered output`.
- Tag-based GitHub Release теперь также прикладывает `build/release_notes/release_notes_ru.md` как release asset и показывает прямую ссылку на него в опубликованном release body.
- Подробности описаны в `VERSIONING_RU.md`.
