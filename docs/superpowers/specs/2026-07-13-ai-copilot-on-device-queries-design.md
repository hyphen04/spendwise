# AI Copilot — richer snapshot + on-device query tools

**Date:** 2026-07-13
**Status:** Approved (design); implementation pending
**Supersedes / builds on:** the AI+Reports overhaul (the `i-want-you-to-atomic-oasis` plan) and the
in-session mention-resolver fix (`AiMentionResolver`).

## Problem

The AI Copilot is not useful enough. Two concrete failures reported by a user with
"Share category & account names" **on**:

1. "Tell me about fuel" → the AI says "no category named fuel" even though Fuel exists.
2. "How many categories do we have?" → the AI says 5, but the user has more.

Root cause: the outbound payload is a **tiny static snapshot**. `AiPayloadBuilder.buildAskContext`
sends only the **top-5 expense categories with spend this month** (`LIMIT 5` in
`reports_repository.monthlySummary`), the current month's summary, 6-month cashflow, and a few
optional aggregates. So:

- The AI literally sees 5 categories → it answers 5. It has no notion of the rest.
- A category not in this month's top-5 spenders (or with no spend this month) is **absent from the
  payload** → even with `shareNames` on, the legend doesn't include it → "no category named fuel".
- The AI cannot answer anything about other months, arbitrary date ranges, filtered totals, or
  planning scenarios, because it has no way to ask for that data.

The in-session `AiMentionResolver` bridges the user's *typed* name to a label/amount, which helps
for named categories, but it does **not** fix "how many categories" (a count question, not a name
mention) and cannot answer arbitrary/historical questions. The real fix is structural: give the AI
the full picture (Phase 1) and the ability to pull on-device aggregates on demand (Phase 2).

## Privacy invariant (unchanged — the hard line)

This work expands what the AI can answer, **not** what data leaves the device. The primary
invariant stands: **no personal details ever leave the device.**

- Only **aggregates + anonymized labels** leave. Never: transaction `note`s; `due_contacts`
  name/phone/phones/photoPath/deviceContactId/defaultNote; `due_entries`/`due_settlements` notes;
  receipt paths; raw transaction rows; real category/account/mode/tag/goal/bill **names** (anonymized
  to `cat_0`/`acc_1`/`mode_1`/`tag_1`/`goal_N`/`bill_N` by default; real names are an opt-in
  `shareNames` toggle that attaches a legend, still restored on-device).
- `due_*`/`ai_*` tables and the PII columns (`note`, `receipt_path`, `phone`, `phones`,
  `photo_path`, `device_contact_id`) are **hard-blocked** — neither the payload nor any tool reads
  them. `goals`/`recurring_items` reach the AI **only** as anonymized aggregates (`goal_N`/`bill_N`),
  never as tables the tools query.
- Tools are **named, fixed queries** (not LLM-authored SQL). Safety comes from the tool set itself,
  mirroring `SqlGuard`'s allow/deny philosophy. The existing opt-in `customSql` path is unchanged and
  separate.
- `AiPayloadBuilder` remains the sole constructor of the aggregate payload. `AiGatekeeper` runs on
  every LLM text surface (chat, report, polish, digest) — unchanged — and is extended only to accept
  tool-result figures in its numeric-correspondence check.
- API key stays in `flutter_secure_storage`, read on demand, never logged, never in long-lived state.

## Phase 1 — Richer snapshot (quick win)

**Goal:** fix "how many categories" and "tell me about fuel" immediately, and make the AI useful for
current/recent questions, by sending the full picture instead of top-5.

**Scope:** chat only (`buildAskContext`). The report narrative (`buildReportContext`) keeps its
top-5 highlights — it is about a curated monthly story, not exhaustive data.

### Changes to `AiPayloadBuilder.buildAskContext`

Add an `allCategories: List<({String id, String name})>` param (the full active-category directory,
already gathered by `gatherAiMentionData`) and a full current-month `categoryBreakdown` (the gatherer
already fetches `categoryBreakdown3mo`; index `[2]` is the current month). Emit:

