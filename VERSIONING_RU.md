# VERSIONING

Обновлено: 2026-04-17

## Источник истины

В PeerLink версионирование специально держится простым: единый источник версии приложения — `pubspec.yaml`.

Формат версии:

```yaml
version: x.y.z+n
```

Где:
- `x.y.z` — семантическая версия приложения,
- `n` — монотонно растущий номер сборки.

Flutter уже сам прокидывает эту версию в нативные метаданные:
- Android:
  - `versionName <- x.y.z`
  - `versionCode <- n`
- iOS:
  - `CFBundleShortVersionString <- x.y.z`
  - `CFBundleVersion <- n`

Это значит, что версию не нужно поддерживать вручную отдельно в platform-файлах.

## Правила версионирования

- `patch`: исправления дефектов и безопасные внутренние улучшения
- `minor`: обратносуместимые новые возможности
- `major`: ломающие изменения или намеренно несовместимое поведение
- `build`: пересборка без изменения семантической версии

## Практические правила для PeerLink

По умолчанию лучше опираться на такие критерии:

- `patch`
  - исправления дефектов
  - сетевые и runtime-стабилизационные правки
  - UI-исправления без изменения продуктового поведения
  - внутренние рефакторинги без миграции данных пользователя
- `minor`
  - новые пользовательские возможности
  - новые настройки, экраны, сценарии или protocol-capability без ломания совместимости
  - заметные улучшения runtime, которые ощущаются пользователем, но не требуют миграции
- `major`
  - ломающие миграции storage/данных
  - намеренно несовместимые protocol-изменения
  - удаления или изменения поведения, требующие координированного rollout
- `build`
  - пересборка той же версии приложения
  - только packaging/meta-изменения
  - повторный CI/release без продуктового изменения

## Скрипт bump версии

Запускать из корня проекта:

```bash
dart run tool/bump_version.dart patch
dart run tool/bump_version.dart minor
dart run tool/bump_version.dart major
dart run tool/bump_version.dart build
dart run tool/bump_version.dart set 1.4.0+27
```

Скрипт меняет только строку `version:` в `pubspec.yaml` и выводит итоговую версию.

## Скрипт коммита для dev

Для обычной работы в `dev` использовать:

```bash
tool/dev_commit.sh "fix: короткое описание"
```

Что делает скрипт:
- проверяет, что текущая ветка — `dev`,
- по умолчанию не меняет `pubspec.yaml`, если в commit message нет release-маркера,
- добавляет текущие изменения в индекс,
- создает git commit с переданным сообщением.

Если в commit message есть один из маркеров:

- `[patch]`
- `[minor]`
- `[major]`
- `[build]`

тогда `tool/dev_commit.sh` дополнительно:
- запускает `tool/prepare_release.sh <marker>`,
- обновляет `pubspec.yaml`,
- добавляет новые записи в `CHANGELOG.md` и `CHANGELOG_RU.md`,
- коммитит уже подготовленное versioned-состояние прямо в `dev`.

Примеры:

```bash
tool/dev_commit.sh "[patch] Исправить стабильность jump-to-reply"
tool/dev_commit.sh "[minor] Добавить health dashboard серверов"
```

С этой моделью версионность живет в `dev`, а `main` / `app` просто получают уже подготовленную версию через PR.

Если все же нужен development build bump прямо в `dev`, использовать:

```bash
tool/dev_commit.sh --bump-build "fix: короткое описание"
```

Этот вариант дополнительно поднимет `build` номер перед коммитом.

## Скрипт подготовки релиза

Для обычного релизного сценария использовать:

```bash
tool/prepare_release.sh patch
tool/prepare_release.sh minor
tool/prepare_release.sh major
tool/prepare_release.sh build
```

Этот скрипт берет на себя обычную рутину подготовки релиза:
- поднимает версию в `pubspec.yaml`,
- добавляет новую запись релиза в `CHANGELOG.md`,
- добавляет такую же запись в `CHANGELOG_RU.md`,
- автоматически заполняет обе записи черновиком из git history,
- выводит итоговую версию.

При необходимости можно передать и явную версию:

