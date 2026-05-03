# CHANGELOG

В этом файле фиксируются заметные изменения релизов приложения PeerLink.

## [2.11.1] - 2026-05-03

### Добавлено

- В `Контактах` кнопка `Пригласить` теперь открывает sheet с QR/deep link `peerlink://invite`; открытие ссылки добавляет пригласившего в контакты и merge-ит вложенную конфигурацию доступных серверов.
- Текст приглашения для отправки теперь использует кликабельную HTTPS landing-ссылку, при этом QR/direct-open остаются на `peerlink://invite`; импорт приглашений принимает оба формата.
- Добавлена публичная landing/invite-страница `https://simplegear.org` с переключателем языка всей страницы, ссылками на открытые репозитории, заглушками App Store / Google Play и настоящими web-иконками PeerLink вместо Flutter-дефолтов.
- Строки контактов теперь открывают меню по долгому нажатию с пунктом `Переименовать`, чтобы менять сохраненное отображаемое имя без изменения peer ID.
- В личном чате с незнакомым peer в меню с тремя точками теперь появляется пункт `Добавить контакт`.
- На экране чата после прокрутки вверх появляется плавающая кнопка со стрелкой вниз; нажатие ведет к первому непрочитанному сообщению, если оно есть, иначе возвращает чат вниз.

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