- **`categories`** — every active category, sorted by current-month spend desc (0-spend ones last),
  each `{id: cat_N, amount, pct_of_expense, trend_3mo: [a,b,c]}`. `trend_3mo` is always present and
  uniform (zeros for categories with no spend in the 3-month window) so the shape is predictable for
  the LLM. This **replaces** `top_expense_categories` in the chat payload. The `_Labeler` labels
  every category (including 0-spend ones) so the legend is complete → `shareNames` now exposes every
  category, and the gatekeeper can restore any of them.
- **`payment_modes`** / **`tag_breakdown`** — every active mode/tag (not just those with spend this
  month), each with `amount` (0 if none) + `pct`. The `_Labeler` labels every mode/tag.
- **`account_balances`** — unchanged (already all active accounts).
- **Counts** — `category_count`, `account_count`, `mode_count`, `tag_count`, `goal_count`,
  `bill_count` (top-level scalars).
- **`cashflow_12mo`** — replace `cashflow_6mo` with the last 12 completed months
  (`ReportsRepository.cashFlowMonths` already returns the rolling series; take 12).
- Keep `goals`/`recurring_bills`/`savings_rate_trend`/`day_distribution`/`tx_frequency` as today.

Token budget: ~20 categories × ~10 tokens + 12-month cashflow ~180 tokens → payload ≈ 1–1.5k tokens.
Acceptable for chat.

### Gatherer

`gatherAiContextExtras` already fetches the 3-month category breakdown and `gatherAiMentionData`
already fetches the full category/mode/tag directory + account balances. Phase 1 wires the full
directory + full current-month breakdown into `buildAskContext`. The report repository needs a
**full** (non-`LIMIT 5`) current-month category breakdown — add `categoryBreakdownAll` (or pass a
limit param to the existing `categoryBreakdown`, which already returns all rows; `monthlySummary`'s
top-5 stays separate for its own consumers). `categoryBreakdown` already has no `LIMIT`, so the full
list is available — just feed it to the builder.

### Prompts

`kAskSystemPrompt` already (from the mention fix) tells the AI not to claim categories "don't exist"
and to use `[Context note]` lines. Add: the summary now lists **all** your categories/modes/tags with
counts and a 12-month cashflow — answer count questions from `*_count`, and per-category questions
from the `categories` list (any category, including 0-spend).

### Files (Phase 1)

- `lib/features/ai/domain/ai_payload_builder.dart` — `buildAskContext`: `categories` (all), all
  modes/tags, counts, `cashflow_12mo`.
- `lib/features/ai/services/ai_context_gatherer.dart` — pass full directory + full current-month
  breakdown.
- `lib/features/ai/services/ai_chat_controller.dart` — pass the new args; `maxContextAmount` already
  folds summary figures.
- `lib/features/ai/domain/ai_prompts.dart` — note the fuller picture.
- Tests: extend `ai_payload_builder_test.dart` / `ai_payload_builder_extras_test.dart` for
  all-categories + counts + 12-mo.
- Privacy audit (mandatory — touches the outbound path).

### Acceptance (Phase 1)

- "How many categories do we have?" → answers the real count.
- "Tell me about fuel" (with or without `shareNames`) → answers using fuel's current-month amount
  (incl. 0) and 3-mo trend.
- `flutter analyze` clean; `flutter test` green; `@spendwise-privacy-auditor` PASS (no new data
  class leaves — same aggregates + labels, just more of them).

## Phase 2 — On-device tool-calling (answer any question)

**Goal:** let the AI answer arbitrary transaction/planning questions by pulling on-device aggregates
on demand — any category, any date range, filtered totals, what-if/planning — without ever sending
raw rows or PII.

### Protocol — provider-agnostic JSON tool-call

