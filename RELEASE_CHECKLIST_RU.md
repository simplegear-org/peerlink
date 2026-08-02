# RELEASE CHECKLIST

Обновлено: 2026-07-31

Этот чек-лист нужен для того, чтобы релизы PeerLink проходили спокойно и предсказуемо, без пропуска очевидных шагов.

Для короткой пошаговой схемы без деталей см.:

- `RELEASE_FLOW_RU.md`

## 1. Версия

- [ ] Выбрать тип релиза: `patch`, `minor`, `major` или `build`
- [ ] Поднять версию в `pubspec.yaml` через:
  - `dart run tool/bump_version.dart patch`
  - `dart run tool/bump_version.dart minor`
  - `dart run tool/bump_version.dart major`
  - `dart run tool/bump_version.dart build`
- [ ] Или выполнить `tool/prepare_release.sh <patch|minor|major|build>`, чтобы сразу поднять версию и создать заготовку changelog
- [ ] Проверить, что итоговая строка версии корректна
- [ ] Для iOS после изменения `pubspec.yaml` выполнить `flutter build ios --config-only --no-codesign` или полноценную iOS-сборку, чтобы `ios/Flutter/Generated.xcconfig` получил актуальные `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER`

## 2. Release Notes

- [ ] Добавить новую запись в `CHANGELOG.md`
- [ ] Добавить такую же запись в `CHANGELOG_RU.md`
- [ ] Проверить и дочистить автоматический черновик changelog, собранный из git history
- [ ] Кратко и честно описать пользовательские изменения релиза
- [ ] Проверить, что `tool/render_release_notes.sh <version> --lang en` дает корректное английское тело GitHub Release
- [ ] Проверить, что `tool/render_release_notes.sh <version> --lang ru` дает корректную русскую версию release notes
- [ ] Если запись в changelog пока сознательно не заполнена, проверить, что fallback-черновик из git history выглядит приемлемо до публикации

## 3. Документация

- [ ] Обновить `README.md` / `README_RU.md`, если изменилось поведение
- [ ] Обновить протокольные и архитектурные документы, если изменился runtime
- [ ] Обновить task/context документы, если заметно изменился статус проекта

## 4. Проверка

- [ ] Выполнить `flutter analyze`
- [ ] Сделать smoke-test основных пользовательских сценариев
- [ ] Проверить старт приложения на целевой платформе
- [ ] Для локального запуска из VSCode проверить, что устройство выбрано в device picker, а профиль запуска не требует ручного `deviceId` в `.vscode/launch.json`
- [ ] Проверить, что сообщения продолжают работать
- [ ] Проверить, что звонки продолжают соединяться
- [ ] Проверить медиа/аватары, если релиз затрагивал эти части

## 5. Платформенные входы

- [ ] Убедиться, что локально доступен `google-services.json` для Android, если он нужен для сборки
- [ ] Убедиться, что локально доступен `GoogleService-Info.plist` для iOS, если он нужен для сборки
- [ ] Убедиться, что вместе с релизом не коммитятся секреты

## 6. Артефакты сборки

- [ ] Собрать Android-артефакт(ы) под целевой релиз
- [ ] Собрать iOS-артефакт(ы) под целевой релиз
- [ ] Проверить, что в артефактах отображается ожидаемая версия и build number
- [ ] Проверить итоговый Android manifest/APK на отсутствие неиспользуемых чувствительных permissions (`USE_EXACT_ALARM`, `MANAGE_EXTERNAL_STORAGE`, storage/media, contacts/call-log), если они не являются основной функцией релиза
- [ ] Если используется ветка `app` для auto-deploy, проверить, что secrets для Google Play / TestFlight настроены и валидны

## 7. Финальный gate

- [ ] Еще раз перечитать changelog
- [ ] Еще раз проверить версию в `pubspec.yaml`
- [ ] Убедиться, что объем релиза соответствует выбранному `patch/minor/major/build`
- [ ] Проверить, что tag имеет формат `app-v<version>`
- [ ] Тегировать и публиковать релиз только после прохождения пунктов выше