```bash
tool/prepare_release.sh 1.2.0+15
```

## Рекомендуемый workflow релиза

Короткая практическая памятка по шагам вынесена в:

- `RELEASE_FLOW_RU.md`

1. Выбрать тип релиза: `patch`, `minor`, `major` или `build`.
2. Выполнить `dart run tool/bump_version.dart ...`.
3. Обновить release notes и связанные `md` файлы, если изменилось поведение.
4. Добавить новую запись в `CHANGELOG.md` и `CHANGELOG_RU.md`.
5. Собирать релизные артефакты уже с новой версией.

## Автоматизация через GitHub Actions

Workflow: `.github/workflows/release-version.yml`

Он поддерживает ручной запуск `workflow_dispatch` с параметрами:
- тип релиза: `patch` / `minor` / `major` / `build`
- опциональное создание git tag

Дальше workflow:
- запускает `tool/prepare_release.sh`,
- выполняет `flutter analyze`,
- коммитит обновленные release-метаданные,
- при необходимости создает tag `app-v<version>`.

## Полный автоматический branch-flow

Workflow: `.github/workflows/branch-release.yml`

Триггер:
- push в `main`
- push в `app`

Поведение:
- версия читается напрямую из `pubspec.yaml`
- тип релиза по merge commit message продолжает определяться только для summary/debug-целей
- workflow больше не делает bump версии

Поведение по веткам:
- `main`:
  - использует версию, уже подготовленную в `dev`
  - `flutter analyze`
  - mirror выбранных файлов
- `app`:
  - все то же самое
  - deploy Android в Google Play `internal`
  - загрузка iOS build в TestFlight

## Commit Message релиза

Использование:

```bash
tool/release_commit_message.sh 1.0.2+3 patch
```

Скрипт генерирует стандартизованный заголовок release commit, который использует workflow.

## GitHub Release Notes

Шаблон: `.github/release-template.md`
Готовые файлы: `build/release_notes/release_notes_en.md` и `build/release_notes/release_notes_ru.md`

Рендер:

```bash
tool/render_release_notes.sh 1.0.1+2 --lang en
tool/render_release_notes.sh 1.0.1+2 --lang ru
```

Скрипт выбирает соответствующую пару changelog/template для указанного языка и подставляет тело нужной версии в release template.

Если запись в changelog еще шаблонная (`TODO`) или фактически пустая, скрипт автоматически переключается на черновик из git history и собирает release notes по коммитам с прошлого release commit.

Release workflow также:
- загружает обе языковые версии notes как artifacts,
- добавляет обе языковые версии в summary GitHub Actions job и явно показывает связку `template source -> rendered output`,
- в tag-based release flow прикладывает `build/release_notes/release_notes_ru.md` как GitHub Release asset и добавляет ссылку на него в опубликованное release body,
- использует один и тот же renderer и для tag-based, и для branch-based release flow.

## Workflow сборки приложения

Workflow: `.github/workflows/app-release-build.yml`

Триггер:
- push тега `app-v<version>`

Что делает:
- рендерит GitHub release notes,
- собирает Android APK,
- собирает iOS app через `--no-codesign`,
- загружает артефакты,
- публикует GitHub Release с приложенными файлами.

Нужные repository secrets:
- `ANDROID_GOOGLE_SERVICES_JSON_B64`
- `IOS_GOOGLE_SERVICE_INFO_PLIST_B64`
- Для branch auto-deploy в `app`:
  - `ANDROID_KEYSTORE_B64`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
  - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
  - опционально `ANDROID_APPLICATION_ID`
  - `IOS_CERTIFICATE_P12_B64`
  - `IOS_CERTIFICATE_PASSWORD`
  - `IOS_PROVISIONING_PROFILE_B64`
  - `IOS_EXPORT_OPTIONS_PLIST_B64`
  - `APP_STORE_CONNECT_KEY_ID`
  - `APP_STORE_CONNECT_ISSUER_ID`
  - `APP_STORE_CONNECT_API_KEY_B64`

## Отправная точка

Управляемая версионность начинается с версии, уже зафиксированной в текущем `pubspec.yaml` репозитория.
