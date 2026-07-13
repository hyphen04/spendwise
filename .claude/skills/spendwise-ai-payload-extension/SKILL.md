---
name: spendwise-ai-payload-extension
description: Add a new field to the SpendWise AI outbound payload safely end-to-end — anonymize via _Labeler (cat_N/acc_N/mode_N/tag_N/goal_N/bill_N), never send PII (notes/names/phones/photos/receipt paths/raw rows), extend AiGatekeeper validation (sentAmounts/sentNameVocabulary + numeric-correspondence + hallucinated-name checks), relax prompts only if the renderer supports the syntax, route polish/digest through the gatekeeper, run spendwise-privacy-audit, and update CLAUDE.md. Invoke whenever you add or change what the AI sees.
---

# Extend the SpendWise AI outbound payload

`lib/features/ai/domain/ai_payload_builder.dart` is the **sole** code that
constructs what leaves the device. This skill is the safe, repeatable recipe for
adding or changing a field in `buildAskContext` / `buildReportContext` without
breaking the privacy invariant. Source of truth: `CLAUDE.md` → "AI Privacy
Rules". **Read `ai_payload_builder.dart` and `ai_gatekeeper.dart` before
editing — the code is the truth, not this skill.**

## The invariant (non-negotiable)

> **No personal details ever leave the device.**

Never sent, in any mode:
- transaction `note`s; `due_contacts` name/phone/phones/photoPath/deviceContactId/
  defaultNote; `due_entries` / `due_settlements` notes; receipt paths; raw rows;
  real amounts; real category/account/mode/tag/**goal**/**bill** names.
- Names are anonymized to opaque labels (`cat_0`/`acc_1`/`mode_1`/`tag_1`/
  `goal_N`/`bill_N`) by default. A `shareNames` toggle opts into real names, in
  which case a `legend` map is attached — but it is **restored on-device** by the
  gatekeeper and never round-tripped unnecessarily.
- `due_*` and `ai_*` tables are hard-blocked from the AI. Goals and recurring
  bills reach the AI **as anonymized aggregates only** (`goal_N`/`bill_N` — no
  names, no notes, no icons; the legend never leaves unless `shareNames`).

## Steps

