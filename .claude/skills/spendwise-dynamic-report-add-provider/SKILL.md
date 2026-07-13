---
name: spendwise-dynamic-report-add-provider
description: Add a new named on-device DataProvider to the SpendWise AI dynamic report end-to-end — schema_metadata entry, executor method, validator column allow-list, a shot example, and a test. The safe, repeatable way to extend the AI report without resorting to opt-in LLM SQL. Invoke when you want the AI report to be able to choose a new kind of chart.
---

# Add a named DataProvider to the dynamic report

The dynamic report (`lib/features/ai/dynamic_report/`) is spec-driven: the LLM
emits a `ChartSpec` JSON that names a `DataProvider`; the app executes it on-device
and renders the result. **Named providers are the safe path** — they reuse
existing repository methods, so the LLM never authors SQL and never sees raw rows.
`customSql` (LLM-authored SQL) is a separate, opt-in, riskier path — do not reach
for it when a named provider will do. This skill adds a named provider end-to-end.

## Steps

1. **Pick the provider name and reuse an existing query.** Look in
   `lib/data/repositories/reports_repository.dart` / `budgets_repository.dart` /
   `goals_repository.dart` / `recurring_repository.dart` for a method that returns
   the data you want the LLM to be able to chart. Reuse it — do **not** write new
   SQL unless absolutely necessary. If you must, prefer adding the method to the
   repository (and a repository test) over letting the LLM write it.

2. **Extend the enum** in `lib/features/ai/dynamic_report/chart_spec.dart`:
   ```dart
   enum DataProvider { topCategories, cashflow6mo, budgets, modes,
     monthlySummary, customSql, yourNewProvider }
   ```
   Document the columns the provider returns (the `field`s a `ChartSeries` can
   reference), e.g. `// yourNewProvider: [{name, amount, pct}, ...]`.

3. **Add the executor branch** in `lib/features/ai/dynamic_report/spec_executor.dart`
   that maps the new `DataProvider` → the repository call → a normalized
   `ChartDataset` (`List<Map<String,Object?>>` rows + column types). The dataset
   must contain **only** the spec's named `series` fields — never raw `note` /
   `phone` / `photo` / real names. Map names to the opaque-label form here if
   applicable (the gatekeeper restores on-device at render time).

4. **Update the validator column allow-list** in
   `lib/features/ai/dynamic_report/spec_validator.dart`: add the new provider's
   accepted `params` keys and the set of `series[].field` values it may reference.
   The validator is the source of truth for what's safe — keep it strict.

5. **Add a shot example** in `lib/features/ai/dynamic_report/schema_metadata.dart`
   (and/or in `kReportSpecSystemPrompt` in `lib/features/ai/domain/ai_prompts.dart`
   if the examples live there): one valid `ChartSpec` JSON using the new provider,
   with a short comment on when it's useful. This is how the LLM learns the
   provider exists and when to pick it.

6. **Document the provider in the schema metadata blob** in
   `schema_metadata.dart`: add the provider to the allowed-providers menu sent to
   the LLM, with its params and a one-line description. **Never add PII columns or
   PII tables** (`due_*`, `ai_*`, `note`, `receipt_path`, `phone`, `photo_path`,
   `device_contact_id`, `phones`) to this blob — see the `spendwise-privacy-audit`
   skill. If the new provider surfaces user-private data (e.g. goals, recurring
   bills), keep its table **out** of `kSchemaMetadata` and only expose the
   provider name + a safe shape.

7. **Add a renderer branch** (if needed) in
   `lib/features/ai/dynamic_report/spec_renderer.dart`. Reuse an existing
   `ChartType` (pie/bar/line/progress/list/stat) if one fits; only add a new
   `ChartType` as a last resort (it ripples through the validator + tests).

8. **Test it:**
   - `test/ai/dynamic_report/spec_validator_test.dart` — a spec using the new
     provider with a valid field passes; an unknown field is rejected.
   - A fixture through the executor asserting the dataset shape is right and
     contains **no PII** (no `note`, no real names if the provider is anonymized).
   - Run `spendwise-privacy-audit` after the change.

## Verify

```
flutter analyze lib/
flutter test test/ai/dynamic_report
```
Both clean/green. Then spot-check: with AI on + spec on, the LLM should
sometimes pick the new provider for relevant months (it's a *choice*, not a
guarantee — the default spec is the fallback).

## When NOT to use this skill

If you find yourself wanting the LLM to run arbitrary SQL, that's the opt-in
`customSql` path (`sql_guard.dart`) — higher risk, gated behind a setting, and
structurally blocked from PII. Named providers should cover the common cases;
only escalate to `customSql` for genuinely ad-hoc analysis and only with the
user's explicit opt-in.