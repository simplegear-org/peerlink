# CHANGELOG

В этом файле фиксируются заметные изменения релизов приложения PeerLink.

## [2.4.1] - 2026-04-22

### Изменено

- Экран `Settings` переработан для серверных групп:
  - bootstrap/relay/turn теперь показываются как агрегированные карточки на основном экране,
  - управление каждой группой перенесено на отдельный экран списка,
  - добавление bootstrap/relay/turn выполняется на соответствующих экранах списков,
  - заголовки и описания экранов серверов унифицированы.
- Блок `Хранилище` в Settings переведен на тот же паттерн навигации, что и серверные карточки:
  - отдельная кнопка `Подробнее` удалена,
  - переход выполняется по тапу на всю карточку,
  - справа показывается `chevron`.

### Исправлено

- Контактные аватары больше не должны пропадать после перезапуска приложения:
  - `AvatarService` теперь хранит embedded backup для contact avatars,
  - при старте приложение сначала восстанавливает последний локально сохраненный аватар и только потом делает сетевой avatar sync.
- Улучшена устойчивость входящей загрузки медиа при смене сети:
  - direct blob download теперь использует retry/timeout-защиту,
  - если входящий файл оборвался на переходе `Wi‑Fi -> mobile`, клиент автоматически делает ограниченный delayed retry,
  - визуальное состояние `Ошибка загрузки` больше не выглядит как бесконечная загрузка.

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
