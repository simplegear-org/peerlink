# AI_CONTEXT

Обновлено: 2026-05-03

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
- Relay-доставка сообщений активна.
- Core entrypoints для runtime messaging/blob операций унифицированы: `sendPayload(...)`, `uploadBlob(...)`, `downloadBlob(...)`.
- Доставка медиа в личных чатах использует relay blob storage и зашифрованный direct blob-reference payload.
- Групповые текст/медиа сообщения идут через relay group path с blob-ссылками на payload.
- Прием личного медиа теперь работает только через зашифрованный `direct_blob_ref` и загрузку blob из relay. Legacy-путь `fileMeta/fileChunk` удален.
- Для крупных payload поддержан chunked upload в relay blob API с fallback на single-shot upload.
- Для encrypted group media используется компактный бинарный формат `PLG2` с fallback-декодированием legacy-формата.
- Тяжелая криптообработка больших group media вынесена в background isolate (без блокировки UI).
- В relay fetch GET path используется transient retry/backoff при обрывах соединения, включая преждевременное закрытие соединения до HTTP-заголовков.
- Relay-сервер применяет проверку членства на group write endpoint-ах; owner синхронизирует состав через `/relay/group/members/update`.
- Group key ротируется при изменении состава участников (add/remove).
- Удаление группового чата у всех доступно только owner'у: owner рассылает service-control (`groupChatDelete`) и сохраняет локальный tombstone группы; не-owner отправляет `groupMembers` leave-событие, выходит из состава и удаляет локальную копию.
- Relay runtime использует bounded active pool + quorum, а не fan-out во все сконфигурированные relay.
- Relay runtime перед runtime-операциями отбирает только живые relay и использует не более 3 серверов.
- Если в конфигурации есть хотя бы один healthy relay, unhealthy relay не должен оставаться в активном пути доставки текста/медиа.
- Пустая relay-конфигурация валидна: startup/background relay polling должен возвращать пустой fetch result или пропускать работу, а не бросать `No message relay servers configured`.
- macOS secure storage должен использовать общие опции `peerLinkMacOSStorageOptions` / `peerLinkSecureStorage` с `usesDataProtectionKeychain: false`; identity/session key-store не должны ходить напрямую в `FlutterSecureStorage`, а должны использовать `SecureStorageWrapper`, потому что Data Protection Keychain/Keychain без entitlement дает `-34018` и fallback/ошибки в локальных release-сборках.
- Инициализация локальных уведомлений на macOS обязана передавать `InitializationSettings.macOS`; без этой ветки `flutter_local_notifications` бросает `macOS settings must be set when targeting macOS platform` на старте приложения.
- macOS sandbox-сборки обязаны иметь `com.apple.security.network.client` в DebugProfile/Release entitlements, иначе исходящие DNS/WebSocket/HTTPS/TURN соединения могут падать как `Failed host lookup` или network permission error.
- macOS sandbox-сборки для звонков/медиа должны иметь usage descriptions в `macos/Runner/Info.plist` для камеры, микрофона, локальной сети, контактов и уведомлений, а также entitlements `device.audio-input`, `device.camera`, `network.server`, `files.user-selected.read-write` и `personal-information.addressbook`.
- `Helper.setSpeakerphoneOn` имеет смысл только на Android/iOS; на desktop/web его нужно считать no-op и не ронять звонок из-за ошибки `enable speakerphone`.
- macOS AppIcon asset catalog должен обновляться из текущей основной иконки `assets/app_icon/icon_1.png`, чтобы desktop-сборка не оставалась со старым изображением.
- Relay control write, fetch и blob fetch выполняются параллельно по выбранным relay, чтобы снижать задержки при частично недоступном списке серверов.
- Если blob fetch получает только `404` от текущего shortlist живых relay, runtime расширяет чтение на остальные сконфигурированные relay перед тем, как считать blob отсутствующим.
- Runtime encryption для reliable-сообщений сейчас включен конфигом (`enableEncryption: true`).
- Звонки сейчас идут только через TURN для всех типов сети.
- В Settings доступен self-hosted деплой с этапным прогрессом (`1/14 ... 14/14`) и post-проверками сервисов.
- Для self-hosted endpoint-ов используются фиксированные адреса `wss://<ip>:443` для bootstrap и `https://<ip>:444` для relay без fallback на legacy endpoint-ы.
- Runtime принимает self-signed сертификаты для bootstrap/relay TLS endpoint-ов на IP-хостах.
- В self-hosted схеме HAProxy используется только для `signal`/`relay`; TURN/TURNS не должен проксироваться через HAProxy и обслуживается напрямую `coturn`.
- Self-hosted TURN-конфиг должен принимать как `turn:`, так и `turns:` URL.
- В Settings списки bootstrap/relay/turn показывают доступность серверов, сортируют строки по состоянию и используют swipe-to-delete с подтверждением.
- На главном экране Settings bootstrap/relay/turn представлены агрегированными карточками; добавление новых серверов выполняется на отдельных list-screen экранах этих групп.
- Блок `Хранилище` в Settings открывается по тапу на всю карточку со стрелкой вправо, без отдельной кнопки `Подробнее`.
- Верхние страницы Contacts/Chats/Settings используют компактный layout с AppBar без описательных header-текстов, плотными расстояниями между карточками и сдержанными внутренними полями.
- Строки контактов, чатов и истории звонков используют общие compact card константы через `CompactCardTileStyles`; screen-specific style-файлы должны хранить только действительно специфичные значения.
- Invite QR/direct-open из Contacts использует `peerlink://invite?payload=...`, а текст для отправки использует кликабельный HTTPS landing URL (`https://simplegear.org/invite?payload=...` по умолчанию). Оба формата содержат Peer ID приглашающего и текущую доступную конфигурацию серверов, а импорт должен merge-ить серверы без замены существующих настроек; старые GitHub Pages invite-ссылки продолжают приниматься для совместимости.
- Публичные static HTML/CSS/JS страницы `web/` для landing/invite используют реальные иконки PeerLink из `assets/app_icon/icon_1.png`, а видимый текст локализуется через переключатель языка в `web/site.js` для EN/RU/ES/ZH/FR.
- Строки контактов показывают аватар, один display label (имя контакта или короткий peer id) и last-seen; имя и peer id не должны дублироваться в одной строке.
- Строки контактов открывают action menu по долгому нажатию для переименования сохраненного display name; peer ID при этом не меняется.
- Overflow menu в app-bar личного чата показывает `Добавить контакт` только если peer еще не сохранен в контактах.
- Строки чатов показывают только аватар, название чата, последнее сообщение и badge непрочитанных; last-seen в карточках списка чатов намеренно не отображается.
- Строки истории звонков должны оставаться компактными: используем плотный отступ между строками и не держим завышенные внутренние поля вокруг текста.
- Типографика приложения централизована в `AppTheme.fontFamily`; top-level text styles, AppBar, NavigationBar, dialogs, snackbars и inputs должны использовать одно семейство шрифта.
- Язык интерфейса переключается в runtime из Settings через `AppLocaleController`; сейчас поддержаны EN/RU/ES/ZH/FR, а новые UI-строки должны идти через `AppStrings` и словари по языкам, без новых hardcoded display text.
- Контактные аватары должны переживать перезапуск приложения за счет локального backup-восстановления до прихода новых avatar announce из сети.
- Incoming media restore должен быть устойчив к кратким network switch: direct blob download использует retry/timeout, а после `Ошибка загрузки` планируется ограниченный авто-retry.
- Relay media transfer и incoming relay-media retry state/timers живут в `RelayMediaTransferService` / `RelayMediaRetryCoordinator`; `ChatController` должен координировать только состояние сообщений, очереди и UI-уведомления.
- Incoming relay-media restore использует persisted bounded retry state, поэтому прерванные placeholder могут автоматически возобновляться при открытии чата, resume приложения или восстановлении connectivity.
- Incoming media auto-retry должен останавливаться после подтвержденного relay `blob not found`; повторное открытие чата не должно запускать бесконечный restore loop для того же placeholder.
- Если приложение повторно открывает чат с незавершенным incoming relay-media placeholder, stale in-progress статусы должны нормализоваться из бесконечного `Получение из relay`, а затем возобновляться только через persisted bounded retry path.
- Ручной tap по incoming relay-media placeholder, пока restore уже активен, не должен запускать вторую загрузку blob для того же сообщения; UI сообщает, что медиа еще загружается.
- Incoming relay-media progress должен быть монотонным; parallel relay-candidate callbacks не должны откатывать видимый progress/status назад.
- Поздние progress callbacks от старого incoming relay-media restore не должны перезаписывать terminal `Ошибка загрузки` или завершенное local-file состояние.
- Ручной tap по incoming relay-media placeholder не должен падать на `blob not found`; сообщение остается в статусе `Ошибка загрузки`.
- Relay blob `404 not found` в обычных media receive/open flow должен возвращаться как non-throwing missing-blob result, чтобы UI мог перейти в `Ошибка загрузки` без runtime exception.
- Relay ack для chat-сообщений должен ждать durable-обработки: `ChatController` обязан сохранить сообщение/placeholder до подтверждения relay envelope.
- Стартовый viewport при открытии чата выполняется single-flight: UI не должен планировать повторные initial-scroll прыжки, пока первый проход позиционирования к низу/непрочитанному еще ожидает layout; режим bottom несколько кадров подряд догоняет актуальный низ списка, чтобы поздний layout медиа не оставлял viewport выше конца чата.
- Стартовый переход к unread должен находить реальный context divider/message через probe ленивого списка; нельзя полагаться только на ratio по индексу, потому что failed media-placeholder имеют нестабильную/большую высоту.
- Переход по reply к исходному сообщению не должен делать видимые zig-zag probe: программный jump использует монотонный smooth-scan к цели и подавляет lazy-load триггеры на время scan.
- Уже открытый чат должен помечать входящие обновления прочитанными только если пользователь был рядом с низом; если пользователь ушел выше по истории, unread-состояние сохраняется для последующего прыжка к первому непрочитанному.
- Входящие media-placeholder со статусом `Ошибка загрузки` не должны использоваться как якорь initial history window или стартовый unread-якорь прокрутки при открытии чата.
- В пузырях видеофайлов чат показывает paused preview-кадр из локально доступного видео; темный play-placeholder остается fallback-ом, если файл недоступен или инициализация preview не удалась.
- Проверка доступности остается типоспецифичной внутри сервисов, но в runtime теперь есть общий контракт `ServerAvailabilityProvider` для bootstrap/relay/turn провайдеров.
- `ServerHealthCoordinator` является общей runtime-оркестрацией для этих провайдеров; Settings должен использовать coordinator-backed availability и не создавать дублирующиеся probe loop.
- Runtime-потребители relay и TURN теперь тоже предпочитают coordinator-backed health snapshot, поэтому выбор серверов и экран Settings опираются на одну и ту же общую картину доступности.
- Bootstrap availability probe должен считать WebSocket connect timeout обычным health-результатом `unavailable`, а не пробрасывать `TimeoutException`; одновременно выполняется только один bootstrap refresh.
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
5. Обновлять документацию в том же изменении, если меняется поведение.
6. Добавлять/обновлять тесты для критических networking/security flow.
7. Считать `pubspec.yaml` единым источником версии приложения; не вести Android/iOS версии вручную отдельно.

## 5. Нефункциональный baseline

- Не допускать silent crash-loop при нестабильной сети.
- Не допускать утечек timers/stream subscriptions.
- Не допускать silent crypto downgrade в production path.

## 6. При неопределенности

- Предпочитать минимальные безопасные изменения.
- Проверять допущения по коду до обновления документации.
- При конфликте docs vs code источником истины считать code и обновлять docs.
