---
name: spendwise-release
description: Cut a SpendWise release — bump pubspec+build, write the CHANGELOG entry, commit, tag, push, build the smallest-possible arm64 split APK (obfuscated + R8-minified + resource-shrunk + English-only), report its size vs. the prior release, and hand off to the user for manual GitHub release upload. Invoke when the user says "release vX.X.X" / "approve release X.X.X" or similar.
---

# SpendWise release

Cut a release following `CLAUDE.md` → "Release Workflow" exactly, with one
overriding principle: **the shipped APK must be as small as possible.** Every
release applies the size levers in step 8 and reports the resulting size vs. the
prior release — a size regression is a release blocker. **Never upload the APK or
create the GitHub release automatically** — the user does that by hand.

## Steps

1. **Read the current version** from `pubspec.yaml` (`version: X.Y.Z+N`) so you know
   the build number to increment.
2. **Update `pubspec.yaml`** — set `version: X.X.X+N` where N is the previous build
   number + 1.
3. **Update `CHANGELOG.md`** — add a new entry at the very top:
   ```
   ## vX.X.X — YYYY-MM-DD
   ### Added / Changed / Fixed
   - bullet points
   ```
   Use today's date (the environment's `currentDate`). Synthesize the entry from the
   unreleased work (git log since the last tag, plus the existing "## Unreleased"
   section if present). When you promote an "Unreleased" section to a versioned
   entry, replace the `## Unreleased` heading with the versioned one (and leave a
   fresh empty `## Unreleased` above it for future work).
4. **Follow the changelog parser subset** (see `CLAUDE.md` → "Changelog Format
   Rules"): only `#`–`####` headings, one level of bullet nesting, `**bold**`,
   `~~strike~~`, `` `code` ``, `[text](url)`, `> blockquote`, `---`. **Never** tables,
   HTML, fenced code blocks, or 5+ hashes.
5. **Commit only `pubspec.yaml` and `CHANGELOG.md`:**
   ```
   git add pubspec.yaml CHANGELOG.md
   git commit -m "chore: release vX.X.X"
   ```
6. **Tag:** `git tag -a vX.X.X -m "Release vX.X.X"`
7. **Push branch and tag:** `git push origin main --tags`
8. **Minimize APK size — ensure the size levers are on** (see "Size levers" below).
   The first two are one-time project config in `android/app/build.gradle` — add
   them if missing (they persist across releases). The third is a build flag.
9. **Build the release APK** (arm64-only, split, obfuscated — keeps the APK minimal):
   ```
   flutter build apk --release --target-platform android-arm64 --split-per-abi \
     --obfuscate --split-debug-info=build/symbols/vX.X.X
   ```
   Do NOT add `ndk { abiFilters }` in `build.gradle` — it conflicts with
   `--split-per-abi` and breaks the build.
10. **Rename** the APK to the canonical name:
    ```
    cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk build/app/outputs/flutter-apk/app-release.apk
    ```
11. **Report the size and compare to the prior release:**
    ```
    ls -lh build/app/outputs/flutter-apk/app-release.apk
    ```
    Pull the previous release's APK size from the prior GitHub release / your last
    `ls -lh`. If the new APK is larger by more than ~1 MB and you did NOT knowingly
    add a heavy dependency/asset, treat it as a release blocker and investigate
    before handing off: run a **separate** diagnostic build
    `flutter build apk --release --target-platform android-arm64 --split-per-abi --analyze-size`
    (note: `--analyze-size` cannot be combined with `--split-debug-info`, so it's a
    one-off — don't add `--obfuscate`/`--split-debug-info` here), or audit newly
    added packages/assets in `pubspec.yaml` and `assets/`.
12. **STOP and tell the user** (do NOT upload, do NOT create the GitHub release):
    > "APK is ready at `build/app/outputs/flutter-apk/app-release.apk` (~<size> MB,
    > <smaller/larger than vPrev by <delta>). Obfuscation symbols are at
    > `build/symbols/vX.X.X/` — keep them to de-obfuscate any crash stack traces
    > (not committed; `build/` is gitignored).
    > Go to https://github.com/hyphen04/spendwise/releases/new, select tag vX.X.X,
    > paste the CHANGELOG entry as description, and upload the APK as an asset.
    > Use the filename `app-release.apk` and upload only one `.apk`."

The updater (`UpdateService.checkForUpdate`) picks the **first `.apk` asset** on the
release (`endsWith('.apk')`), so the exact filename isn't required — but upload **only
one** `.apk` so it can't pick the wrong one.

## Size levers (always on)

The arm64 split already drops `x86_64` (emulators) and `armeabi-v7a` (legacy 32-bit).
These additional levers keep the APK as small as possible. They are non-negotiable for
a release unless the user explicitly overrides.

### A. R8 code shrinking + resource shrinking — `android/app/build.gradle`

The release `buildType` must run R8 minify + resource shrinking. Add these lines if
they're missing (they persist after the first release):

```gradle
buildTypes {
    release {
        signingConfig = signingConfigs.release
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

`shrinkResources true` requires `minifyEnabled true`. If `android/app/proguard-rules.pro`
does not exist, create it empty — only add `-keep` rules later if a release build
crashes on a reflectively-loaded plugin (don't disable minify to fix it).

> **First release after enabling R8:** smoke-test the APK (app launches, add a
> transaction, open a report, open AI chat, export a PDF). R8 can occasionally strip
> reflectively-used plugin code; if a flow breaks, add a targeted `-keep` rule in
> `proguard-rules.pro`. This is a one-time verification — once stable, R8 is safe to
> keep on for every release.

### B. Locale pruning — `android/app/build.gradle` `defaultConfig`

Drop the translated resources that AndroidX / play-services / other deps bundle for
locales the app doesn't ship:

```gradle
defaultConfig {
    // ... existing lines ...
    resConfigs "en"
}
```

The app currently ships English-only UI, so this is safe. If a future release adds
another locale, add it here (`resConfigs "en", "hi"`, etc.).

### C. Obfuscate + split debug info — build flag (step 9)

`--obfuscate` shortens Dart symbol names (smaller Dart payload + harder to reverse);
`--split-debug-info=build/symbols/vX.X.X` pulls the debug symbols OUT of the APK into
a separate file that is NOT shipped. Both shrink the shipped Dart code.

**Keep the symbols directory** (`build/symbols/vX.X.X/`) — it is required to
de-obfuscate crash stack traces for that version. It is not committed (`build/` is
gitignored). Don't delete it until crash reports for vX.X.X are symbolicated.

### Not size levers (don't add)
- Do NOT add `--tree-shake-icons` — icon tree-shaking is automatic in modern Flutter
  and the flag is deprecated/removed; specifying it can break the build.
- Do NOT add `ndk { abiFilters }` — it conflicts with `--split-per-abi`.
- Do NOT build a fat APK (no `--split-per-abi`) — it bundles x86_64 + armeabi-v7a and
  triples the size.

## Guardrails

- **Size is a release metric.** Always run step 11 (`ls -lh` + compare). A regression
  > ~1 MB without a known heavy addition is a release blocker.
- Only bump `schemaVersion` / run `build_runner` if this release also includes a DB
  schema change — that's a separate concern (see the `spendwise-db-schema-change`
  skill) and must be done *before* the release commit, not as part of it.
- If `git status` shows uncommitted changes beyond `pubspec.yaml`/`CHANGELOG.md`
  mid-release, surface them to the user — don't silently bundle them in.