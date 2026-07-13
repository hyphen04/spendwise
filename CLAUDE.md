# SpendWise — Agent Instructions

> This file tells the AI agent (Claude Code) how to handle releases and DB schema changes.
> Do NOT delete or rename this file.

> **Reusable skills & project agents** live in `.claude/`. Skills (invoke when the
> task matches): `spendwise-release` (cut a release), `spendwise-db-schema-change`
> (safe Drift migration), `spendwise-privacy-audit` (verify nothing leaks to the
> AI), `spendwise-dynamic-report-add-provider` (extend the AI report safely),
> `spendwise-ai-payload-extension` (add a field to the AI outbound payload
> safely), `spendwise-custom-report` (extend the on-device, never-AI custom
> report builder). Project agents (`@spendwise-explorer` for scoped codebase
> questions, `@spendwise-privacy-auditor` to adversarially audit AI/report
> changes, `@spendwise-reviewer` to review a diff against the rules below,
> `@spendwise-supervisor` to orchestrate multi-track implementation in isolated
> worktrees). The workflows in this file are the source of truth; the
> skills/agents encode them for reuse.

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
6. **Build release APK** — arm64-only, split, and obfuscated, to keep the APK
   **as small as possible** for GitHub distribution. First ensure the size levers
   below are set, then:
   ```
   flutter build apk --release --target-platform android-arm64 --split-per-abi \
     --obfuscate --split-debug-info=build/symbols/vX.X.X
   ```
   This produces a single APK at
   `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` covering modern
   64-bit Android devices.

   > **APK size levers (always on):**
   > - **Split/arm64-only:** A plain `flutter build apk --release` produces a
   >   ~70 MB fat APK bundling `x86_64` (emulators only) and `armeabi-v7a`
   >   (legacy 32-bit) native libs. `--target-platform android-arm64` alone only
   >   filters Flutter's engine — plugin `.so` files (sqlite3, dartjni) still
   >   slip in for all ABIs. `--split-per-abi` forces per-ABI packaging so the
   >   output contains only `arm64-v8a` libs. Do NOT add `ndk { abiFilters }` in
   >   `build.gradle` — it conflicts with `--split-per-abi` and breaks the build.
   > - **R8 + resource shrinking:** the release `buildType` in
   >   `android/app/build.gradle` must have `minifyEnabled true` and
   >   `shrinkResources true` (with `proguardFiles ... 'proguard-rules.pro'`).
   >   If `proguard-rules.pro` doesn't exist, create it empty. Smoke-test the
   >   first release after enabling R8 (launch app, add tx, open a report, AI
   >   chat, export PDF) — if a reflectively-loaded plugin breaks, add a
   >   `-keep` rule rather than disabling minify.
   > - **Locale pruning:** `defaultConfig` must have `resConfigs "en"` (the app
   >   ships English-only; add another locale here if one is ever added).
   > - **Obfuscate + split debug info:** `--obfuscate` shortens Dart symbol
   >   names; `--split-debug-info=build/symbols/vX.X.X` pulls debug symbols OUT
   >   of the APK (not shipped). **Keep** the `build/symbols/vX.X.X/` directory
   >   to de-obfuscate crash stack traces — it is not committed (`build/` is
   >   gitignored).
   > - Do NOT add `--tree-shake-icons` (automatic in modern Flutter; the flag is
   >   deprecated and can break the build).

7. **Rename the APK** to a clean canonical name (recommended):
   ```
   cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk build/app/outputs/flutter-apk/app-release.apk
   ```
   The updater selects the **first `.apk` asset** on the release
   (`UpdateService.checkForUpdate` uses `endsWith('.apk')`), so the exact name
   is not required by the code — but `app-release.apk` is the project
   convention. Upload **only one** `.apk` per release so the updater can't
   pick the wrong one.

8. **Report the size** (`ls -lh build/app/outputs/flutter-apk/app-release.apk`)
   and compare to the prior release. A regression > ~1 MB without a knowingly
   added heavy dependency/asset is a release blocker — investigate
   (`--analyze-size`) before handing off.