1. **Pick the field and reuse an existing aggregation.** Look in
   `lib/data/repositories/` (`reports_repository.dart`, `budgets_repository.dart`,
   `goals_repository.dart`, `recurring_repository.dart`) for a method that
   returns the aggregate you want. Reuse it — do **not** read raw rows in the
   builder. Amounts may be real aggregates (consistent with today's model);
   **names** are never real. Add the field as an **optional** entry in
   `buildAskContext` (and `buildReportContext` to match) — omit the key entirely
   when empty so the payload stays small.

2. **Anonymize via `_Labeler`.** Every name-bearing reference goes through the
   existing `_Labeler`:
   - `cat_N` (categories), `acc_N` (accounts), `mode_N` (payment modes),
     `tag_N` (tags) — already exist.
   - `goal_N` (goals) and `bill_N` (recurring bills) — extend `_Labeler` with
     `goal`/`bill` labelers if not already present. The legend records the
     `goal_N → id` / `bill_N → id` mapping; it is embedded in the outbound JSON
     **only** when `shareNames` is on (existing gating — do not change it).
   - For goals/bills, send **only** safe aggregates: goals →
     `{id: goal_N, target, saved, pct, months_left?, monthly_commitment?}`;
     bills → `{id: bill_N, amount, cadence, next_due_in_days, source}`.
     **No** name, icon, or note. Ever.

3. **Never send PII.** Confirm the new field carries no `note`, no contact
   name/phone/photo, no receipt path, no raw row. If the source aggregate has a
   PII field (e.g. a `note` column), drop it before serializing. (Past example:
   `MonthlySummary.biggestSpendNote` was explicitly dropped from the AI payload.)

4. **Extend `AiGatekeeper` validation.** The gatekeeper is constructed with the
   legend + `validLabels` **plus** the new correspondence data:
   - `sentAmounts` — the rounded figures the payload sent (every amount you add
     to the payload must be registered here).
   - `sentNameVocabulary` — the real names sent, **only** when `shareNames` is on
     (empty otherwise).
   `check()` keeps existing empty/garbage, leftover-label, PII-scrub, and
   `>max*10` numeric checks, and adds:
   - **Numeric correspondence**: parse currency-ish numbers from the reply; flag
     any that are neither within tolerance of a `sentAmounts` entry nor a sane
     derived figure (≤ `maxContextAmount * 1.5`). Catches hallucinated figures.
   - **Hallucinated-name detection** (only when `shareNames`): flag category/
     account/mode/tag/goal/bill names in the reply that are not in
     `sentNameVocabulary`.
   `restore()` is unchanged (`LabelReplacer`). Every amount you add to the
   payload **must** be added to `sentAmounts`, or the numeric-correspondence
   check will flag legitimate LLM restatements as hallucinations.

5. **Route polish/digest through the gatekeeper.** No LLM text surface bypasses
   the gatekeeper. If your change touches insight/digest polish
   (`ai_insight_polish_controller.dart`, digest polish controller), run the
   polished reply through `AiGatekeeper` (built from the
   `InsightAnonymizer` legend) for `restore` **and** `check` — replacing any
   direct `InsightAnonymizer.restore` call site. `InsightAnonymizer` stays as
   the legend builder; the gatekeeper is the single validator. Surface the
   `CheckedOnDeviceNote` if `flagged`; fall back to local on `bad`.

6. **Relax prompts only if the renderer supports the syntax.** AI replies now
   render with `flutter_markdown` (`AiMarkdown` in
   `lib/features/ai/widgets/ai_markdown.dart`) — tables and fenced code blocks
   are supported. If your field lets the LLM answer richer, you may relax
   `kAskSystemPrompt` / `kReportSystemPrompt` in
   `lib/features/ai/domain/ai_prompts.dart` to allow tables + fenced code.
   **Keep all PII-prohibition wording** and the "use opaque labels / don't
   invent numbers" rules. Do **not** touch the changelog prompts —
   `ChangelogMarkdown` is still the changelog/What's New parser with its
   existing supported-subset rules.

7. **Test it.** Add/extend boundary tests asserting the new outbound field
   contains no PII:
   ```
   test/ai/ai_payload_builder_test.dart
   ```
   - Assert the new field is present with the right shape and **no** `note`/name/
     phone/photo/receipt path.
   - If you extended the gatekeeper, add a test that a reply with a
     hallucinated figure (not in `sentAmounts`, > `maxContextAmount * 1.5`) is
     `flagged`, and a reply with a hallucinated name (not in
     `sentNameVocabulary`, `shareNames` on) is `flagged`.
   - Goals/bills: assert the payload carries `goal_N`/`bill_N` ids and **no**
     name/note/icon.

8. **Run the privacy audit.** Before merge, run the `spendwise-privacy-audit`
   skill (or `@spendwise-privacy-auditor` agent). It must PASS. This change
   touches the AI outbound path and the gatekeeper, so the audit is mandatory.

9. **Update `CLAUDE.md`.** If your field changes the rules (e.g. a previously
   on-device-only table now reaches the AI as an anonymized aggregate), update
   the "AI Privacy Rules" section so the file stays the source of truth. Track 4
   owns `CLAUDE.md` — supply the wording, do not edit the file outside your
   track.

## Verify

```
flutter analyze lib/
flutter test test/ai
```
Both clean/green. Then spot-check: with AI on, ask a question the new field
enables; confirm the reply references the new data using opaque labels (or real
names restored on-device if `shareNames`), and that a deliberately hallucinated
figure in a test reply is caught.

## When NOT to use this skill

- Adding a **dynamic-report** chart provider → use
  `spendwise-dynamic-report-add-provider` instead (the report is spec-driven,
  not payload-driven).
- Adding a **user-authored custom report** (group-by/filter/metric, on-device,
  never AI) → use `spendwise-custom-report`.
- Anything that would send a `note`, contact name/phone/photo, receipt path, or
  raw row → **stop**. The invariant is absolute; no feature justifies it.