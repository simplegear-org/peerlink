# TASKS

Обновлено: 2026-04-22

## Ключи статусов

- `done`
- `in_progress`
- `todo`
- `blocked`

## 1. Завершено

- [done] Зафиксирована политика версионирования приложения: единый источник версии `pubspec.yaml`, scripted bump flow через `tool/bump_version.dart`.
- [done] Добавлена автоматизация подготовки релиза: локальный `tool/prepare_release.sh` и GitHub Actions workflow `.github/workflows/release-version.yml`.
- [done] Релизный tooling расширен: автогенерация release commit message, шаблонные GitHub release notes и tag-based workflow сборки Android/iOS.
- [done] Добавлена branch-driven автоматизация: `main` делает auto-release prepare+mirror, `app` делает auto-release prepare+mobile deploy.
- [done] Добавлен локальный сценарий `tool/dev_commit.sh` для коммитов в ветке `dev` без изменения `pubspec.yaml` по умолчанию; опциональный `--bump-build` оставлен для явных development build bump.
- [done] Добавлен общий контракт `ServerAvailabilityProvider` как базовая абстракция для bootstrap/relay/turn health-провайдеров.
- [done] Добавлен общий `ServerHealthCoordinator`, чтобы runtime startup и Settings использовали одни и те же bootstrap/relay/turn health-сервисы и общее состояние доступности.
- [done] `HttpRelayClient` и `TurnAllocator` подключены к общим coordinator-backed health snapshot для relay/turn с сохранением локального runtime fallback, если shared health еще неизвестен.
- [done] Добавлен общий refresh health-состояния при возврате приложения в foreground и при смене сетевой связности, чтобы bootstrap/relay/turn заранее обновляли доступность в runtime.
- [done] Добавлен адресный refresh relay shortlist перед критичными send/blob/fetch операциями, если shared relay health snapshot устарел.
- [done] Добавлен адресный refresh TURN shortlist перед построением TURN-конфига звонка, если shared TURN health snapshot устарел.
- [done] Автогенерация release notes теперь сначала берет секцию нужной версии из changelog и автоматически переключается на черновик из git history, если запись в changelog еще шаблонная.
- [done] Автогенерация release notes теперь поддерживает и английскую, и русскую версию как в скриптах, так и в workflow.
- [done] Tag-based GitHub Release теперь прикладывает русские release notes как release asset и показывает прямую ссылку на них в опубликованном release body.
- [done] `prepare_release.sh` теперь автоматически заполняет новые changelog-записи черновиком из git history вместо пустых `TODO`-секций.
- [done] DI/runtime сборка через `NetworkDependencies`.
- [done] Интеграция UI через `NodeFacade`.
- [done] Relay-based reliable messaging pipeline (`store/fetch/ack`).
- [done] Персистентное хранение (secure metadata + chat DB + media filesystem).
- [done] Рефакторинг call stack: выделены `CallNegotiationController`, `CallVideoController`, `CallVideoState`.
- [done] TURN-only политика аудио/видео звонков для всех типов сети.
- [done] Декомпозиция chat-flow в UI/state слое (`ChatScreen*`, `ChatController*` разделены).
- [done] Для экранов стандартизована структура `*_screen.dart` + `*_view.dart` + `*_styles.dart`.
- [done] Chat helper-модули вынесены отдельно (`chat_screen_helpers`, `chat_screen_unread_divider`, `chat_screen_media_actions`).
- [done] Групповые текст/медиа сообщения унифицированы через relay group flow с blob-ссылками на payload.
- [done] Добавлен chunked upload для relay blob API с fallback на single-upload endpoint.
- [done] Добавлена server-side проверка членства для relay group write-path.
- [done] Интегрирован endpoint синхронизации состава (`/relay/group/members/update`).
- [done] Реализована ротация group key при изменении состава (add/remove).
- [done] Crypto payload group media переведен на компактный бинарный формат `PLG2` с fallback-декодированием legacy-формата.
- [done] Тяжелая криптообработка больших group media вынесена в background isolate (без фризов UI).
- [done] Добавлен transient retry/backoff для relay fetch GET при нестабильной сети.
- [done] Базовый bootstrap presence: периодические snapshots пиров, переходы online/offline и локальный `last seen`.
- [done] В Settings реализован self-hosted деплой серверов с этапным прогрессом (`1/14 ... 14/14`) и post-проверками bootstrap/relay/turn.
- [done] Self-hosted endpoint-ы зафиксированы на `wss://<ip>:443` и `https://<ip>:444` без legacy fallback на `/signal` / `:3000` / `:4000`.
- [done] В runtime добавлена поддержка self-signed TLS сертификатов для bootstrap/relay endpoint-ов на IP-хостах.
- [done] Для self-hosted схемы зафиксировано разделение: HAProxy только для `signal/relay`, а TURN/TURNS идет напрямую в `coturn`.
- [done] Нормализация TURN URL в runtime принимает и `turn:`, и `turns:`.
- [done] Runtime bootstrap удерживает несколько WebSocket-подключений одновременно.
- [done] Исходящий call/WebRTC signaling отправляется во все bootstrap-каналы, где виден целевой peer, с fallback во все connected bootstrap.
- [done] Relay runtime использует bounded active pool + quorum вместо fan-out во весь список серверов.
- [done] Relay runtime теперь предварительно отбирает только живые relay, ограничивает runtime-использование 3 серверами и выполняет control/blob операции параллельно, чтобы уменьшить задержки текста и медиа при частично недоступном списке relay.
- [done] В Settings серверные группы переведены на агрегированные карточки с отдельными list-screen экранами для bootstrap/relay/turn.
- [done] Блок `Хранилище` в Settings переведен на навигацию по тапу на всю карточку со стрелкой вправо.
- [done] Контактные аватары теперь сохраняют локальный backup и восстанавливаются после перезапуска до прихода нового сетевого avatar announce.
- [done] Для входящих media restore добавлены retry/timeout для direct blob download и ограниченный автоматический retry после transient network failure.

