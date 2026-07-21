# AI_CONTEXT

Обновлено: 2026-07-21

Файл задает рабочие рамки для AI-assisted разработки в PeerLink.

## 1. Цель проекта

Собрать production-grade децентрализованный мессенджер без потери текущей рабочей функциональности.

## 2. Правило истины

Всегда разделять:
- AS-IS (что реально делает код),
- NEXT (что запланировано).

Нельзя описывать план как уже внедренное решение.

## 3. Текущая runtime-реальность

- Bootstrap signaling централизован и обязателен.
- Runtime bootstrap многоканальный: одновременно удерживается несколько WebSocket-подключений к разным bootstrap.
- Исходящий signaling должен идти во все bootstrap-каналы, где виден целевой peer; fallback — во все connected bootstrap.
- В Settings bootstrap-статусы должны отражать две разные плоскости состояния: `подключен` означает, что runtime реально держит signaling channel к этому bootstrap, `доступен` означает успешный health probe без текущего signaling channel, `недоступен` означает failed health probe.
- Relay-доставка сообщений активна.
- Core entrypoints для runtime messaging/blob операций унифицированы: `sendPayload(...)`, `uploadBlob(...)`, `downloadBlob(...)`.
- Доставка медиа в личных чатах использует relay blob storage и зашифрованный direct blob-reference payload.
- Групповые текст/медиа сообщения идут через relay group path с blob-ссылками на payload.
- Прием личного медиа теперь работает только через зашифрованный `direct_blob_ref` и загрузку blob из relay. Legacy-путь `fileMeta/fileChunk` удален.
- Для крупных payload поддержан chunked upload в relay blob API с fallback на single-shot upload.
- Для encrypted group media используется компактный бинарный формат `PLG2` с fallback-декодированием legacy-формата.
- Тяжелая криптообработка больших group media вынесена в background isolate (без блокировки UI).
- Реализация group crypto живет в `lib/core/security/group_message_crypto_service.dart` рядом с `GroupKeyService`; в `ChatController` допускается только делегирование, без собственной криптографической логики.
- `IdentityService` должен оставаться facade-слоем над identity lifecycle; key-store bridge нужно держать в `identity_key_store.dart`, storage/keypair/install-id helper-логику — в `identity_storage_support.dart`, а membership/update signing payload-ы — в `identity_membership_crypto.dart`.
- В relay fetch GET path используется transient retry/backoff при обрывах соединения, включая преждевременное закрытие соединения до HTTP-заголовков.
- POST/control/blob upload path в relay использует ту же transient retry/timeout-изоляцию, что и GET, поэтому поздние socket connect/open/close/body-read ошибки должны деградировать в отказ конкретного relay, а не ронять приложение.
- Relay HTTP ошибки connect/header/body-read должны оставаться временным отказом конкретного relay; raw `dart:io` HTTP exceptions не должны всплывать в UI/startup path.
- Relay-сервер применяет проверку членства на group write endpoint-ах; owner синхронизирует состав через `/relay/group/members/update`.
- Group key ротируется при изменении состава участников (add/remove).
- Удаление группового чата у всех доступно только owner'у: owner рассылает service-control (`groupChatDelete`) и сохраняет локальный tombstone группы; не-owner отправляет `groupMembers` leave-событие, выходит из состава и удаляет локальную копию.
- Relay runtime использует bounded active pool + quorum, а не fan-out во все сконфигурированные relay.
- Relay write должен отправляться в bounded active pool, а не только в quorum-количество серверов, чтобы отказ одного ранее healthy relay во время записи мог быть перекрыт другим активным relay.
- Relay runtime перед runtime-операциями отбирает только живые relay и использует не более 3 серверов.
- Если в конфигурации есть хотя бы один healthy relay, unhealthy relay не должен оставаться в активном пути доставки текста/медиа.
- Пустая relay-конфигурация валидна: startup/background relay polling должен возвращать пустой fetch result или пропускать работу, а не бросать `No message relay servers configured`.
- macOS secure storage должен использовать общие опции `peerLinkMacOSStorageOptions` / `peerLinkSecureStorage` с `usesDataProtectionKeychain: false`; identity/session key-store не должны ходить напрямую в `FlutterSecureStorage`, а должны использовать `SecureStorageWrapper`, потому что Data Protection Keychain/Keychain без entitlement дает `-34018` и fallback/ошибки в локальных release-сборках.
- Инициализация локальных уведомлений на macOS обязана передавать `InitializationSettings.macOS`; без этой ветки `flutter_local_notifications` бросает `macOS settings must be set when targeting macOS platform` на старте приложения.
- Клиент FCM при старте и `onTokenRefresh` должен синхронизировать токен в двух контурах: обновлять identity (`fcmTokenHash` для bootstrap register) и best-effort регистрировать raw токен в `push.js` через подписанные `/devices/register` и `/devices/unregister` (Ed25519, anti-replay `id/ts`).
- FCM-модуль в `lib/core/firebase` должен оставаться декомпозированным: `FirebaseMessagingService` — только coordinator/external API, `FirebasePushTokenLifecycle` — token lifecycle, `FirebasePushInboundService` — inbound orchestration, `FirebasePushPayloadProcessor` — обработка push payload/server config/account/group updates, `FirebasePushPresentationHandler` — foreground/open/native-fallback presentation. Возвращать эти ответственности обратно в один монолитный сервис нельзя.
- Для push/call payload path должен использоваться единый `FirebasePushPayload`; не возвращать отдельные ad-hoc call-payload DTO для UI open path, FCM fallback и iOS CallKit.
- Формирование push fanout вынесено из низкоуровневого HTTP: payload/signature сборка живет в `PushEventFactory`, runtime-метаданные серверов — в `PushRuntimeMetadataBuilder`, orchestration отправки — в `PushEventService`.
- Состоянием бейджа иконки владеет `AppBadgeService`: он хранит unread/missed-call счетчики и синхронизирует platform badge вместо прямых вызовов notification plugin из UI.
- `IosCallkitService` должен оставаться native bridge-слоем с внешним callback seam, а не владельцем merge/payload orchestration.
- После успешной отправки group text/media сообщение должно best-effort публиковать подписанное push-событие в `push.js` через `/events/message`, чтобы сервис разослал `group_update` получателям.
- Push payload для `/events/message` и `/events/call` должен включать опциональный блок `servers` с полными endpoint-ами доступных bootstrap/relay/push/turn серверов.
- В текущем `push.js` поле `servers` не участвует в строке подписи push payload; подпись для `push-v1.1` включает `schemaVersion` и `relay`.
- Клиент при получении push должен читать `data.servers` и merge-ить недостающие bootstrap/relay/push/turn серверы в локальную конфигурацию без удаления существующих.
- Для iOS нужно учитывать кейс, когда после тапа по пушу `FirebaseMessaging.getInitialMessage()` возвращает `null`: нативный `AppDelegate` сохраняет последний payload в памяти, а Flutter читает его через method channel `peerlink/push_payload/methods` (`consumeLatestPushPayload`) и применяет тот же merge `servers`.
- `group_update` push ускоряет восстановление, но не является обязательным триггером: клиент должен запускать `pollRelay()` и при обычном startup, и при `AppLifecycleState.resumed`, и при восстановлении сетевой связности.
- Входящий relay group envelope обязан сохранить `groupId` до `ChatService`; при наличии `groupId` входящее сообщение маршрутизируется в target группы, а не в direct target отправителя.
- macOS sandbox-сборки обязаны иметь `com.apple.security.network.client` в DebugProfile/Release entitlements, иначе исходящие DNS/WebSocket/HTTPS/TURN соединения могут падать как `Failed host lookup` или network permission error.
- macOS sandbox-сборки для звонков/медиа должны иметь usage descriptions в `macos/Runner/Info.plist` для камеры, микрофона, локальной сети, контактов и уведомлений, а также entitlements `device.audio-input`, `device.camera`, `network.server`, `files.user-selected.read-write` и `personal-information.addressbook`.
- `Helper.setSpeakerphoneOn` имеет смысл только на Android/iOS; на desktop/web его нужно считать no-op и не ронять звонок из-за ошибки `enable speakerphone`.
- macOS AppIcon asset catalog должен обновляться из текущей основной иконки `assets/app_icon/icon_1.png`, чтобы desktop-сборка не оставалась со старым изображением.
- Relay control write, fetch и blob fetch выполняются параллельно по выбранным relay, чтобы снижать задержки при частично недоступном списке серверов.
- Если blob fetch получает только `404` от текущего shortlist живых relay, runtime расширяет чтение на остальные сконфигурированные relay перед тем, как считать blob отсутствующим.
- Runtime encryption для reliable-сообщений сейчас включен конфигом (`enableEncryption: true`).
- Multi-device identity находится на переходе от этапа 2 к этапу 3: `AccountIdentity` хранит `accountId`, `displayName` и `devices`, Settings умеет экспортировать `peerlink://pair`, а новое устройство теперь только отправляет pairing request; финальный merge `accountId` и server config выполняется после approval от уже доверенного устройства аккаунта. Текущий `peerId/nodeId` пока остается runtime device id для маршрутизации, bootstrap, relay и crypto session.
- Звонки сейчас идут только через TURN для всех типов сети.
- Для call runtime default файловый log level должен оставаться `errorsOnly`; verbose-call trace допустим только как явный диагностический режим, а hot call path не должен делать synchronous-per-line file flush.
- Частые call-media signaling кадры (`ice`, `call_media_ready`, `call_video_state`, `call_video_state_ack`, `call_video_flow_ack`) не должны создавать шумный обычный runtime file trace.
- Recovery path звонка не должен разгонять плотный цикл `ICE restart` / `renegotiation`; повторные recovery-attempt-ы должны быть bounded cooldown-ами и state guards.
- Call-state updates, в которых меняются только счетчики байт, не должны считаться полноценными state-transition событиями для UI/log path.
- Synthetic remote call stream нельзя публиковать в UI пустым до появления реального media track, а повторное присоединение того же remote track не должно триггерить новый `onRemoteStream`.
- Video renderer на экране звонка не должен делать повторный `setSrcObject(...)`, если `MediaStream` и выбранный video track фактически не изменились.
- В Settings доступен self-hosted деплой с этапным прогрессом (`1/14 ... 14/14`) и post-проверками сервисов.
- Для self-hosted endpoint-ов используются фиксированные адреса `wss://<ip>:443` для bootstrap и `https://<ip>:444` для relay без fallback на legacy endpoint-ы.
- Runtime принимает self-signed сертификаты для bootstrap/relay TLS endpoint-ов на IP-хостах.
- В self-hosted схеме HAProxy используется только для `signal`/`relay`; TURN/TURNS не должен проксироваться через HAProxy и обслуживается напрямую `coturn`.
- Self-hosted TURN-конфиг должен принимать как `turn:`, так и `turns:` URL.
- В Settings списки bootstrap/relay/turn показывают доступность серверов, сортируют строки по состоянию и используют swipe-to-delete с подтверждением.
- В Settings добавлен отдельный список `Push servers`: экран позволяет добавлять/удалять push endpoint-ы (ввод домена/IP без протокола, runtime сам нормализует в `http://<host>:4500`); runtime выбирает первый валидный endpoint из списка для `/devices/register|unregister` и `/events/message`.
- `SettingsController` не должен расширяться логикой presentation/codec/flow: server status formatting держать в `settings_server_status_presenter.dart`, invite encode/parse — в `settings_invite_codec.dart`, pairing request/approve/reject flow — в `settings_pairing_flow_service.dart`.
- На главном экране Settings bootstrap/relay/turn представлены агрегированными карточками; добавление новых серверов выполняется на отдельных list-screen экранах этих групп.
- `SettingsScreen` не должен обратно превращаться в god-object: orchestration/lifecycle остаются в `settings_screen.dart`, composition/layout-секции живут в `settings_screen_content.dart`, `settings_screen_identity_section.dart`, `settings_screen_account_devices_section.dart`, `settings_screen_server_sections.dart`, `settings_screen_preferences_sections.dart`, barrel `settings_screen_account_sections.dart` используется только как re-export, общие UI-блоки переиспользуются через `settings_screen_shared_widgets.dart` и `settings_screen_account_widgets.dart`, а avatar/pairing/import-export/self-hosted/reset flow должны расширяться в соответствующих `settings_screen_*_actions.dart`.
- Блок `Хранилище` в Settings открывается по тапу на всю карточку со стрелкой вправо, без отдельной кнопки `Подробнее`.
- Верхние страницы Contacts/Chats/Settings используют компактный layout с AppBar без описательных header-текстов, плотными расстояниями между карточками и сдержанными внутренними полями.
- Строки контактов, чатов и истории звонков используют общие compact card константы через `CompactCardTileStyles`; screen-specific style-файлы должны хранить только действительно специфичные значения.
- Invite QR/direct-open из Contacts использует `peerlink://invite?payload=...`, а текст для отправки использует кликабельный HTTPS landing URL (`https://simplegear.org/invite?payload=...` по умолчанию). Оба формата содержат Peer ID приглашающего и текущую доступную конфигурацию серверов, а импорт должен merge-ить серверы без замены существующих настроек; self-invite должен сначала merge-ить вложенную конфигурацию серверов и только потом пропускать создание контакта.
- `Поделиться конфигурацией` использует `https://simplegear.org/config?payload=...` только с текущей доступной конфигурацией серверов. Web-routing открывает `peerlink://config?...`, а app-side config deep link напрямую merge-ит `bootstrap/relay/turn/push` без QR-диалога выбора режима импорта.
- Android и macOS native runners обязаны передавать в Flutter через `DeepLinkService` ссылки `peerlink://invite`, `peerlink://pair`, `peerlink://config`, `peerlink://call`, а также поддерживаемые `https://simplegear.org/...` / legacy GitHub Pages ссылки; на macOS канал конфигурируется из `MainFlutterWindow`, а URL handler-ы регистрируются рано, чтобы не терять cold-start link.
- Публичные static HTML/CSS/JS страницы `web/` для landing/invite используют реальные иконки PeerLink из `assets/app_icon/icon_1.png`, а видимый текст локализуется через переключатель языка в `web/site.js` для EN/RU/ES/ZH/FR.
- Строки контактов показывают аватар, один display label (имя контакта или короткий peer id) и last-seen; имя и peer id не должны дублироваться в одной строке.
- Строки контактов открывают action menu по долгому нажатию для переименования сохраненного display name; peer ID при этом не меняется.
- Overflow menu в app-bar личного чата показывает `Добавить контакт` только если peer еще не сохранен в контактах.
- Строки чатов показывают только аватар, название чата, последнее сообщение и badge непрочитанных; last-seen в карточках списка чатов намеренно не отображается.
- Строки истории звонков должны оставаться компактными: используем плотный отступ между строками и не держим завышенные внутренние поля вокруг текста.
- Типографика приложения централизована в `AppTheme.fontFamily`; top-level text styles, AppBar, NavigationBar, dialogs, snackbars и inputs должны использовать одно семейство шрифта.
- Язык интерфейса переключается в runtime из Settings через `AppLocaleController`; сейчас поддержаны EN/RU/ES/ZH/FR, а новые UI-строки должны идти через `AppStrings` и словари по языкам, без новых hardcoded display text.
- Контактные аватары должны переживать перезапуск приложения за счет локального backup-восстановления до прихода новых avatar announce из сети.
- `AvatarService` живет в `lib/core/runtime`; UI не должен возвращать avatar storage/blob/broadcast логику обратно в `ui/state`.
- Incoming media restore должен быть устойчив к кратким network switch: direct blob download использует retry/timeout, а после `Ошибка загрузки` планируется ограниченный авто-retry.
- Relay media transfer и incoming relay-media retry state/timers живут в `RelayMediaTransferService` / `RelayMediaRetryCoordinator`; `ChatController` должен координировать только состояние сообщений, очереди и UI-уведомления.
- `RelayMediaTransferService` / `RelayMediaRetryCoordinator` живут в `lib/core/relay`, а не в `ui/state`; UI/state слой должен только вызывать их и координировать presentation state.
- Inbound parsing/classification для `ChatController` должен жить в отдельном сервисе `ChatInboundClassifier`; decode-функции передаются через явные зависимости.
- Outbound encode/decode payload и transfer-id helper-логика для `ChatController` должна жить в отдельном сервисе `ChatOutboundCodec`, а не в теле контроллера.
- Для декомпозиции chat-state использовать доменные сервисы `ChatRepository`, `ChatSummaryService`, `ChatFileQueueService`, `ChatOutboundService`, `ChatInboundService`, `ChatReadStateService`, `ChatContactsService`, `ChatGroupService`; не возвращать storage/contacts/group/read-state логику обратно в `ChatController`.
- При удалении сообщения из unloaded chat изменение должно доходить до persisted storage/summary, а не зависеть от присутствия чата в in-memory `chats`.
- `memberPeerIds` должны канонизироваться (`trim + unique + sort`) перед persistence/compare, иначе порядок списка даст ложные group-meta обновления.
- Локальный путь group avatar нельзя считать committed до успешного broadcast membership update; на ошибке fan-out staging avatar должен откатываться.
- Incoming relay-media restore использует persisted bounded retry state, поэтому прерванные placeholder могут автоматически возобновляться при открытии чата, resume приложения или восстановлении connectivity.
- Incoming media auto-retry должен останавливаться после подтвержденного relay `blob not found`; повторное открытие чата не должно запускать бесконечный restore loop для того же placeholder.
- Если приложение повторно открывает чат с незавершенным incoming relay-media placeholder, stale in-progress статусы должны нормализоваться из бесконечного `Получение из relay`, а затем возобновляться только через persisted bounded retry path.
- Ручной tap по incoming relay-media placeholder, пока restore уже активен, не должен запускать вторую загрузку blob для того же сообщения; UI сообщает, что медиа еще загружается.
- Incoming relay-media progress должен быть монотонным; parallel relay-candidate callbacks не должны откатывать видимый progress/status назад.
- Поздние progress callbacks от старого incoming relay-media restore не должны перезаписывать terminal `Ошибка загрузки` или завершенное local-file состояние.
- Ручной tap по incoming relay-media placeholder не должен падать на `blob not found`; сообщение остается в статусе `Ошибка загрузки`.
- Relay blob `404 not found` в обычных media receive/open flow должен возвращаться как non-throwing missing-blob result, чтобы UI мог перейти в `Ошибка загрузки` без runtime exception.
- Relay ack для chat-сообщений должен ждать durable-обработки: `ChatController` обязан сохранить сообщение/placeholder до подтверждения relay envelope.
- Исходящие relay-операции reliable-слоя теперь должны сохраняться до фактической отправки: direct payload, group payload и group membership update обязаны переживать перезапуск приложения и продолжать retry из runtime state, а не только из in-memory timer-ов.
- Relay polling должен различать состояния `нет сообщений` и `все выбранные relay недоступны`; outage relay не должен увеличивать обычный empty-poll backoff так, будто inbox просто пустой.
- Стартовый viewport при открытии чата выполняется single-flight: UI не должен планировать повторные initial-scroll прыжки, пока первый проход позиционирования к низу/непрочитанному еще ожидает layout; режим bottom несколько кадров подряд догоняет актуальный низ списка, чтобы поздний layout медиа не оставлял viewport выше конца чата.
- Стартовый переход к unread должен находить реальный context divider/message через probe ленивого списка; нельзя полагаться только на ratio по индексу, потому что failed media-placeholder имеют нестабильную/большую высоту.
- Переход по reply к исходному сообщению не должен делать видимые zig-zag probe: программный jump использует монотонный smooth-scan к цели и подавляет lazy-load триггеры на время scan.
- Уже открытый чат должен помечать входящие обновления прочитанными только если пользователь был рядом с низом; если пользователь ушел выше по истории, unread-состояние сохраняется для последующего прыжка к первому непрочитанному.
- Входящие media-placeholder со статусом `Ошибка загрузки` не должны использоваться как якорь initial history window или стартовый unread-якорь прокрутки при открытии чата.
- В пузырях видеофайлов чат показывает paused preview-кадр из локально доступного видео; темный play-placeholder остается fallback-ом, если файл недоступен или инициализация preview не удалась.
- Проверка доступности остается типоспецифичной внутри сервисов, но в runtime теперь есть общий контракт `ServerAvailabilityProvider` для bootstrap/relay/turn провайдеров.
- `ServerHealthCoordinator` является общей runtime-оркестрацией для этих провайдеров; Settings должен использовать coordinator-backed availability и не создавать дублирующиеся probe loop.
- Сервисы доступности bootstrap/relay/turn теперь используют общий polling/backoff engine, поэтому недоступные серверы уходят в экспоненциальный retry-backoff вместо постоянного fixed-interval probing.
- Shared availability refresh для bootstrap/relay/turn должен выполнять due-probes параллельно, а не последовательно, чтобы startup/foreground refresh не деградировал линейно от числа недоступных серверов.
- Runtime-потребители relay и TURN теперь тоже предпочитают coordinator-backed health snapshot, поэтому выбор серверов и экран Settings опираются на одну и ту же общую картину доступности.
- Bootstrap availability probe должен считать WebSocket connect timeout обычным health-результатом `unavailable`, а не пробрасывать `TimeoutException`; одновременно выполняется только один bootstrap refresh.
- Bootstrap runtime `setServer` должен считать WebSocket `ready` timeout обычной ошибкой подключения с reconnect, а не пробрасывать `TimeoutException`; teardown полуоткрытого channel должен иметь bounded close timeout.
- Shared health coordinator также делает refresh при возврате приложения в foreground и при смене сетевой связности, поэтому runtime-состояние серверов не остается устаревшим после resume или переключения сети.
- Relay runtime теперь перед критичными send/blob/fetch операциями адресно обновляет shared health только для текущего relay shortlist, если общий relay snapshot успел устареть.
- TURN runtime теперь тоже перед сборкой TURN-based `rtcConfig` адресно обновляет shared health только для текущего TURN shortlist, чтобы call setup использовал более свежих TURN-кандидатов.
- DHT присутствует, но остается минимальным.

