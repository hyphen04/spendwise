---
name: spendwise-custom-report
description: Add a custom-report group-by / filter / metric to SpendWise end-to-end — CustomReportSpec field + CustomReportExecutor branch + builder UI + provider — within the safe-table constraint (only transactions joined to accounts/categories/modes/tags/budgets; never note/receipt_path; never due_*/ai_*/recurring_items/goals). Includes the DB schema checklist reference if a new column/table is needed. Invoke when extending the user-authored, on-device, never-AI custom report builder.
---

# Add a custom-report option (group-by / filter / metric / chart type)

The Custom Report builder (`lib/features/reports/custom/`) is **user-authored,
on-device, and never sent to the AI.** The user picks a group-by, filters, a
metric, and a chart type; the app executes the spec locally and renders with
fl_chart. This skill is the safe, repeatable recipe for adding a new option to
that builder. Source of truth: `CLAUDE.md` → "AI Privacy Rules" (the safe-table
subset) and "DB Schema Change Checklist".

> **The custom report is NOT an AI feature.** The `CustomReportSpec` is never
> sent to the LLM. It is pure Dart, executed on-device. Do not route it through
> `AiPayloadBuilder` or the dynamic-report pipeline.

## The safe-table constraint (non-negotiable)

`CustomReportExecutor` is **hard-constrained to the safe subset** — mirror
`lib/features/ai/dynamic_report/sql_guard.dart`'s allow/deny lists as the
template:

- **Allowed tables:** `transactions` joined to `accounts`, `categories`, `modes`,
  `tags`, `budgets`. That is it.
- **Never read:** the `note` or `receipt_path`/`receiptPath` columns (even from
  allowed tables — they are PII).
- **Never touch:** `due_contacts`, `due_entries`, `due_settlements`, `ai_threads`,
  `ai_messages`, `recurring_items`, `goals`. These are PII or on-device-only and
  have no place in a user-authored report query.
- The spec (`CustomReportSpec`) holds **only field references + filters** — no
  free-text, no PII. A saved `custom_reports` row is `name` + `specJson` +
  timestamps; `specJson` is the spec's `toJson`, never a row's contents.

## Steps

1. **Extend `CustomReportSpec`** in
   `lib/features/reports/custom/custom_report_spec.dart`:
   - Add the new option to the relevant enum/field (`groupBy`: category / account
     / mode / tag / day / month; `metric`: sum / count / avg; `kind`: expense /
     income / all; `chartType`: bar / pie / line / list / stat) or add a new
     filter field (`accountId` / `categoryId` / `modeId` / `tagId` /
     `dateRange`).
   - Keep `toJson` / `fromJson` round-trippable (the spec is persisted as
     `specJson` in the `custom_reports` table). Add a round-trip test (see step 6).
   - The spec stays pure Dart — **no** repository imports, **no** DB access.

2. **Add the executor branch** in
   `lib/features/reports/custom/custom_report_executor.dart`:
   - Map the new `groupBy` / `metric` / filter to a `ReportsRepository` method
     (or a small new helper added in the same repo shape — read-only, safe
     tables only). Compose existing methods where possible; do **not** write
     new SQL unless absolutely necessary, and if you do, keep it to the allowed
     tables/columns.
   - Return a normalized dataset the renderer can consume (reuse the
     `SpecRenderer` / `SpecChart` shapes from the dynamic report where they
     fit). The dataset must contain **only** the grouped metric + opaque-ish
     labels (the custom report is on-device, so real names are fine to show the
     user — but never `note` / `receipt_path`).
   - Assert the branch never reads `note` / `receipt_path` and never touches
     `due_*` / `ai_*` / `recurring_items` / `goals`.

3. **Add the builder UI** in
   `lib/features/reports/custom/custom_report_builder_screen.dart`:
   - A picker for the new option (segmented control / dropdown matching the
     existing builder's idiom) with a **live fl_chart preview** that re-runs the
     executor on spec change.
   - Reuse `showSpendWiseSheet` / `showFeedbackSnackBar` / `showConfirmDeleteDialog`
     per the List Row Interaction Rules if the builder lists/saves/deletes specs.
   - Save writes a `custom_reports` row via the DAO; "X saved" snackbar, never
     silent.

4. **Add the provider** in `lib/state/custom_report_providers.dart`:
   - Reuse the existing provider family pattern
     (`customReportsStreamProvider`, `customReportSpecProvider`,
     `customReportDataProvider.family`). Add a new provider only if the option
     needs a distinct async source; otherwise the existing family parameterized
     by spec is enough.
   - `ref.watch` in `build`, `ref.read` in callbacks (Riverpod hygiene).

5. **Add the renderer branch** (if a new `chartType`) in the renderer used by
   `custom_report_view_screen.dart`. Reuse an existing `ChartType` if one fits;
   only add a new one as a last resort (it ripples through the renderer + tests).

6. **DB schema change (only if a new column/table is needed).** A new
   `groupBy`/`metric`/`filter` that fits in the existing `specJson` needs **no**
   schema change — just bump nothing. If you genuinely need a new table or
   column (rare), follow the DB Schema Change Checklist:
   - Edit the table file in `lib/data/db/tables/`.
   - Run `dart run build_runner build --delete-conflicting-outputs` (the
     supervisor runs tooling — do not hand-write `.g.dart`).
   - Bump `schemaVersion` in `lib/data/db/app_database.dart` by exactly 1.
   - Add an additive `onUpgrade` step (`m.createTable` / `m.addColumn`); never
     `destructiveMigration`; never NOT NULL without a DEFAULT.
   - Document in `CHANGELOG.md` and `CLAUDE.md` DB checklist.
   See the `spendwise-db-schema-change` skill for the full recipe.

7. **Test it:**
   - `test/reports/custom/custom_report_spec_test.dart` — `toJson` / `fromJson`
     round-trip for the new option.
   - An executor fixture asserting the dataset shape is right and contains
     **no** `note` / `receipt_path` and touches no `due_*` / `ai_*` /
     `recurring_items` / `goals` table.
   - The custom report is on-device and never AI, so a privacy audit is not
     strictly required — **but** if your executor writes any new SQL, run
     `spendwise-privacy-audit` to confirm the safe-table subset holds.

## Verify

```
flutter analyze lib/
flutter test test/reports/custom
```
Both clean/green. Then spot-check: build a custom report with the new option,
save it, reopen it, and confirm the preview matches the saved view.

## When NOT to use this skill

- You want the **AI** to choose a chart from the user's data → that's the
  dynamic report; use `spendwise-dynamic-report-add-provider`.
- You want to send a new field to the **LLM** → use
  `spendwise-ai-payload-extension`.
- Your new option would require reading `note`, `receipt_path`, or any
  `due_*` / `ai_*` / `recurring_items` / `goals` table → **stop**. The
  safe-table constraint is absolute for the custom report.