# RELEASE CHECKLIST

Last updated: 2026-04-17

This checklist is meant to keep PeerLink releases calm and predictable: no missing basics, no last-minute surprises.

For a shorter practical sequence without the full checklist, see:

- `RELEASE_FLOW.md`

## 1. Version

- [ ] Decide release type: `patch`, `minor`, `major`, or `build`
- [ ] Bump version in `pubspec.yaml` via:
  - `dart run tool/bump_version.dart patch`
  - `dart run tool/bump_version.dart minor`
  - `dart run tool/bump_version.dart major`
  - `dart run tool/bump_version.dart build`
- [ ] Or run `tool/prepare_release.sh <patch|minor|major|build>` for version bump + changelog stub in one step
- [ ] Confirm the resulting version string is correct

## 2. Release Notes

- [ ] Add a new entry to `CHANGELOG.md`
- [ ] Add a matching entry to `CHANGELOG_RU.md`
- [ ] Review and clean up the automatic changelog draft generated from git history
- [ ] Verify notable user-facing changes are described briefly and honestly
- [ ] Verify `tool/render_release_notes.sh <version> --lang en` produces the expected English GitHub Release body
- [ ] Verify `tool/render_release_notes.sh <version> --lang ru` produces the expected Russian release-notes variant
- [ ] If the changelog entry is still intentionally incomplete, verify the git-history fallback draft is acceptable before publication

## 3. Documentation

- [ ] Update `README.md` / `README_RU.md` if behavior changed
- [ ] Update protocol/architecture docs if runtime behavior changed
- [ ] Update task/context docs if project status changed materially

## 4. Validation

- [ ] Run `flutter analyze`
- [ ] Smoke-test the main app flows
- [ ] Verify app startup on the target platform
- [ ] Verify messaging still works
- [ ] Verify calls still connect
- [ ] Verify media/avatar flows still work if touched by the release

## 5. Platform Inputs

- [ ] Confirm `google-services.json` is present locally for Android builds if needed
- [ ] Confirm `GoogleService-Info.plist` is present locally for iOS builds if needed
- [ ] Confirm no secrets are being committed as part of the release

## 6. Build Artifacts

- [ ] Build Android artifact(s) for the release target
- [ ] Build iOS artifact(s) for the release target
- [ ] Verify the produced artifacts report the expected version/build number
- [ ] If branch `app` is used for auto-deploy, verify Google Play / TestFlight secrets are configured and valid

## 7. Final Gate

- [ ] Re-read changelog entry
- [ ] Re-check version in `pubspec.yaml`
- [ ] Confirm the release scope matches the chosen `patch/minor/major/build`
- [ ] Confirm tag name matches `app-v<version>`
- [ ] Tag/publish only after the above items are complete