The app is BYO-key multi-provider (OpenAI, Anthropic, Gemini, OpenRouter, custom OpenAI-compatible).
Native function-calling APIs differ and aren't universally supported, so we use a **JSON tool-call
protocol** — the same proven pattern as the dynamic-report chart-spec: the LLM is given a tool
catalog and, when it needs data, responds with **only** a JSON tool-call object; the app parses,
executes on-device, feeds the anonymized result back, and re-requests. This works with any chat/text
provider.

**Tool-call shape:** `{"tool": "<name>", "args": {…}}` (bare or in a ```json fence — the app strips
fences and extracts the first JSON object). If the LLM's reply is not a parseable tool-call, it is
the **final answer** (rendered with `AiMarkdown`). On parse failure: one retry nudge ("respond with
only the JSON tool-call or your final answer"), then treat as final answer (never block the user).

**Round-trip:** user question → (round 1) LLM emits tool-call or answer → if tool-call, app executes
→ app appends a `tool_result` message (anonymized JSON) + "now answer the user using this data" →
(round 2) LLM emits another tool-call or answer → … up to **4 tool rounds**, then a forced "answer
now" instruction. A "Looking up your data…" indicator shows during tool rounds.

**Streaming interop:** when tool-calling is **on**, every round is **buffered (non-streaming)** —
the app parses the full reply to decide tool-call vs final answer, and shows a "Looking up your
data…" indicator during tool rounds. The final answer is rendered whole (via `AiMarkdown`) as soon
as a non-tool-call reply is parsed. Rationale: you can't know a reply is final until you have it, and
streaming an internal tool-call JSON to the user would leak the protocol. When tool-calling is **off**
(toggle), behavior is unchanged — replies stream as today. The loss of token-streaming with tools on
is an acceptable tradeoff and can be polished later (e.g. stream only a detected final round) without
changing the protocol.

### Tool catalog

All tools return **aggregates only**, with opaque labels (or real names when `shareNames` is on).
Entity references in args use opaque labels (`cat_3`); the executor resolves them to real ids via the
on-device inverse legend.

1. **`list_entities(kind)`** — `kind ∈ {category, account, mode, tag, goal, bill}`. Returns all
   active entities of that kind with labels (+ names if `shareNames`) and the total count. Fixes
   "how many categories" definitively and lets the AI discover what exists.
2. **`breakdown(group_by, from, to, kind?)`** — `group_by ∈ {category, account, mode, tag}`;
   `from`/`to` ISO dates (validated, sane range, capped at all-history). Returns
   `[{id: <label>, amount, count, pct}]` sorted desc, capped at top-20 + an `{id: "other", amount,
   count}` rollup. `kind` optional (`expense`/`income`/`all`). Handles "per-category spend in
   October", "UPI spend last week", "which account did I spend most from this year".
3. **`monthly_totals(from, to)`** — `[{month, income, expense, net}]`, capped at 24 months. Handles
   "how much did I spend last March", year-over-year.
4. **`filtered_totals(filters, from, to)`** — `filters: {amount_min?, amount_max?, category?,
   account?, mode?, tag?, kind?}` where entity filters are label references. Returns
   `{count, total, by_category: [{id, amount, count}], by_mode, by_account, by_tag}` (each capped
   top-10 + other). **No rows, no notes, no merchants.** Handles "how many transactions over 5000 in
   April", "total UPI spend last week".
5. **`budget_status(month?)`** — per-budget `{id, spent, effective, over, over_by}` for the given
   month (default current).
6. **`goals_overview()`** / **`bills_overview()`** — the anonymized aggregates already in the
   payload, exposed on-demand (so a long conversation can refresh them without resending the whole
   context).

**Planning / what-if** is the **AI's reasoning** over fetched data (goals + cashflow + category
trends) — the AI does the arithmetic. No special "planning tool" needed; the data tools suffice. (If
projection math proves unreliable, a later iteration can add a `project(assumptions)` helper tool —
out of scope here.)

### Executor — `AiToolExecutor`

Pure-ish class (takes `ReportsRepository`, `BudgetsRepository`, `GoalsRepository`,
`RecurringRepository`, the on-device legend, and `shareNames`). For a `(tool, args)`:

1. **Validate** — tool name in the allow-list; required args present; labels resolve via the inverse
   legend; dates parse and are sane (`from <= to`, range ≤ all-history, not future-biased); filter
   values in range. Reject unknown tools/labels with a structured error fed back to the LLM.
2. **Resolve** labels → real ids (on-device).
3. **Execute** a **fixed safe query** via the repositories. Hard constraints: read-only; only
   `transactions` joined to `accounts`/`categories`/`modes`/`tags`/`budgets`; never reads `note`/
   `receipt_path`/contact columns; never touches `due_*`/`ai_*`/`goals`/`recurring_items` tables
   (goals/bills via their repos as aggregates only). No LLM-authored SQL.
4. **Anonymize** results back to labels (ids → `cat_N`), or names if `shareNames`. Apply token caps.
5. Return a JSON map (the `tool_result` message body).

This mirrors `SqlGuard`'s allow/deny lists as the template; safety is in the fixed tool set, not
runtime SQL parsing.

### Chat loop — `ai_chat_controller`

After the user's question, run the tool-use loop:

- Build `requestMessages = [preamble, …history]` (preamble = system prompt with the tool catalog +
  the Phase 1 snapshot). The mention-resolver still runs on the latest user message (appended
  `[Context note]`) — it composes with tools.
- Round: request completion (streamed for the first round; buffered once a tool-call is detected).
  - If the reply parses as a tool-call: execute via `AiToolExecutor`, append a `tool_result` message
    to `requestMessages`, merge the tool's returned amounts into the stream's `sentAmounts`, show
    "Looking up your data…", loop (≤ 4 tool rounds).
  - Else: it's the final answer — gatekeeper `restore` (already applied live) + `check`; persist +
    display.
- On max rounds: append "Answer the user now using the data you have" and force a final answer.
- On executor error: feed a structured error back to the LLM (e.g. `{"error": "unknown label cat_99"}`)
  so it can self-correct, rather than failing the whole reply.

### Gatekeeper extension

`AiGatekeeper` is unchanged in structure. The per-stream gatekeeper is rebuilt with
`sentAmounts = base ∪ mentionAmounts ∪ toolResultAmounts` (the executor returns the amounts it
emitted, so a reply quoting a tool-fetched figure is accepted, not flagged as hallucinated). In
`shareNames` mode, `sentNameVocabulary` is extended with any names the tools emitted. Label restore
and all existing checks (empty/garbage, leftover-label, PII-scrub, wild-ceiling, numeric-
correspondence, hallucinated-name) are unchanged. Tool results are app-generated (trusted); the
gatekeeper's job is the LLM's **final reply**.

### Setting

On by default (privacy-safe — aggregates only). Add an "Allow AI to look up my data" toggle in AI
settings (`aiToolCalling` pref, default true). When off, the AI uses only the Phase 1 snapshot (no
tool-calls) — matches users who want a static-only AI. The system prompt is chosen based on this
toggle (with/without the tool catalog).

### Files (Phase 2)

- `lib/features/ai/tools/ai_tool_catalog.dart` (new) — tool definitions (name, description, param
  shape, result caps).
- `lib/features/ai/tools/ai_tool_executor.dart` (new) — validate + resolve + execute + anonymize.
- `lib/features/ai/tools/ai_tool_protocol.dart` (new) — parse/emit tool-call JSON from LLM text
  (strip fences, extract first JSON object, retry nudge).
- `lib/features/ai/services/ai_chat_controller.dart` — the tool-use loop (extends the existing
  `_streamReply`).
- `lib/features/ai/domain/ai_prompts.dart` — `kAskToolSystemPrompt` (catalog + protocol + "use tools
  for data, then answer; never invent figures; never claim a category doesn't exist").
- `lib/features/ai/domain/ai_gatekeeper.dart` — no structural change; wiring only.
- `lib/state/ai_providers.dart` + `lib/services/prefs_service.dart` — `aiToolCalling` pref +
  notifier (default true), reactive in `aiConfigProvider`.
- Tests: `ai_tool_executor_test.dart` (each tool: happy path, unknown label rejected, date
  validation, caps, no-PII), `ai_tool_protocol_test.dart` (parse bare/fenced/malformed), controller
  loop test (mock LlmClient returning a tool-call then an answer).
- Privacy audit (mandatory — touches the AI outbound path + a new on-device query layer).

### Acceptance (Phase 2)

- "How much did I spend on fuel last October?" → tool-call `breakdown(group_by=category,
  from=…-10-01, to=…-11-01)` → real answer.
- "How many transactions over 5000 in April?" → `filtered_totals(amount_min=5000, …)` → count +
  total (no rows).
- "Can I reach my goal by December?" → AI fetches `goals_overview` + `monthly_totals` + `breakdown`,
  reasons, answers with a projection.
- Unknown label / bad date → executor returns a structured error → LLM self-corrects or answers with
  what it has; never crashes, never sends PII.
- `flutter analyze` clean; `flutter test` green; `@spendwise-privacy-auditor` PASS (tools return
  aggregates only; no `note`/`receipt_path`/contact/`due_*`/`ai_*`/`goals`/`recurring_items`-table
  access; labels never leak the legend; tool results anonymized).

## Sequencing & file ownership

Two implementation plans, one design.

- **Plan A — Phase 1** (small): payload builder + gatherer + prompts + tests + privacy audit. Ships
  first; fixes the two reported bugs immediately.
- **Plan B — Phase 2** (large): tool catalog + executor + protocol + controller loop + setting +
  prompts + tests + privacy audit. Builds on Phase 1's full directory + inverse legend.

Track boundaries (avoid merge collisions when parallelized):
- Phase 1: `ai_payload_builder.dart`, `ai_context_gatherer.dart`, `ai_prompts.dart` (Ask prompt only),
  `ai_chat_controller.dart` (only the `_buildContext` arg wiring), Phase 1 tests.
- Phase 2: new `lib/features/ai/tools/**`, `ai_chat_controller.dart` (the `_streamReply` loop),
  `ai_prompts.dart` (new `kAskToolSystemPrompt`), `ai_gatekeeper.dart` (wiring), `ai_providers.dart`,
  `prefs_service.dart`, Phase 2 tests.
- Shared (merge-phase): `ai_chat_controller.dart`, `ai_prompts.dart`, `CHANGELOG.md`, `CLAUDE.md`.

`ai_chat_controller.dart` and `ai_prompts.dart` are touched by both phases — sequence the phases
(Phase 1 lands first), or have the supervisor reconcile in a merge phase if parallelized.

## Privacy-audit gate (mandatory, both phases)

Any change touching the AI outbound path (`ai_payload_builder.dart`), the new tool layer
(`ai_tool_executor.dart`/`ai_tool_catalog.dart`/`ai_tool_protocol.dart`), the gatekeeper, or a
PII-bearing table requires a **passing** `@spendwise-privacy-auditor` run (or the
`spendwise-privacy-audit` skill) before merge. A privacy FAIL is a hard merge blocker — no override.

## Verification (both phases)

1. `flutter analyze lib/` clean.
2. `flutter test` green (existing + new tool/protocol/payload tests).
3. `@spendwise-privacy-auditor` PASS for each phase.
4. `@spendwise-reviewer` on the full diff (DB checklist if any schema change — none expected; list-row
   rules N/A; changelog subset; no-shame tone in prompts).
5. Manual smoke: Phase 1 — count + 0-spend category + 12-mo trend answers. Phase 2 — multi-round
   tool-call for a historical/filtered/planning question; "Looking up your data…" indicator; unknown
   label self-corrects; toggle off → static-only behavior.