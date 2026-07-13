---
name: spendwise-db-schema-change
description: Make a Drift schema change in SpendWise safely — edit the table, run build_runner, bump schemaVersion, add an additive onUpgrade migration step, and document it. Invoke whenever you modify a Drift table definition (add/rename column, add table).
---

# SpendWise DB schema change

SpendWise uses Drift with a manual `onUpgrade` migration (no destructive
migrations — they'd wipe user data). Run this checklist **every time** you modify
a table in `lib/data/db/tables/`. Source of truth: `CLAUDE.md` → "DB Schema
Change Checklist".

## Checklist

1. **Edit the table file** in `lib/data/db/tables/` (e.g. add a column / new table).
   - For a new table, follow the existing table conventions (integer primary key,
     `createdAt`/`updatedAt` TEXT ISO timestamps, sensible defaults).
2. **Regenerate** the Drift glue:
   ```
   dart run build_runner build --delete-conflicting-outputs
   ```
   This rewrites `*.g.dart` files — commit them alongside the table change.
3. **Bump `schemaVersion`** in `lib/data/db/app_database.dart` by exactly 1
   (e.g. `schemaVersion => 14` → `15`). Never bump by more than 1 per release.
4. **Add a migration step** in the `MigrationStrategy.onUpgrade` callback:
   ```dart
   if (from < NEW_VERSION) {
     await m.addColumn(tableName, tableName.newColumn);
     // or for a new table:
     await m.createTable(newTable);
     // or raw DDL:
     await customStatement('ALTER TABLE x ADD COLUMN y TEXT NOT NULL DEFAULT ""');
   }
   ```
   - `m.addColumn` / `m.createTable` are preferred over hand-written DDL — they
     use the live table definitions and are less error-prone.
   - Each `if (from < N)` block is additive and runs once per upgrade path.
5. **NEVER** use `destructiveMigration` — it deletes all user data permanently.
6. **NEVER** add a `NOT NULL` column without a `DEFAULT` value or a `Value(fallback)`
   in the migration. Existing rows have no value for the new column.
7. **NEVER** remove a column in the same version bump as other changes — deprecate
   it with a `// DEPRECATED: drop in vX.Y` comment first and remove it in a later
   release, so there's a window where the column still exists.
8. **Document** the schema change in `CHANGELOG.md` under the relevant section
   (typically a `### Changed` / `### Added` entry under the version or
   `## Unreleased`, e.g. "DB schema v14 → v15: added goals.targetDate").

## Privacy (when the table/column touches user data)

- Tables that hold personal details (`due_contacts`, `due_entries`,
  `due_settlements`, `ai_threads`, `ai_messages`) and columns (`note`,
  `receipt_path`, `phone`, `photo_path`, `device_contact_id`, `phones`) must
  **never** be exposed to the AI. The LLM sees only `kSchemaMetadata` in
  `lib/features/ai/dynamic_report/schema_metadata.dart` — a frozen, hand-authored
  PII-stripped blob. If your new table/column is PII-sensitive, **do not add it to
  `kSchemaMetadata`** (see the `spendwise-privacy-audit` skill). Tables like
  `recurring_items` and `goals` are deliberately kept out of the AI schema for
  exactly this reason.
- Run `spendwise-privacy-audit` after any change that touches PII-bearing tables or
  the AI payload path.

## Verify

```
flutter analyze lib/
flutter test
```
Both must be clean/green before the schema change is considered done. If a
migration is non-trivial, add a test that opens a DB at the old `schemaVersion`,
runs `db.customStatement('PRAGMA user_version = OLD')`, then upgrades and asserts
the new column/table exists with the right defaults.