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

- [Русская версия](README_RU.md)
- [Architecture](docs/public/ARCHITECTURE.md)
- [Архитектура](docs/public/ARCHITECTURE_RU.md)
- [Security policy](docs/public/SECURITY.md)
- [Security model](docs/public/SECURITY_MODEL.md)
- [Network flow](docs/public/NETWORK_FLOW.md)
- [Bootstrap signaling protocol](docs/public/BOOTSTRAP_SIGNALING_PROTOCOL.md)
- [Relay protocol](docs/public/RELAY_PROTOCOL.md)
- [Group blob protocol](docs/public/GROUP_BLOB_V1_SPEC.md)
- [Reliability and delivery resilience](docs/public/RELIABILITY.md)
- [Public mirror policy](docs/public/GITHUB_PUBLIC_MIRROR_SETTINGS.md)
- [Лицензирование](docs/public/LICENSE-HISTORY.md)
- [Сторонние лицензии](docs/public/THIRD_PARTY_NOTICES.md)
- [История изменений](docs/public/CHANGELOG.md)
- [Участие в проекте](docs/public/CONTRIBUTING.md)

Подробная внутренняя техническая документация хранится отдельно и не
публикуется в source mirror.
