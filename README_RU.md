# README

Обновлено: 2026-04-22

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
- Персистентность включена:
  - secure storage для метаданных/настроек,
  - Drift/SQLite для чатов,
  - файловая система для медиа.
  - очистка хранилища удаляет только те категории, которые пользователь выбрал явно; heuristic orphan-media cleanup удален как небезопасный для legacy-путей восстановления медиа.
- Bootstrap signaling по WebSocket используется для transport/call signaling.
- Runtime удерживает несколько bootstrap WebSocket-соединений одновременно.
- Исходящий signaling (`call_invite`, `offer`, `answer`, `ice`) отправляется во все bootstrap-каналы, где виден целевой peer; если peer нигде не виден, используется fallback во все connected bootstrap.
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
  - результат проверок показывается явно: `Test connection bootstrap (ok/fail)`, `relay (ok/fail)`, `turn (ok/fail)`,
  - после деплоя используются фиксированные TLS endpoint-ы: `wss://<ip>:443` для bootstrap и `https://<ip>:444` для relay,
  - fallback на legacy endpoint-ы (`/signal`, `:3000`, `:4000`) больше не используется,
  - конфигурация TURN поддерживает смешанный формат URL (`turn:` и `turns:`),
  - рабочая схема: `wss://<ip>:443` (signal через HAProxy), `https://<ip>:444` (relay через HAProxy), а TURN/TURNS идет напрямую в `coturn`,
  - рекомендуемые TURN-записи: `turns:<ip>:5349?transport=tcp`, `turn:<ip>:3478?transport=udp`, `turn:<ip>:3478?transport=tcp`.
- В Settings для bootstrap/relay/turn используются агрегированные карточки:
  - на главном экране показывается краткая сводка доступных/недоступных серверов,
  - нажатие открывает отдельный экран списка для каждой группы серверов,
  - добавление bootstrap/relay/turn перенесено на отдельные экраны соответствующих списков,
  - удаление по-прежнему выполняется свайпом влево с подтверждением.
- В Settings добавлен раздел `Хранилище`:
  - верхний блок показывает `Total app storage`,
  - переход на экран разбивки теперь выполняется по нажатию на всю карточку со стрелкой вправо, как в секциях серверов,
  - каждая категория поддерживает удаление свайпом влево с подтверждением и встроенным предупреждением о последствиях.
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
- В core entry layer теперь используется единый messaging/blob API:
  - `NodeFacade.sendPayload(...)` для direct/group доставки,
  - `NodeFacade.uploadBlob(...)` для загрузки blob в direct/group relay scope,
  - `NodeFacade.downloadBlob(...)` для восстановления blob независимо от исходного scope.
- Identity-модель использует стабильный `peerId` (v2). Legacy peer id сохраняется в метаданных для совместимости.
- Для групповых чатов путь доставки текста и медиа унифицирован через relay group flow.
- Для групповых blob включена отправка большими файлами через chunked upload.
- Для group media payload используется компактный бинарный формат шифрования (`PLG2`) с fallback-декодированием legacy-формата.
- Тяжелая криптообработка group media (большие payload) вынесена в background isolate, чтобы не фризить UI.

## Что реализовано

- DI-сборка через `NetworkDependencies`.
- Деривация identity:
  - стабильный `peerId` (v2) = hash(signing public key + installation id),
  - `legacyPeerId` = прежний формат hash(signing public key).
- Пост-инициализация через `AppBootstrapCoordinator`.
- Публичный API ядра через `NodeFacade`.
- Завершена декомпозиция chat-flow UI/логики (`ChatScreen*` и `ChatController*` разнесены по отдельным файлам).
- Для экранов стандартизован шаблон: `*_screen.dart` + `*_view.dart` + `*_styles.dart`.
- Chat UI helper-компоненты вынесены отдельно (`chat_screen_helpers`, `chat_screen_unread_divider`).
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
- Звонки сейчас принудительно идут через TURN для всех типов сети (для стабильности).
- Для self-hosted среды `signal/relay` терминируются на HAProxy, а `TURN/TURNS` обслуживаются напрямую `coturn` без TCP-проксирования через HAProxy.

## Текущие ограничения

- Signaling остается централизованным по контракту bootstrap-сервера, хотя runtime уже удерживает несколько bootstrap WebSocket-каналов одновременно.
- DHT-слой минимальный (`KademliaProtocol` без полноценного lookup workflow).
- Шифрование сообщений подключено, но в runtime сейчас `enableEncryption: false` в `NetworkDependencies` (режим совместимости/отладки).
- Failover `Direct -> TURN -> Relay` для message transport сейчас не активен: текущий `PeerSession` direct-only.

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

## Запуск

```bash
flutter pub get
flutter analyze
flutter run
```

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
