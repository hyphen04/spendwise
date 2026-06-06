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
6. **Build release APK**:
   ```
   flutter build apk --release
   ```
7. **Tell the user** (do NOT upload automatically):
   > "APK is ready at `build/app/outputs/flutter-apk/app-release.apk`
   > Go to https://github.com/hyphen04/spendwise/releases/new, select tag vX.X.X,
   > paste the CHANGELOG entry as description, and upload the APK as an asset.
   > **The asset filename must be `app-release.apk`** — the in-app updater looks for this exact name."

8. **STOP** — do NOT create the GitHub release automatically. The user uploads the APK manually.

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
- APK asset name: **must be `app-release.apk`** (hardcoded in `UpdateService`)

---

## Creating a GitHub Release (step-by-step for future reference)

1. Complete steps 1–6 of the Release Workflow above
2. Go to https://github.com/hyphen04/spendwise/releases/new
3. Under "Choose a tag", select `vX.X.X` from the dropdown
4. Set title: `SpendWise vX.X.X`
5. Paste the CHANGELOG entry into the description box
6. Click "Attach binaries" and upload `build/app/outputs/flutter-apk/app-release.apk`
7. **Rename the uploaded file to `app-release.apk`** if GitHub changes the filename
8. Click "Publish release"

Users will see the update notification the next time they tap "Check for Update" in Settings.