9. **Tell the user** (do NOT upload automatically):
   > "APK is ready at `build/app/outputs/flutter-apk/app-release.apk` (~<size> MB,
   > <smaller/larger than vPrev by <delta>). Obfuscation symbols are at
   > `build/symbols/vX.X.X/` — keep them to de-obfuscate crash traces (not
   > committed).
   > Go to https://github.com/hyphen04/spendwise/releases/new, select tag vX.X.X,
   > paste the CHANGELOG entry as description, and upload the APK as an asset.
   > Use the filename `app-release.apk` and upload only one `.apk`."

10. **STOP** — do NOT create the GitHub release automatically. The user uploads the APK manually.

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

### Migration history (additive entries)

- **v14 → v15 — `custom_reports` table (additive).** `m.createTable(customReports)`
  in `onUpgrade`. New table `lib/data/db/tables/custom_reports_table.dart`:
  `id`, `name`, `specJson` (TEXT), `createdAt`, `updatedAt`. No PII (the spec is
  field references + filters only; `specJson` is a `CustomReportSpec.toJson`
  blob, never a row's contents). DAO `CustomReportsDao`. Created by the Custom
  Report builder (Track 3) — user-authored, on-device, never sent to the AI.

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

---

## AI Privacy Rules (primary invariant — never break)

> **No personal details ever leave the device.** This is the app's primary rule
> and its marketing USP ("local aggregation, remote synthesis without exposure").
> Run the `spendwise-privacy-audit` skill (or `@spendwise-privacy-auditor` agent)
> after any change to the AI outbound path, the report spec pipeline, the
> gatekeeper, or a PII-bearing table.

- **One outbound boundary.** `lib/features/ai/domain/ai_payload_builder.dart` is
  the SOLE code that constructs what leaves the device. Every AI feature routes
  outbound data through it (or, for the dynamic report, through the
  `schema_metadata` blob + opaque labels). Never build a prompt body from raw
  rows, real names, notes, or amounts anywhere else. Use the
  `spendwise-ai-payload-extension` skill to add a field end-to-end safely. The
  chat payload now sends **all** categories/modes/tags (including 0-spend
  entities, not just the top-5 spend categories) plus `category_count` /
  `mode_count` / `tag_count` scalars and a 12-month cashflow series — privacy is
  unchanged (same aggregates + opaque labels, just more of them; the name↔label
  legend still leaves only with `shareNames`).
- **On-device restore + validation.** `AiGatekeeper` runs on **every** LLM text
  surface (chat replies, polished insights, digest polish, report `title`/
  `caption`/`narrativeSeed`, report narrative) to restore opaque labels + scrub
  PII + sanity-check numbers — **no surface bypasses the gatekeeper.** In
  addition to the existing empty/garbage, leftover-label, PII-scrub, and
  `>max*10` numeric checks, the gatekeeper now does:
  - **Numeric correspondence** — parses currency-ish numbers from the reply and
    flags any that are neither within tolerance of a `sentAmounts` entry (the
    rounded figures the payload sent) nor a sane derived figure
    (≤ `maxContextAmount * 1.5`). Catches hallucinated figures.
  - **Hallucinated-name detection** (only when `shareNames` is on) — flags
    category/account/mode/tag/goal/bill names in the reply that are not in the
    `sentNameVocabulary` the payload sent.
  The insight/digest polish paths run their LLM reply through `AiGatekeeper`
  (built from the `InsightAnonymizer` legend) for `restore` **and** `check` —
  adding PII-scrub + numeric sanity to polish/digest for the first time.
  `InsightAnonymizer` stays as the legend builder; its direct `restore` call
  sites are replaced by the gatekeeper (one legend mechanic, one validator).
  The legend map never leaves the device.
- **On-device mention resolution (the name↔label bridge).** Because the app is
  anonymize-by-default, the LLM sees only opaque labels (`cat_0`…) and cannot
  map a name the user *types* ("fuel") to a label — so it would wrongly claim
  "no category named fuel." `AiMentionResolver` (`lib/features/ai/domain/
  ai_mention_resolver.dart`) bridges this **on-device**: it scans the user's
  **own** message for category/account/mode/tag names that match the on-device
  directory (`AiMentionData` from `gatherAiContextExtras`'s sibling
  `gatherAiMentionData` — reads only `categories`/`accounts`/`modes`/`tags`,
  never `due_*`/`ai_*`/`goals`/`recurring_items`, never `note`/`receipt_path`/
  contact columns) and appends a `[Context note: …]` to that user message **as
  sent to the LLM only — never persisted to the DB, never shown in the UI.**
  The note re-uses only (a) the name the user themselves typed, (b) the label
  if it is already in the context legend, and (c) the current-month aggregate
  amount. The legend/directory for entities the user did **not** mention never
  leaves. The note's figures/names are merged into that stream's `AiGatekeeper`
  `sentAmounts` (and `sentNameVocabulary` when `shareNames` is on) so a reply
  quoting them is accepted, not flagged. This is **not** a second outbound
  boundary and introduces no new real names or aggregates beyond what the user
  named — `AiPayloadBuilder` remains the sole constructor of the aggregate
  payload; the resolver only re-uses the user's own words + labels already in
  context. `ai_chat_controller._resolveLastUserMessage` is the only call site.
- **API key.** Stored in `flutter_secure_storage` via `SecureStorageService`
  (NOT SharedPreferences). Read on demand, never logged, never held in
  long-lived Riverpod state.
- **Never sent, in any mode:** transaction `note`s; `due_contacts`
  name/phone/phones/photoPath/deviceContactId/defaultNote; `due_entries` /
  `due_settlements` notes; receipt paths; raw rows; real amounts; real
  category/account/mode/tag/**goal**/**bill** names (anonymized to
  `cat_0`/`acc_1`/`mode_1`/`tag_1`/`goal_N`/`bill_N` by default; real names are
  an opt-in toggle that attaches a `legend`, still restored on-device).
- **Goals + recurring bills reach the AI as anonymized aggregates ONLY.** They
  are sent as `goal_N` (target/saved/pct/`months_left?`/`monthly_commitment?`)
  and `bill_N` (amount/cadence/`next_due_in_days`/source) — **no names, no
  notes, no icons.** The `goal_N`/`bill_N` → id legend is recorded on-device and
  embedded in the outbound JSON **only** when `shareNames` is on; otherwise it
  never leaves. This relaxes the earlier "stay on-device only" line for goals
  and recurring bills — they now contribute aggregates to the AI, but the
  `goals` and `recurring_items` **tables** are still not listed in
  `schema_metadata` (see dynamic-report rules below); only the anonymized
  aggregate fields flow through `AiPayloadBuilder`.
- **AI reply rendering.** AI chat replies and report narratives now render with
  `flutter_markdown` via `AiMarkdown` (`lib/features/ai/widgets/ai_markdown.dart`)
  — tables and fenced code blocks are supported, so the ask/report prompts may
  allow rich output. `ChangelogMarkdown` (`lib/app/widgets/changelog_markdown.dart`)
  remains the changelog / What's New parser with its existing supported-subset
  rules (unchanged) — do not route changelog text through `AiMarkdown` or relax
  the changelog format rules.

### Dynamic report (`lib/features/ai/dynamic_report/`)

The AI Report is spec-driven: the LLM emits a `ChartSpec` JSON naming a
`DataProvider`; the app executes it on-device and renders with fl_chart.

- **The LLM sees only** `schema_metadata.dart` (a frozen, hand-authored,
  PII-stripped schema blob — never auto-generated from live schema) + opaque
  labels. It **never** sees raw rows or real amounts. Queries execute on-device;
  **results are never sent back.**
- **`schema_metadata.dart` must never list** the PII tables `due_contacts`,
  `due_entries`, `due_settlements`, `ai_threads`, `ai_messages`, or the PII columns
  `note`, `receipt_path`/`receiptPath`, `phone`, `phones`, `photo_path`/`photoPath`,
  `device_contact_id`/`deviceContactId`. The `recurring_items` and `goals`
  **tables** are also deliberately kept out of `schema_metadata` — the LLM never
  authors SQL over them. Their data reaches the AI only as anonymized aggregates
  (`bill_N`/`goal_N`) through `AiPayloadBuilder` (see above), never through the
  report spec pipeline.
- **Named providers are the safe default** — they reuse existing repository
  methods. **`customSql` (LLM-authored SQL) is opt-in, off by default**, gated by
  the `aiCustomSql` setting, and routed through `sql_guard.dart` (Stage B):
  read-only, single-statement, keyword blocklist, table allow-list (blocks
  `due_*` / `ai_*`), column blocklist (blocks the PII columns above),
  auto-LIMIT, 10s timeout. Residual risk (semantically-wrong-but-valid SQL) is
  accepted for the opt-in advanced path; named providers cover common cases.
- **The Dart `SpecValidator` is the source of truth** for JSON shape, not
  provider `response_format`/`responseSchema` enforcement (uneven across
  providers). One retry on failure, then default-spec fallback so the report is
  never empty.
- **Extending the report:** use the `spendwise-dynamic-report-add-provider` skill
  to add a named provider end-to-end (enum + executor + validator allow-list +
  shot example + test). Prefer it over `customSql`.

---

## Multi-track implementation

Large changes (e.g. the AI+Reports overhaul) are split into **file-disjoint
tracks** implemented in parallel git worktrees and coordinated by the
`@spendwise-supervisor` agent. The supervisor dispatches track agents, holds the
file-ownership boundaries below, runs `@spendwise-reviewer` +
`@spendwise-privacy-auditor` + `flutter analyze lib/` + `flutter test` per
track, reconciles shared files in a final merge phase, and signals merge-ready
**only** on green + privacy PASS.

### Track file-ownership boundaries (the conflict-avoidance contract)

- **Track 1 — AI core:** `pubspec.yaml`, `lib/features/ai/domain/**`,
  `lib/features/ai/services/**`, `lib/features/ai/presentation/ai_chat_screen.dart`
  + `ai_report_screen.dart`, new `lib/features/ai/widgets/ai_markdown.dart`.
- **Track 2 — Smart Insights fullscreen viewer:**
  `lib/features/ai/presentation/ai_insights_section.dart`,
  `lib/features/ai/widgets/ai_insight_card.dart`, new
  `lib/features/ai/presentation/insight_viewer_screen.dart` +
  `lib/features/ai/widgets/insight_status_page.dart`, the `/ai/insights` route.
- **Track 3 — Reports hub + Custom Report builder:**
  `lib/features/reports/reports_screen.dart`,
  `lib/features/reports/widgets/report_card.dart`, new
  `lib/features/reports/custom/**`, new `custom_reports` table + DAO + migration,
  `lib/state/custom_report_providers.dart`, custom-report routes.
- **Track 4 — Tooling:** `.claude/**`, `CLAUDE.md`.
- **Shared (merge-phase only, supervisor-reconciled):** `router.dart`,
  `pubspec.yaml`, `CLAUDE.md`, `CHANGELOG.md`. Track agents report router routes
  as Dart snippets in their result instead of editing `router.dart`.

### Rules

- **Worktree per track.** Each track runs in its own isolated git worktree so
  tracks don't collide; the supervisor merges at the end.
- **Privacy gate (mandatory).** Any change touching the AI outbound path
  (`ai_payload_builder.dart`), the gatekeeper (`ai_gatekeeper.dart`),
  `schema_metadata.dart`, `sql_guard.dart`, or a PII-bearing table
  (`due_*` / `ai_*` / `goals` / `recurring_items`) requires a **passing**
  `@spendwise-privacy-auditor` run (or the `spendwise-privacy-audit` skill)
  before merge. A privacy FAIL is a hard merge blocker — no override.
- **Tooling is the supervisor's.** Track agents do not run `flutter` / `dart` /
  `pub` / `build_runner` unless explicitly permitted; the supervisor runs all
  tooling after merge so the result is reproducible. (Exception: Track 3's new
  `custom_reports` table needs generated `.g.dart` — the supervisor runs
  `build_runner` in the merge phase.)
- **No auto-release.** The supervisor stops at merge-ready; the user cuts the
  release via the Release Workflow above.

### Hooks

`.claude/settings.local.json` installs two advisory/guard hooks:
- **PostToolUse** on `Edit|Write` to `lib/features/ai/domain/ai_payload_builder.dart`
  / `ai_gatekeeper.dart` / `schema_metadata.dart` / `sql_guard.dart` or any
  `lib/data/db/tables/(due_*|ai_*|goals_table|recurring_items_table)*` → prints a
  reminder to run `spendwise-privacy-audit` before committing (advisory,
  non-blocking; `.claude/hooks/privacy-reminder.sh`).
- **PreToolUse** on `Bash` matching `git commit` → runs `flutter analyze lib/`
  and aborts the commit on error (`.claude/hooks/precommit-analyze.sh`).
