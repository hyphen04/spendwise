# SpendWise — Agent Instructions

> This file tells the AI agent (Claude Code) how to handle releases and DB schema changes.
> Do NOT delete or rename this file.

---

## Release Workflow

When the user says **"release vX.X.X"** or **"approve release X.X.X"** or similar:

1. **Update `pubspec.yaml`** — set `version: X.X.X+N` (increment build number N by 1 from current)
2. **Update `CHANGELOG.md`** — add a new entry at the very top in this format:
   ```
   ## vX.X.X — YYYY-MM-DD
   ### Added / Changed / Fixed
   - bullet points describing what changed
   ```
3. **Commit** only `pubspec.yaml` and `CHANGELOG.md`:
   ```
   git add pubspec.yaml CHANGELOG.md
   git commit -m "chore: release vX.X.X"
   ```
4. **Tag**:
   ```
   git tag -a vX.X.X -m "Release vX.X.X"
   ```
5. **Push branch and tag**:
   ```
   git push origin main --tags
   ```
6. **Build release APK** (arm64-only, split, to keep the APK small for GitHub distribution):
   ```
   flutter build apk --release --target-platform android-arm64 --split-per-abi
   ```
   This produces a single ~25 MB APK at
   `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` covering modern
   64-bit Android devices.

   > **Why split/arm64-only:** A plain `flutter build apk --release` produces a
   > ~70 MB fat APK bundling `x86_64` (emulators only) and `armeabi-v7a` (legacy
   > 32-bit) native libs. `--target-platform android-arm64` alone only filters
   > Flutter's engine — plugin `.so` files (sqlite3, dartjni) still slip in for
   > all ABIs. `--split-per-abi` forces per-ABI packaging so the output contains
   > only `arm64-v8a` libs. Do NOT add `ndk { abiFilters }` in `build.gradle` —
   > it conflicts with `--split-per-abi` and breaks the build.

7. **Rename the APK** to a clean canonical name (recommended):
   ```
   cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk build/app/outputs/flutter-apk/app-release.apk
   ```
   The updater selects the **first `.apk` asset** on the release
   (`UpdateService.checkForUpdate` uses `endsWith('.apk')`), so the exact name
   is not required by the code — but `app-release.apk` is the project
   convention. Upload **only one** `.apk` per release so the updater can't
   pick the wrong one.

8. **Tell the user** (do NOT upload automatically):
   > "APK is ready at `build/app/outputs/flutter-apk/app-release.apk` (renamed from
   > `app-arm64-v8a-release.apk`, ~25 MB).
   > Go to https://github.com/hyphen04/spendwise/releases/new, select tag vX.X.X,
   > paste the CHANGELOG entry as description, and upload the APK as an asset.
   > Use the filename `app-release.apk` and upload only one `.apk`."

9. **STOP** — do NOT create the GitHub release automatically. The user uploads the APK manually.

---

## Changelog Format Rules (for the changelog parser)

The GitHub release body is pasted from the `CHANGELOG.md` entry, and both the
update sheet and the Settings → "What's New" sheet render it with a small
custom Markdown parser (`lib/app/widgets/changelog_markdown.dart`) — **not** a
full Markdown engine. The parser is forgiving (unsupported syntax degrades to
plain text rather than showing literal markers), but sticking to the supported
set keeps "what's new" clean.

**Supported:**
- `#`–`####` headings. `## vX.X.X — YYYY-MM-DD` is the version heading (one per
  entry, at the top); `### Added` / `### Changed` / `### Fixed` are section
  labels; `####` for minor sub-headings.
- `- ` or `* ` bullets, plus numbered lists (`1.`, `2.`). Up to **one level of
  nesting** (indent a child by 2 spaces). Deeper nesting is flattened.
- `**bold**`, `~~strikethrough~~`, `` `inline code` ``.
- `[text](url)` links — rendered as tappable text that opens externally.
- `![alt](url)` images — rendered as the alt text (no remote image loading).
- `> blockquote` for notes/callouts.
- `---` horizontal rules.
- Blank lines between blocks for spacing.

**NOT supported (avoid):**
- Tables, more than one level of bullet/list nesting.
- HTML, `# ##### ` (5+ hashes), fenced code blocks (` ``` `).

If you need richer formatting, extend `changelog_markdown.dart` first — don't
rely on syntax the parser doesn't handle.

---

## DB Schema Change Checklist

Run this checklist **every time** you modify a Drift table definition:

1. Edit the table file in `lib/data/db/tables/`
2. Run: `dart run build_runner build --delete-conflicting-outputs`
3. Bump `schemaVersion` in `lib/data/db/app_database.dart` by exactly 1
4. Add a migration step in the `onUpgrade` callback:
   ```dart
   if (from < NEW_VERSION) {
     await m.addColumn(tableName, tableName.newColumn);
     // or: await customStatement('ALTER TABLE x ADD COLUMN y TEXT');
   }
   ```
5. **NEVER** use `destructiveMigration` — it deletes all user data permanently
6. **NEVER** add a `NOT NULL` column without a `DEFAULT` value or `Value(fallback)` in the migration
7. **NEVER** remove a column in the same version bump as other changes — deprecate with a comment first
8. Document the schema change in `CHANGELOG.md`

---

## GitHub Repository

- Owner: `hyphen04`
- Repo: `spendwise`
- Releases: https://github.com/hyphen04/spendwise/releases
- Update API: https://api.github.com/repos/hyphen04/spendwise/releases/latest
- APK asset name: `app-release.apk` is the convention. The updater picks the
  first `.apk` asset on the release (`UpdateService` uses `endsWith('.apk')`),
  so the exact name is not required — but upload **only one** `.apk` per release.

---

## Creating a GitHub Release (step-by-step for future reference)

1. Complete steps 1–7 of the Release Workflow above (build + rename to `app-release.apk`)
2. Go to https://github.com/hyphen04/spendwise/releases/new
3. Under "Choose a tag", select `vX.X.X` from the dropdown
4. Set title: `SpendWise vX.X.X`
5. Paste the CHANGELOG entry into the description box
6. Click "Attach binaries" and upload `build/app/outputs/flutter-apk/app-release.apk`
7. **Rename the uploaded file to `app-release.apk`** if GitHub changes the filename
8. Click "Publish release"

Users will see the update notification the next time they tap "Check for Update" in Settings.

---

## List Row Interaction Rules

These apply to every screen that lists editable/deletable rows (transactions,
accounts, categories, modes, budgets, contacts, due entries).

- **Swipe to reveal actions.** Wrap each row in `Slidable` (`flutter_slidable`,
  already a dependency): `startActionPane` = Edit (+ Duplicate where it exists),
  `endActionPane` = Delete. Keep secondary actions (archive, set/clear default)
  in the trailing menu.
- **Tap = open the edit form.** A plain tap on a row opens the entity's edit
  sheet prefilled — it does not open a separate read-only detail view.
- **Always confirm before delete.** Route every delete through the shared
  `showConfirmDeleteDialog` helper (`lib/app/widgets/confirm_delete_dialog.dart`).
  Do not inline new confirm dialogs. (The transaction delete keeps its
  settlement-aware multi-variant dialog via `confirmAndDeleteTransaction` in
  `lib/features/transactions/transaction_actions.dart`.)
- **Always show a snackbar after edit and after delete.** Use the shared
  `showFeedbackSnackBar` helper (`lib/app/utils/feedback.dart`) — "X updated" /
  "X deleted" / "X duplicated". Never leave a successful edit or delete silent.
- Reuse the two helpers above; do not duplicate dialog/snackbar code.