## 2. В работе

- [in_progress] Стабилизация старта звонка и media-flow в мобильных сетях.
- [in_progress] Декомпозиция крупных core-файлов.

## 3. P0 (Критично)

- [todo] Включить и валидировать encrypted messaging в runtime (`enableEncryption: true`) без регрессий совместимости.
- [todo] Добавить интеграционные тесты relay messaging (success/retry/ack/failure).
- [todo] Добавить интеграционные тесты call setup/reconnect после смены сети.

## 4. P1 (Сетевое ядро)

- [todo] Зафиксировать стратегию message transport sessions (`direct-only` или `direct+fallback`).
- [todo] Если нужен fallback: реализовать и протестировать `Direct -> TURN -> Relay` в `PeerSession` для message transport.
- [todo] Расширить DHT от каркаса до рабочих lookup/rpc workflows.
- [todo] Снизить зависимость от централизованного bootstrap signaling сверх текущего многоканального runtime.

## 5. P1 (Безопасность)

- [todo] Расширить replay protection на control/signaling envelope там, где это применимо.
- [todo] Расширить текущую group-key rotation до полноценной ratcheting/session-key стратегии.
- [todo] Добавить negative security tests (invalid signature, replay, tampering).

## 6. P2 (UX/Product)

- [todo] Расширить presence UX (privacy controls / richer status) поверх базового online/last-seen.
- [todo] UX для delivery/read receipts.
- [done] В settings показывается доступность bootstrap/relay/turn, строки отсортированы по состоянию, удаление выполняется свайпом с подтверждением.

## 7. Качество

- [todo] End-to-end smoke tests: startup/connect/disconnect/background poll.
- [todo] Regression checks на очистку timers/subscriptions/resources.
