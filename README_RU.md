# PeerLink X

Кроссплатформенный Flutter-мессенджер с децентрализованным сетевым ядром,
WebRTC-звонками и relay-доставкой сообщений.

## Быстрый старт

```bash
flutter pub get
flutter analyze
flutter run
```

Для push-сборок локально нужны Firebase-конфигурация и `PUSH_API_TOKEN` через
`--dart-define`; секреты в репозиторий не добавляются.

## Документы

- [English version](README.md)
- [Архитектура](docs/public/ARCHITECTURE_RU.md)
- [Architecture](docs/public/ARCHITECTURE.md)
- [Политика безопасности](docs/public/SECURITY.md)
- [Модель безопасности](docs/public/SECURITY_MODEL_RU.md)
- [Сетевые потоки](docs/public/NETWORK_FLOW_RU.md)
- [Протокол bootstrap signaling](docs/public/BOOTSTRAP_SIGNALING_PROTOCOL_RU.md)
- [Протокол relay](docs/public/RELAY_PROTOCOL_RU.md)
- [Протокол group blob](docs/public/GROUP_BLOB_V1_SPEC_RU.md)
- [Отказоустойчивость доставки](docs/public/RELIABILITY.md)
- [Политика public mirror](docs/public/GITHUB_PUBLIC_MIRROR_SETTINGS.md)
- [Лицензирование](docs/public/LICENSE-HISTORY.md)
- [Сторонние лицензии](docs/public/THIRD_PARTY_NOTICES.md)
- [История изменений](docs/public/CHANGELOG_RU.md)
- [Участие в проекте](docs/public/CONTRIBUTING.md)

Подробная внутренняя техническая документация хранится отдельно и не
публикуется в source mirror.
