# AI_CONTEXT

Обновлено: 2026-04-22

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
- В relay fetch GET path добавлен transient retry/backoff при обрывах соединения.
- Relay-сервер применяет проверку членства на group write endpoint-ах; owner синхронизирует состав через `/relay/group/members/update`.
- Group key ротируется при изменении состава участников (add/remove).
- Relay runtime использует bounded active pool + quorum, а не fan-out во все сконфигурированные relay.
- Relay runtime перед runtime-операциями отбирает только живые relay и использует не более 3 серверов.
- Если в конфигурации есть хотя бы один healthy relay, unhealthy relay не должен оставаться в активном пути доставки текста/медиа.
- Relay control write, fetch и blob fetch выполняются параллельно по выбранным relay, чтобы снижать задержки при частично недоступном списке серверов.
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
- Контактные аватары должны переживать перезапуск приложения за счет локального backup-восстановления до прихода новых avatar announce из сети.
- Incoming media restore должен быть устойчив к кратким network switch: direct blob download использует retry/timeout, а после `Ошибка загрузки` планируется ограниченный авто-retry.
- Проверка доступности остается типоспецифичной внутри сервисов, но в runtime теперь есть общий контракт `ServerAvailabilityProvider` для bootstrap/relay/turn провайдеров.
- `ServerHealthCoordinator` является общей runtime-оркестрацией для этих провайдеров; Settings должен использовать coordinator-backed availability и не создавать дублирующиеся probe loop.
- Runtime-потребители relay и TURN теперь тоже предпочитают coordinator-backed health snapshot, поэтому выбор серверов и экран Settings опираются на одну и ту же общую картину доступности.
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
