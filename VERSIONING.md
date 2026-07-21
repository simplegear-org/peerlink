# VERSIONING

Last updated: 2026-04-17

## Source Of Truth

PeerLink keeps versioning intentionally simple: `pubspec.yaml` is the single source of truth for the app version.

Version format:

```yaml
version: x.y.z+n
```

Where:
- `x.y.z` is the semantic application version,
- `n` is the monotonically increasing build number.

Flutter already maps this version into native build metadata:
- Android:
  - `versionName <- x.y.z`
  - `versionCode <- n`
- iOS:
  - `CFBundleShortVersionString <- x.y.z`
  - `CFBundleVersion <- n`

Version changes should not be maintained separately in platform files.

## Versioning Rules

- `patch`: bug fixes and safe internal improvements
- `minor`: backward-compatible features
- `major`: breaking changes or intentionally incompatible behavior changes
- `build`: rebuild without changing semantic version

## PeerLink Release Heuristics

Use these rules by default so releases stay predictable:

- `patch`
  - bug fixes
  - networking stability fixes
  - UI fixes without changing core product behavior
  - internal refactors that do not require user migration
- `minor`
  - new user-visible features
  - new settings, screens, flows, or protocol capabilities that remain backward-compatible
  - significant runtime improvements that users can feel, without breaking old app data
- `major`
  - breaking storage/data migrations
  - intentionally incompatible protocol changes
  - removals or behavior changes that require coordinated rollout
- `build`
  - rebuild of the same app version
  - metadata-only packaging update
  - CI/release repeat without product-level change

## Bump Script

Run from the project root:

```bash
dart run tool/bump_version.dart patch
dart run tool/bump_version.dart minor
dart run tool/bump_version.dart major
dart run tool/bump_version.dart build
dart run tool/bump_version.dart set 1.4.0+27
```

The script updates only the `version:` line in `pubspec.yaml` and prints the resulting version.

## Dev Commit Script

For routine work on `dev`, use:

```bash
tool/dev_commit.sh "fix: short description"
```

What it does:
- verifies that the current branch is `dev`,
- does not change `pubspec.yaml` by default unless the commit message contains a release marker,
- stages the current changes,
- creates a git commit with the provided message.

If the commit message contains one of these markers:

- `[patch]`
- `[minor]`
- `[major]`
- `[build]`

then `tool/dev_commit.sh` also:
- runs `tool/prepare_release.sh <marker>`,
- updates `pubspec.yaml`,
- prepends release entries to `CHANGELOG.md` and `CHANGELOG_RU.md`,
- commits the versioned state directly in `dev`.

Example:

```bash
tool/dev_commit.sh "[patch] Fix reply jump stability"
tool/dev_commit.sh "[minor] Add server health dashboard"
```

With this model, versioning is owned by `dev`, and `main` / `app` simply inherit the already prepared version through PRs.

If you explicitly need a development build bump in `dev`, use:

```bash
tool/dev_commit.sh --bump-build "fix: short description"
```

That variant also increments the `build` number before committing.

## Release Preparation Script

For the usual release path, use:

```bash
tool/prepare_release.sh patch
tool/prepare_release.sh minor
tool/prepare_release.sh major
tool/prepare_release.sh build
```

This script handles the routine release prep:
- bumps `pubspec.yaml`,
- prepends a new release entry to `CHANGELOG.md`,
- prepends a matching entry to `CHANGELOG_RU.md`,
- auto-fills both entries with a draft summary from git history,
- prints the resulting version.

If needed, an explicit version can also be provided:

```bash
tool/prepare_release.sh 1.2.0+15
```

## Suggested Release Flow

For a shorter step-by-step version, see:

- `RELEASE_FLOW.md`

1. Choose `patch`, `minor`, `major`, or `build`.
2. Run `dart run tool/bump_version.dart ...`.
3. Update release notes and relevant `md` files if behavior changed.
4. Add a new entry to `CHANGELOG.md` and `CHANGELOG_RU.md`.
5. Build release artifacts using the updated version.

## GitHub Actions Automation

Workflow: `.github/workflows/release-version.yml`

It supports manual `workflow_dispatch` with:
- release type: `patch` / `minor` / `major` / `build`
- optional tag creation

The workflow then:
- runs `tool/prepare_release.sh`,
- runs `flutter analyze`,
- commits updated release metadata,
- optionally creates tag `app-v<version>`.

## Full Automatic Branch Flow

Workflow: `.github/workflows/branch-release.yml`

Trigger:
- push to `main`
- push to `app`

Behavior:
- version is read directly from `pubspec.yaml`
- release type marker is still detected from the merge commit message for summary/debug purposes only
- no version bump happens in the workflow

Branch behavior:
- `main`:
  - use the version already prepared in `dev`
  - run `flutter analyze`
  - mirror selected files
- `app`:
  - all of the above
  - deploy Android to Google Play `internal`
  - upload iOS build to TestFlight

## Release Commit Message

Use:

```bash
tool/release_commit_message.sh 1.0.2+3 patch
```

It generates the standardized release commit subject used by the workflow.

## GitHub Release Notes

Template: `.github/release-template.md`
Rendered outputs: `build/release_notes/release_notes_en.md` and `build/release_notes/release_notes_ru.md`

Renderer:

```bash
tool/render_release_notes.sh 1.0.1+2 --lang en
tool/render_release_notes.sh 1.0.1+2 --lang ru
```

The renderer selects the matching changelog/template pair for the requested language and injects the version body into the release template.

If the changelog entry is still a placeholder (`TODO`) or effectively empty, the renderer automatically falls back to a git-history draft built from commits since the previous release commit.

Release workflows also:
- upload both rendered language variants as artifacts,
- append both language variants to the GitHub Actions job summary and show the `template source -> rendered output` mapping,
- attach `build/release_notes/release_notes_ru.md` as a GitHub Release asset in the tag-based release flow and link to it from the published release body,
- reuse the same renderer for tag-based and branch-based release flows.

## App Build Workflow

Workflow: `.github/workflows/app-release-build.yml`

Trigger:
- push tag `app-v<version>`

What it does:
- renders GitHub release notes,
- builds Android APK,
- builds iOS app with `--no-codesign`,
- uploads artifacts,
- publishes GitHub Release with attached artifacts.

Required repository secrets:
- `ANDROID_GOOGLE_SERVICES_JSON_B64`
- `IOS_GOOGLE_SERVICE_INFO_PLIST_B64`
- For branch auto-deploy on `app`:
  - `ANDROID_KEYSTORE_B64`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
  - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
  - optional `ANDROID_APPLICATION_ID`
  - `IOS_CERTIFICATE_P12_B64`
  - `IOS_CERTIFICATE_PASSWORD`
  - `IOS_PROVISIONING_PROFILE_B64`
  - `IOS_EXPORT_OPTIONS_PLIST_B64`
  - `APP_STORE_CONNECT_KEY_ID`
  - `APP_STORE_CONNECT_ISSUER_ID`
  - `APP_STORE_CONNECT_API_KEY_B64`

## Baseline

Managed versioning starts from the version already stored in the repository `pubspec.yaml`.
