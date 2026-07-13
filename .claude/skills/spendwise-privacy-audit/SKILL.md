---
name: spendwise-privacy-audit
description: Audit a SpendWise change against the privacy invariant — verify no personal details leave the device, the gatekeeper runs on LLM output, the legend never leaves, and PII columns/tables are unreachable by LLM SQL. Invoke after any change touching the AI payload, the report spec pipeline, or PII-bearing tables.
---

# SpendWise privacy audit

The PRIMARY rule, stated by the user: **no personal details ever leave the device.**
This is the marketing USP ("local aggregation, remote synthesis without
exposure") and the single most important invariant in the codebase. Run this
audit after **any** change that touches the AI outbound path, the dynamic-report
spec pipeline, the gatekeeper, or a PII-bearing table. Output a pass/fail report.

## The invariant

`lib/features/ai/domain/ai_payload_builder.dart` is the **sole** code that
constructs what leaves the device. Everything outbound goes through it (or, for
the dynamic report, through `lib/features/ai/dynamic_report/schema_metadata.dart`
for the schema blob + opaque labels for data). `AiGatekeeper` restores labels /
scrubs PII on-device on the return path.

**Never sent (in either chat or report mode):**
- transaction `note`s
- `due_contacts` name / phone / phones / photoPath / deviceContactId / defaultNote
- `due_entries` / `due_settlements` notes
- receipt paths
- raw rows, real amounts, real category/account/mode/tag names (those are
  anonymized to opaque `cat_0`/`acc_1`/`mode_1`/`tag_1` keys by default; a
  settings toggle opts into real names, in which case a `legend` map is attached
  but still restored on-device and never round-tripped unnecessarily)
- For the dynamic report: the LLM sees only schema metadata (table/column names +
  kinds, no PII columns) + opaque labels; it **never** sees raw rows or real
  amounts; queries execute on-device; results are never sent back.

## What to check

1. **No outbound data construction outside the boundary.**
   ```
   rg -n "LlmClient|complete\(|\.send|http\.|dio\." lib/features/ai lib/services
   ```
   Every call site must flow through `AiPayloadBuilder` (or, for the report,
   `schema_metadata.dart` + opaque labels). Flag any place that builds a prompt
   body from raw rows, real names, notes, or amounts directly.

2. **PII columns/tables unreachable by LLM SQL.**
   - `lib/features/ai/dynamic_report/schema_metadata.dart` must **not** list:
     `due_contacts`, `due_entries`, `due_settlements`, `ai_threads`, `ai_messages`
     tables; nor columns `note`, `receipt_path`/`receiptPath`, `phone`, `phones`,
     `photo_path`/`photoPath`, `device_contact_id`/`deviceContactId`.
   - `lib/features/ai/dynamic_report/sql_guard.dart` must hard-block those same
     tables/columns (table allow-list + column blocklist + EXPLAIN introspection).
   - Tables deliberately kept out of the AI schema (e.g. `recurring_items`,
     `goals`) should still be absent from `kSchemaMetadata`.

3. **Gatekeeper runs on LLM output.** Every LLM text surface (chat replies,
   polished insights, digest polish, report `title`/`caption`/`narrativeSeed`,
   report narrative) must pass through `AiGatekeeper` (label restore + PII scrub
   + numeric sanity) before being shown to the user.
   ```
   rg -n "AiGatekeeper|gatekeeper\." lib/features/ai
   ```

4. **API key storage.** The key must live in `flutter_secure_storage` via
   `SecureStorageService`, not in SharedPreferences. Never logged, never held in
   long-lived Riverpod state.
   ```
   rg -n "aiApiKey|llmKey|SecureStorageService" lib
   ```

5. **No notes/PII in aggregations.** If `ReportsRepository` / `BudgetsRepository`
   adds a new aggregation field, confirm it carries no `note`/name/phone. (Past
   example: `MonthlySummary.biggestSpendNote` was explicitly dropped from the AI
   payload.)

6. **Tests.** There must be a boundary test asserting the new/changed outbound
   fields contain no PII:
   ```
   test/ai/ai_payload_builder_test.dart
   test/ai/dynamic_report/llm_spec_roundtrip_test.dart
   ```
   If the change added an outbound field, add an assertion here.

## Output

Report each check as PASS / FAIL with a one-line evidence pointer
(`file:line`). FAIL on any of 1–4 is a hard blocker — fix before merge. FAIL on
5–6 is a soft blocker — add the assertion/test. End with a one-line verdict:
`PRIVACY: PASS` or `PRIVACY: FAIL (n blockers)`.