## 4. Правила изменений

При изменении кода:
1. Сохранять границу UI через `NodeFacade`.
2. Сохранять сборку зависимостей внутри runtime wiring (`NetworkDependencies`).
3. Сохранять корректный lifecycle (timers/subscriptions/dispose).
4. Дробить крупную call-логику через controller/state extraction.
4.1. Для `lib/core/calls` сначала расширять существующие `Call*Controller`, а не возвращать ответственность в `AudioCallPeer`.
5. Обновлять документацию в том же изменении, если меняется поведение.
6. Добавлять/обновлять тесты для критических networking/security flow.
7. Считать `pubspec.yaml` единым источником версии приложения; не вести Android/iOS версии вручную отдельно.
8. Не допускать бесконечного роста файлов: если файл уже крупный (ориентир: `~800+` строк для UI/state и `~500+` для runtime-сервисов), новые функции добавлять только через декомпозицию по доменам (отдельные классы/сервисы/controller/helper через `import` с четкой ответственностью).
9. Перед добавлением новой фичи в крупный файл сначала фиксировать архитектурное решение: куда именно пойдет логика, как будет тестироваться и почему нельзя вынести в отдельный модуль.
10. Если файл уже стал «god-object», приоритетом следующего изменения должна быть декомпозиция; прямое наращивание такого файла без попытки выделить bounded-компонент считается нарушением архитектурного baseline.
11. При декомпозиции не использовать `part` как конечную архитектуру: `part` допускается только как временный шаг миграции в рамках одного PR/серии PR.
12. Целевое состояние декомпозиции: отдельные файлы и классы-сервисы/controller-модули через `import`, явные зависимости через конструктор/callback wiring, отсутствие скрытого доступа к состоянию файла-родителя.
13. Перед созданием нового сервиса сначала проверять уже существующие сервисы в этом bounded context; не допускать дублей по ответственности и пересекающихся сервисных слоев.
14. Если подходящий сервис уже существует, но покрывает не весь нужный сценарий, расширять существующий сервис, а не создавать новый дублирующий.
15. При рефакторинге и переносе существующих сервисов размещать их в целевых директориях проекта по фактической ответственности (`core`, `runtime`, `relay`, `security`, `ui/state` и т.д.), а не сохранять старое размещение по инерции.
16. При создании нового сервиса или выделении логики из крупного файла сначала проверять, можно ли оптимально расширить или переиспользовать уже существующий сервис в целевой директории без введения нового дублирующего слоя.

## 5. Нефункциональный baseline

- Не допускать silent crash-loop при нестабильной сети.
- Не допускать утечек timers/stream subscriptions.
- Не допускать silent crypto downgrade в production path.

## 6. При неопределенности

- Предпочитать минимальные безопасные изменения.
- Проверять допущения по коду до обновления документации.
- При конфликте docs vs code источником истины считать code и обновлять docs.
