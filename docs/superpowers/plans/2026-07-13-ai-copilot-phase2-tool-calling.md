# AI Copilot Phase 2 — On-Device Tool-Calling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Prerequisite:** Plan A (Phase 1) is merged — `buildAskContext` already emits all categories/modes/tags + counts + `cashflow_12mo`, and the controller gathers `mentionData` (full directory) before building the payload. This plan builds on that full directory + the on-device legend.

**Goal:** Let the AI answer *any* transaction/planning question by pulling on-device aggregates on demand (any category, any date range, filtered totals, goal feasibility) via a provider-agnostic JSON tool-call protocol — without ever sending raw rows, notes, contacts, or real names (unless `shareNames` is on).

**Architecture:** The LLM is given a tool catalog in its system prompt. When it needs data, it replies with **only** a JSON tool-call object; the app parses it, executes a **fixed, named query** on-device via `AiToolExecutor`, feeds the anonymized result back, and re-requests — up to 4 rounds. The round loop lives in a pure, injectable `AiToolRunner` (unit-testable with a fake `LlmClient`); the controller delegates to it when the `aiToolCalling` toggle is on, and falls back to today's streaming path when off. Tool results are aggregates only with opaque labels (or real names when `shareNames`); the gatekeeper's `sentAmounts`/`sentNameVocabulary` are extended with the tool-emitted figures/names so a reply quoting a fetched figure is accepted, not flagged.

**Tech Stack:** Flutter, Riverpod, Drift (`NativeDatabase.memory()` for tests), `flutter_test`. No new deps. No DB schema change.

## Global Constraints

- **Privacy invariant (primary, unchanged):** only aggregates + anonymized labels leave the device. Never: transaction `note`s; `due_contacts` name/phone/phones/photoPath/deviceContactId/defaultNote; `due_entries`/`due_settlements` notes; receipt paths; raw transaction rows; real category/account/mode/tag/goal/bill names (anonymized to `cat_0`/`acc_1`/`mode_1`/`tag_1`/`goal_N`/`bill_N`; real names only with the opt-in `shareNames` toggle, restored on-device). `due_*`/`ai_*` tables and PII columns (`note`, `receipt_path`, `phone`, `phones`, `photo_path`, `device_contact_id`) are hard-blocked — no tool reads them. `goals`/`recurring_items` reach the AI **only** as the anonymized aggregates already in the payload (`goal_N`/`bill_N`); tools never query those tables. **Tools are named fixed queries, not LLM-authored SQL** — safety is in the tool set, mirroring `SqlGuard`.
- **TDD:** write the failing test first, watch it fail, implement, watch it pass, commit.
- **Tooling:** run `flutter analyze lib/ test/` and `flutter test` per task. The precommit hook runs `flutter analyze lib/` on `git commit`.
- **Commit policy:** commit only when the user asks. If on `main`, branch first (`git checkout -b ai-copilot-phase2`). Each task's commit is conditional on the user having asked for commits.
- **Provider-agnostic:** use `LlmClient.complete(...)` (non-streaming) for every tool round. `LlmClient` is `abstract` with `complete(AiConfig, List<ChatMessage>, {int? maxTokens, bool json})` → `Future<String>` and `stream(...)`. A fake `implements LlmClient` in tests.
- **Entity record types (existing):** `AiEntityName = ({String id, String name})` (from `ai_mention_resolver.dart`); `GoalSummary`/`BillSummary` (from `ai_payload_builder.dart`); `CategoryTotal`/`ModeTotal`/`TagTotal`/`MonthTotal` (from `report_models.dart`).

---

## File Structure

- **Modify** `lib/features/ai/domain/ai_payload_builder.dart` — expose `labelToId` from `_Labeler`; include it in `AiContext`.
- **Modify** `lib/features/ai/domain/ai_context.dart` — extend the `AiContext` record with `labelToId`.
- **Modify** `lib/data/repositories/reports_repository.dart` — add `monthlyTotalsInRange({from, to})` and `filteredTotals({...})` (fixed safe queries; no notes / no `due_*` / `ai_*`).
- **Create** `lib/features/ai/tools/ai_tool_protocol.dart` — parse an LLM reply into a tool-call or final answer; emit the tool-call JSON shape; the retry nudge.
- **Create** `lib/features/ai/tools/ai_tool_catalog.dart` — the 6 tool definitions (name, description, arg shape, result caps) + the catalog string for the prompt.
- **Create** `lib/features/ai/tools/ai_tool_executor.dart` — validate → resolve labels → execute fixed query → anonymize → return `{body, amounts, names, isError}`.
- **Create** `lib/features/ai/tools/ai_tool_runner.dart` — the buffered round loop (injectable `LlmClient` + `AiToolExecutor`); unit-testable.
- **Modify** `lib/features/ai/domain/ai_prompts.dart` — add `kAskToolSystemPrompt` (catalog + protocol + rules).
- **Modify** `lib/features/ai/services/ai_chat_controller.dart` — store `_mentionData`/`_labelToId`/`_goals`/`_bills`/`_shareNames`; in `_streamReply`, branch on the `aiToolCalling` toggle: on → build `AiToolExecutor` + `AiToolRunner` + `kAskToolSystemPrompt` and run the loop; off → today's streaming path.
- **Modify** `lib/services/prefs_service.dart` — add `aiToolCalling` (default **true**) + setter.
- **Modify** `lib/state/ai_providers.dart` — add `aiToolCallingProvider` (mirror `aiShareNamesProvider`).
- **Modify** `lib/features/ai/presentation/ai_settings_section.dart` — add the "Allow AI to look up my data" toggle.
- **Create** tests: `test/ai/ai_tool_protocol_test.dart`, `test/ai/ai_tool_executor_test.dart`, `test/ai/ai_tool_runner_test.dart`, plus extend `test/ai/ai_payload_builder_test.dart` for `labelToId` and add `test/data/reports_repository_tool_test.dart` for the new repo methods.
- **No DB schema change.**

---

## Task 1: Expose `labelToId` from the builder (TDD)

The executor must resolve an LLM-supplied label (`cat_3`) back to the real category id to run its fixed queries. The `_Labeler` already holds `id → label` maps internally; expose the inverse as `labelToId` and surface it through `AiContext`. This is an **on-device-only** addition — the outbound JSON is unchanged. (Touches `ai_payload_builder.dart` → privacy-audit gate applies.)

**Files:**
- Modify: `lib/features/ai/domain/ai_context.dart`
- Modify: `lib/features/ai/domain/ai_payload_builder.dart` (`_Labeler` + both build methods' return)
- Test: `test/ai/ai_payload_builder_test.dart`

**Interfaces:**
- Produces: `AiContext` gains `Map<String, String> labelToId` (label like `cat_0` → real id). `_Labeler.labelToId` getter inverts all six `_*Keys` maps.

- [ ] **Step 1: Write the failing test**

Add to `test/ai/ai_payload_builder_test.dart` (new group):

```dart
group('AiPayloadBuilder — labelToId (Phase 2)', () {
  final b = AiPayloadBuilder();

  test('labelToId maps every emitted label back to its real entity id', () {
    final ctx = b.buildAskContext(
      summary: _summary(topCats: const []),
      budgets: const [],
      cashflow: const [],
      period: '2026-07',
      allCategories: const [(id: 'c-fuel', name: 'Fuel'), (id: 'c-food', name: 'Food')],
      allModes: const [(id: 'm-upi', name: 'UPI')],
      allTags: const [(id: 't-work', name: 'work')],
      accountBalances: const [(id: 'a1', name: 'HDFC', balance: 1000)],
      goals: const [
        (id: 'g1', name: 'Phone', target: 60000, saved: 15000, monthsLeft: 10, monthlyCommitment: 4500),
      ],
      recurringBills: const [
        (id: 'b1', name: 'Netflix', amount: 649, cadence: 'monthly', nextDueInDays: 5, source: 'manual'),
      ],
    );
    // The JSON's category labels (cat_N) must round-trip to the real ids.
    final cats = (ctx.json['categories']! as List).cast<Map>();
    for (final c in cats) {
      final label = c['id'] as String;
      expect(ctx.labelToId[label], isNotNull);
      expect(ctx.labelToId[label]!.startsWith('c-'), isTrue);
    }
    expect(ctx.labelToId.values, containsAll(const ['m-upi', 't-work', 'a1', 'g1', 'b1']));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ai/ai_payload_builder_test.dart`
Expected: FAIL — `labelToId` not defined on `AiContext` (compile error: the record has no `labelToId` field).

- [ ] **Step 3: Implement**

In `lib/features/ai/domain/ai_context.dart`, extend the typedef:

```dart
/// The result of building an AI context payload.
///
/// - [json]: the map that gets JSON-encoded and sent to the LLM. It contains
///   only anonymized aggregations (opaque rank keys like `cat_0`); a `legend`
///   key is embedded in [json] **only** when `shareNames` is true.
/// - [legend]: the full `label → real-name` map, **always** populated
///   internally (regardless of `shareNames`). It never leaves the device — it
///   is returned to the caller so [AiGatekeeper] can restore real names in the
///   LLM's reply on-device. When `shareNames` is true, [legend] is the same
///   map that was embedded in [json]['legend'].
/// - [labelToId]: the inverse `label → real-id` map (e.g. `cat_0 → <category
///   id>`), **always** populated internally. Never leaves the device. Used by
///   the on-device tool executor to resolve labels the LLM emits back to the
///   real ids needed to run its fixed queries.
typedef AiContext =
    ({Map<String, Object?> json, Map<String, String> legend, Map<String, String> labelToId});
```

In `lib/features/ai/domain/ai_payload_builder.dart`, add a `labelToId` getter to `_Labeler` (after the `bill(...)` method, before `_key`):

```dart
  /// Inverse of all six `_*Keys` maps: `label → real id`. On-device only; the
  /// executor uses it to resolve labels the LLM emits back to real ids.
  Map<String, String> get labelToId {
    final out = <String, String>{};
    for (final e in _catKeys.entries) {
      out[e.value] = e.key;
    }
    for (final e in _accKeys.entries) {
      out[e.value] = e.key;
    }
    for (final e in _modeKeys.entries) {
      out[e.value] = e.key;
    }
    for (final e in _tagKeys.entries) {
      out[e.value] = e.key;
    }
    for (final e in _goalKeys.entries) {
      out[e.value] = e.key;
    }
    for (final e in _billKeys.entries) {
      out[e.value] = e.key;
    }
    return out;
  }
```

Update both return sites to include `labelToId: labeler.labelToId,`. In `buildAskContext` (the `return ( json: {...}, legend: labeler.legend );` block) change to:

```dart
    return (
      json: {
        // … unchanged map contents …
        if (shareNames && labeler.legend.isNotEmpty) 'legend': labeler.legend,
      },
      legend: labeler.legend,
      labelToId: labeler.labelToId,
    );
```

Do the same in `buildReportContext`'s return (add `labelToId: labeler.labelToId,`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ai/ai_payload_builder_test.dart`
Expected: PASS (all existing + new `labelToId` test green). If other files destructure `AiContext` as a 2-field record, the analyzer will flag them — fix by ignoring the new field (they use `ctx.json`/`ctx.legend` by name, so they're fine).

- [ ] **Step 5: Commit (if the user has asked for commits)**

```bash
git add lib/features/ai/domain/ai_context.dart lib/features/ai/domain/ai_payload_builder.dart test/ai/ai_payload_builder_test.dart
git commit -m "feat(ai): expose on-device labelToId from AiPayloadBuilder for tool resolution (Phase 2)"
```

---

## Task 2: New fixed repo queries — `monthlyTotalsInRange` + `filteredTotals` (TDD)

The `monthly_totals` tool (any range) and `filtered_totals` tool need repo methods that don't exist yet. These are **fixed, parameterized, read-only** queries over `transactions` joined to `accounts`/`categories`/`modes`/`transaction_tags`/`tags`. They never select `note` or `receipt_path`, never touch `due_*`/`ai_*`/`goals`/`recurring_items`.

**Files:**
- Modify: `lib/data/repositories/reports_repository.dart`
- Test: `test/data/reports_repository_tool_test.dart` (new)

**Interfaces:**
- Produces:
  - `Future<List<MonthTotal>> monthlyTotalsInRange({required String from, required String to})` — one row per `yyyy-MM` in `[from, to)`, income/expense/net.
  - `Future<({int count, double total, List<({String id, String name, double amount, int count})> byCategory, ...byMode, ...byAccount, ...byTag})> filteredTotals({required String from, required String to, String? kind, String? accountId, String? categoryId, String? modeId, String? tagId, double? amountMin, double? amountMax})` — each `by*` list sorted desc, capped top-10 + an `other` rollup is the executor's job (the repo returns all; the executor caps). `name` here is the real name (the executor anonymizes).

- [ ] **Step 1: Write the failing tests**

Create `test/data/reports_repository_tool_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/reports_repository.dart';

void main() {
  late AppDatabase db;
  late ReportsRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get(); // force creation + seed defaults
    repo = ReportsRepository(db);

    // Seed one account, two categories, one mode.
    await db.into(db.accounts).insert(
            AccountsCompanion.insert(id: 'a1', name: 'HDFC', icon: '💳', color: '#059669', createdAt: 0, updatedAt: 0));
    await db.into(db.categories).insert(
            CategoriesCompanion.insert(id: 'c-fuel', name: 'Fuel', icon: '⛽', createdAt: 0, updatedAt: 0));
    await db.into(db.categories).insert(
            CategoriesCompanion.insert(id: 'c-food', name: 'Food', icon: '🍔', createdAt: 0, updatedAt: 0));
    await db.into(db.modes).insert(
            ModesCompanion.insert(id: 'm-upi', name: 'UPI', icon: '📱', createdAt: 0, updatedAt: 0));

    // October 2026 expenses.
    Future<void> tx(String id, double amount, String cat, String day) async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        amount: amount,
        transactionDate: '2026-10-${day}T10:00:00.000',
        accountId: 'a1',
        categoryId: cat,
        modeId: 'm-upi',
        kind: const Value('expense'),
        createdAt: 0,
        updatedAt: 0,
      ));
    }

    await tx('tx1', 2000, 'c-fuel', '05');
    await tx('tx2', 500, 'c-fuel', '06'); // filtered out by amount_min=1000
    await tx('tx3', 3000, 'c-food', '07');
    // September 2026 (outside the October range).
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'txSep',
      amount: 9999,
      transactionDate: '2026-09-15T10:00:00.000',
      accountId: 'a1',
      categoryId: 'c-fuel',
      modeId: 'm-upi',
      kind: const Value('expense'),
      createdAt: 0,
      updatedAt: 0,
    ));
  });

  tearDown(() => db.close());

  test('monthlyTotalsInRange returns per-month income/expense for the window', () async {
    final rows = await repo.monthlyTotalsInRange(
      from: '2026-09-01T00:00:00.000',
      to: '2026-11-01T00:00:00.000',
    );
    expect(rows.length, 2); // Sep + Oct
    final sep = rows.firstWhere((m) => m.month == 9);
    final oct = rows.firstWhere((m) => m.month == 10);
    expect(sep.expense, 9999);
    expect(oct.expense, 5500); // 2000 + 500 + 3000
    expect(oct.income, 0);
  });

  test('filteredTotals: count + total with amount_min filter, byCategory breakdown', () async {
    final r = await repo.filteredTotals(
      from: '2026-10-01T00:00:00.000',
      to: '2026-11-01T00:00:00.000',
      kind: 'expense',
      amountMin: 1000,
    );
    expect(r.count, 2); // tx1 (2000) + tx3 (3000); tx2 (500) excluded
    expect(r.total, 5000);
    final byCat = r.byCategory;
    final food = byCat.firstWhere((c) => c.id == 'c-food');
    final fuel = byCat.firstWhere((c) => c.id == 'c-fuel');
    expect(food.amount, 3000);
    expect(food.count, 1);
    expect(fuel.amount, 2000);
    expect(fuel.count, 1);
  });

  test('filteredTotals: categoryId filter narrows to one category', () async {
    final r = await repo.filteredTotals(
      from: '2026-10-01T00:00:00.000',
      to: '2026-11-01T00:00:00.000',
      kind: 'expense',
      categoryId: 'c-fuel',
    );
    expect(r.count, 2); // tx1 + tx2
    expect(r.total, 2500);
  });

  test('filteredTotals reads no notes — amount_min/max use amount only', () async {
    // A transaction with a PII note still filters purely on amount/date/kind.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'txNote',
      amount: 4000,
      transactionDate: '2026-10-08T10:00:00.000',
      accountId: 'a1',
      categoryId: 'c-food',
      modeId: 'm-upi',
      kind: const Value('expense'),
      note: const Value('secret note with phone 9876543210'),
      createdAt: 0,
      updatedAt: 0,
    ));
    final r = await repo.filteredTotals(
      from: '2026-10-01T00:00:00.000',
      to: '2026-11-01T00:00:00.000',
      kind: 'expense',
      amountMin: 3500,
    );
    expect(r.count, 1);
    expect(r.total, 4000);
    // The note is never returned by filteredTotals (no note field in the result).
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/reports_repository_tool_test.dart`
Expected: FAIL — `monthlyTotalsInRange` / `filteredTotals` not defined (compile error).

- [ ] **Step 3: Implement the repo methods**

Append to `lib/data/repositories/reports_repository.dart` (inside the class):

```dart
  /// Per-month income/expense over `[from, to)` in a single grouped query.
  /// Used by the AI tool layer's `monthly_totals` tool. Reads only `kind`,
  /// `amount`, `transaction_date` — never `note` or `receipt_path`, never
  /// `due_*` / `ai_*` / `goals` / `recurring_items`.
  Future<List<MonthTotal>> monthlyTotalsInRange({
    required String from,
    required String to,
  }) async {
    final rows = await _db.customSelect(
      "SELECT substr(transaction_date,1,7) AS ym, "
      "COALESCE(SUM(CASE WHEN kind='income' THEN amount ELSE 0 END),0) AS income, "
      "COALESCE(SUM(CASE WHEN kind='expense' THEN amount ELSE 0 END),0) AS expense "
      "FROM transactions "
      "WHERE kind IN ('income','expense') "
      "AND transaction_date >= ? AND transaction_date < ? "
      "GROUP BY ym ORDER BY ym",
      variables: [Variable.withString(from), Variable.withString(to)],
    ).get();
    return rows.map((r) {
      final ym = r.data['ym'] as String;
      final parts = ym.split('-');
      return MonthTotal(
        year: int.parse(parts[0]),
        month: int.parse(parts[1]),
        income: (r.data['income'] as num).toDouble(),
        expense: (r.data['expense'] as num).toDouble(),
      );
    }).toList();
  }

  /// Aggregate count + total over `[from, to)` with optional filters, plus
  /// per-group breakdowns by category / mode / account / tag. Used by the AI
  /// tool layer's `filtered_totals` tool. Fixed, parameterized, read-only.
  /// Never selects `note` or `receipt_path`; never touches `due_*` / `ai_*` /
  /// `goals` / `recurring_items`. `name` fields are real names — the executor
  /// anonymizes them to labels (or keeps them when `shareNames` is on).
  Future<({
    int count,
    double total,
    List<({String id, String name, double amount, int count})> byCategory,
    List<({String id, String name, double amount, int count})> byMode,
    List<({String id, String name, double amount, int count})> byAccount,
    List<({String id, String name, double amount, int count})> byTag,
  })> filteredTotals({
    required String from,
    required String to,
    String? kind,
    String? accountId,
    String? categoryId,
    String? modeId,
    String? tagId,
    double? amountMin,
    double? amountMax,
  }) async {
    final vars = <Variable>[Variable.withString(from), Variable.withString(to)];
    final where = <String>[
      "t.transaction_date >= ?",
      "t.transaction_date < ?",
    ];
    if (kind != null) {
      where.add("t.kind = ?");
      vars.add(Variable.withString(kind));
    }
    if (accountId != null) {
      where.add("t.account_id = ?");
      vars.add(Variable.withString(accountId));
    }
    if (categoryId != null) {
      where.add("t.category_id = ?");
      vars.add(Variable.withString(categoryId));
    }
    if (modeId != null) {
      where.add("t.mode_id = ?");
      vars.add(Variable.withString(modeId));
    }
    if (amountMin != null) {
      where.add("t.amount >= ?");
      vars.add(Variable.withReal(amountMin));
    }
    if (amountMax != null) {
      where.add("t.amount <= ?");
      vars.add(Variable.withReal(amountMax));
    }
    final whereClause = where.join(' AND ');

    // tagId filter requires joining transaction_tags — handled in the tag
    // grouping query below. For count/total/by_* we apply it as an IN filter.
    String tagFilterClause = '';
    if (tagId != null) {
      tagFilterClause = " AND t.id IN (SELECT transaction_id FROM transaction_tags WHERE tag_id = ?)";
      vars.add(Variable.withString(tagId));
    }

    final countRow = await _db.customSelect(
      "SELECT COUNT(*) AS cnt, COALESCE(SUM(t.amount),0) AS total "
      "FROM transactions t WHERE $whereClause $tagFilterClause",
      variables: vars,
    ).getSingle();
    final count = (countRow.data['cnt'] as int?) ?? 0;
    final total = (countRow.data['total'] as num).toDouble();

    List<({String id, String name, double amount, int count})> group(
        String join, String idCol, String nameCol, String table) {
      // Re-build vars for this grouped query (same filters).
      final gvars = <Variable>[Variable.withString(from), Variable.withString(to)];
      if (kind != null) gvars.add(Variable.withString(kind));
      if (accountId != null) gvars.add(Variable.withString(accountId));
      if (categoryId != null) gvars.add(Variable.withString(categoryId));
      if (modeId != null) gvars.add(Variable.withString(modeId));
      if (amountMin != null) gvars.add(Variable.withReal(amountMin));
      if (amountMax != null) gvars.add(Variable.withReal(amountMax));
      String extra = '';
      if (tagId != null) {
        extra = " AND t.id IN (SELECT transaction_id FROM transaction_tags WHERE tag_id = ?)";
        gvars.add(Variable.withString(tagId));
      }
      final rows = _db.customSelect(
        "SELECT $idCol AS id, $nameCol AS name, "
        "COALESCE(SUM(t.amount),0) AS amount, COUNT(*) AS cnt "
        "FROM transactions t $join WHERE $whereClause$extra "
        "GROUP BY $idCol ORDER BY amount DESC",
        variables: gvars,
      );
      // Note: run synchronously below via await in caller; this helper returns
      // a Future. (See usage in the returned record.)
      throw UnimplementedError(); // placeholder replaced below
    }

    // The helper above can't be async-in-record cleanly, so inline the four
    // grouped queries directly.
    final byCatRows = await _db.customSelect(
      "SELECT t.category_id AS id, COALESCE(c.name,'Unknown') AS name, "
      "COALESCE(SUM(t.amount),0) AS amount, COUNT(*) AS cnt "
      "FROM transactions t LEFT JOIN categories c ON t.category_id = c.id "
      "WHERE $whereClause $tagFilterClause "
      "GROUP BY t.category_id ORDER BY amount DESC",
      variables: vars,
    ).get();
    final byCategory = byCatRows
        .map((r) => (
              id: r.data['id'] as String? ?? '',
              name: r.data['name'] as String? ?? '',
              amount: (r.data['amount'] as num).toDouble(),
              count: (r.data['cnt'] as int?) ?? 0,
            ))
        .toList();

    final byModeRows = await _db.customSelect(
      "SELECT t.mode_id AS id, COALESCE(m.name,'Unknown') AS name, "
      "COALESCE(SUM(t.amount),0) AS amount, COUNT(*) AS cnt "
      "FROM transactions t LEFT JOIN modes m ON t.mode_id = m.id "
      "WHERE $whereClause $tagFilterClause "
      "GROUP BY t.mode_id ORDER BY amount DESC",
      variables: vars,
    ).get();
    final byMode = byModeRows
        .map((r) => (
              id: r.data['id'] as String? ?? '',
              name: r.data['name'] as String? ?? '',
              amount: (r.data['amount'] as num).toDouble(),
              count: (r.data['cnt'] as int?) ?? 0,
            ))
        .toList();

    final byAccRows = await _db.customSelect(
      "SELECT t.account_id AS id, COALESCE(a.name,'Unknown') AS name, "
      "COALESCE(SUM(t.amount),0) AS amount, COUNT(*) AS cnt "
      "FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id "
      "WHERE $whereClause $tagFilterClause "
      "GROUP BY t.account_id ORDER BY amount DESC",
      variables: vars,
    ).get();
    final byAccount = byAccRows
        .map((r) => (
              id: r.data['id'] as String? ?? '',
              name: r.data['name'] as String? ?? '',
              amount: (r.data['amount'] as num).toDouble(),
              count: (r.data['cnt'] as int?) ?? 0,
            ))
        .toList();

    final byTagRows = await _db.customSelect(
      "SELECT tt.tag_id AS id, COALESCE(tg.name,'Unknown') AS name, "
      "COALESCE(SUM(t.amount),0) AS amount, COUNT(*) AS cnt "
      "FROM transactions t "
      "JOIN transaction_tags tt ON tt.transaction_id = t.id "
      "JOIN tags tg ON tg.id = tt.tag_id "
      "WHERE $whereClause "
      "GROUP BY tt.tag_id ORDER BY amount DESC",
      variables: vars,
    ).get();
    final byTag = byTagRows
        .map((r) => (
              id: r.data['id'] as String? ?? '',
              name: r.data['name'] as String? ?? '',
              amount: (r.data['amount'] as num).toDouble(),
              count: (r.data['cnt'] as int?) ?? 0,
            ))
        .toList();

    return (
      count: count,
      total: total,
      byCategory: byCategory,
      byMode: byMode,
      byAccount: byAccount,
      byTag: byTag,
    );
  }
```

> **Note:** remove the stub `group(...)` helper and its `throw UnimplementedError()` — the four inlined queries replace it. (It is shown only to document the shape; the inlined queries are the real implementation. Do not leave the stub in the file.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/reports_repository_tool_test.dart`
Expected: PASS (all 4 tests green).

Run: `flutter test` (full suite)
Expected: no regressions.

- [ ] **Step 5: Commit (if the user has asked for commits)**

```bash
git add lib/data/repositories/reports_repository.dart test/data/reports_repository_tool_test.dart
git commit -m "feat(reports): monthlyTotalsInRange + filteredTotals fixed queries for AI tools (Phase 2)"
```

---

## Task 3: Tool protocol — parse LLM reply into tool-call vs final answer (TDD)

Pure Dart, no IO. Parses an LLM reply: if it contains a JSON object `{"tool": "...", "args": {...}}` (bare or in a ```json fence), treat it as a tool-call; otherwise it's the final answer. Provides the retry nudge string.

**Files:**
- Create: `lib/features/ai/tools/ai_tool_protocol.dart`
- Test: `test/ai/ai_tool_protocol_test.dart`

**Interfaces:**
- Produces:
  - `class AiToolCall { final String tool; final Map<String, Object?> args; }`
  - `class AiToolParseResult { final bool isToolCall; final AiToolCall? call; final String text; }` — `text` is the raw reply (final answer) when `!isToolCall`.
  - `AiToolParseResult AiToolProtocol.parse(String reply)` — strips a leading ```json / ``` fence, finds the first `{...}` object, `jsonDecode`s it; a tool-call requires a `tool` string + (optional) `args` map. Any decode failure or missing `tool` → `isToolCall=false` (final answer).
  - `String get kToolRetryNudge` — `"Respond with only the JSON tool-call object, or your final answer in plain text."`

- [ ] **Step 1: Write the failing tests**

Create `test/ai/ai_tool_protocol_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/tools/ai_tool_protocol.dart';

void main() {
  group('AiToolProtocol.parse', () {
    test('parses a bare JSON tool-call', () {
      final r = AiToolProtocol.parse('{"tool":"breakdown","args":{"group_by":"category","from":"2026-10-01","to":"2026-11-01"}}');
      expect(r.isToolCall, isTrue);
      expect(r.call!.tool, 'breakdown');
      expect(r.call!.args['group_by'], 'category');
      expect(r.call!.args['from'], '2026-10-01');
    });

    test('parses a fenced ```json tool-call', () {
      final r = AiToolProtocol.parse('```json\n{"tool":"list_entities","args":{"kind":"category"}}\n```');
      expect(r.isToolCall, isTrue);
      expect(r.call!.tool, 'list_entities');
      expect(r.call!.args['kind'], 'category');
    });

    test('parses a tool-call embedded in prose (first object wins)', () {
      final r = AiToolProtocol.parse('Let me look that up.\n{"tool":"monthly_totals","args":{"from":"2026-01-01","to":"2026-12-01"}}');
      expect(r.isToolCall, isTrue);
      expect(r.call!.tool, 'monthly_totals');
    });

    test('a plain-text answer with no JSON is the final answer', () {
      final r = AiToolProtocol.parse('You spent 3000 on Food in October.');
      expect(r.isToolCall, isFalse);
      expect(r.text, 'You spent 3000 on Food in October.');
    });

    test('JSON without a "tool" key is a final answer (not a tool-call)', () {
      final r = AiToolProtocol.parse('{"summary":"You spent 3000."}');
      expect(r.isToolCall, isFalse);
    });

    test('malformed JSON is a final answer, never throws', () {
      final r = AiToolProtocol.parse('{"tool":"breakdown","args":');
      expect(r.isToolCall, isFalse);
      expect(r.text, '{"tool":"breakdown","args":');
    });

    test('tool without args still parses (empty args map)', () {
      final r = AiToolProtocol.parse('{"tool":"goals_overview"}');
      expect(r.isToolCall, isTrue);
      expect(r.call!.tool, 'goals_overview');
      expect(r.call!.args, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ai/ai_tool_protocol_test.dart`
Expected: FAIL — `AiToolProtocol` not defined (compile error).

- [ ] **Step 3: Implement**

Create `lib/features/ai/tools/ai_tool_protocol.dart`:

```dart
import 'dart:convert';

/// A parsed tool-call from an LLM reply: the tool name + its args map.
class AiToolCall {
  const AiToolCall({required this.tool, required this.args});
  final String tool;
  final Map<String, Object?> args;
}

/// The result of parsing an LLM reply. Either it is a tool-call
/// ([isToolCall] true, [call] set) or the final answer ([text] holds the raw
/// reply to render). The parser is forgiving: any decode failure or missing
/// `tool` key degrades to "final answer" rather than throwing — so a malformed
/// reply never blocks the user.
class AiToolParseResult {
  const AiToolParseResult({this.call, required this.text});
  final AiToolCall? call;
  final String text;
  bool get isToolCall => call != null;
}

/// Provider-agnostic JSON tool-call protocol. The LLM is told (in the system
/// prompt) to either answer in plain text or reply with **only** a JSON object
/// `{"tool": "<name>", "args": {…}}`. This class parses that.
class AiToolProtocol {
  const AiToolProtocol._();

  /// Parse [reply]. Strips a leading ```json / ``` fence if present, finds the
  /// first `{...}` object, and decodes it. A tool-call requires a `tool` field
  /// that is a non-empty string; `args` defaults to an empty map. Anything else
  /// (no JSON, malformed JSON, JSON without `tool`) is treated as the final
  /// answer.
  static AiToolParseResult parse(String reply) {
    final stripped = _stripFence(reply);
    final obj = _firstJsonObject(stripped);
    if (obj == null) return AiToolParseResult(text: reply);
    final tool = obj['tool'];
    if (tool is! String || tool.trim().isEmpty) {
      return AiToolParseResult(text: reply);
    }
    final args = obj['args'];
    final argMap = args is Map ? Map<String, Object?>.from(args) : const <String, Object?>{};
    return AiToolParseResult(call: AiToolCall(tool: tool.trim(), args: argMap), text: reply);
  }

  static String _stripFence(String s) {
    final trimmed = s.trim();
    if (trimmed.startsWith('```')) {
      // Drop the opening fence (```json or ```) and a trailing ```.
      final withoutOpen = trimmed.replaceFirst(RegExp(r'^```[a-zA-Z]*\n'), '');
      return withoutOpen.replaceFirst(RegExp(r'```\s*$'), '').trim();
    }
    return trimmed;
  }

  /// Find and decode the first balanced `{...}` object in [s], or null.
  static Map<String, Object?>? _firstJsonObject(String s) {
    final start = s.indexOf('{');
    if (start < 0) return null;
    int depth = 0;
    bool inStr = false;
    String? esc;
    for (int i = start; i < s.length; i++) {
      final ch = s[i];
      if (inStr) {
        if (esc == '\\') {
          esc = null;
        } else if (ch == '\\') {
          esc = '\\';
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          final slice = s.substring(start, i + 1);
          try {
            final decoded = jsonDecode(slice);
            if (decoded is Map) return Map<String, Object?>.from(decoded);
            return null;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }
}

/// One-line nudge appended when a reply looked tool-ish but didn't parse, to
/// give the LLM one chance to self-correct before treating the reply as final.
const String kToolRetryNudge =
    'Respond with only the JSON tool-call object ({"tool": "...", "args": {...}}), '
    'or your final answer in plain text.';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ai/ai_tool_protocol_test.dart`
Expected: PASS (all 7 tests green).

- [ ] **Step 5: Commit (if the user has asked for commits)**

```bash
git add lib/features/ai/tools/ai_tool_protocol.dart test/ai/ai_tool_protocol_test.dart
git commit -m "feat(ai): provider-agnostic JSON tool-call protocol parser (Phase 2)"
```

---

## Task 4: Tool catalog (TDD)

Static definitions of the 6 tools + the human-readable catalog string embedded in the system prompt. Pure data.

**Files:**
- Create: `lib/features/ai/tools/ai_tool_catalog.dart`
- Test: `test/ai/ai_tool_catalog_test.dart`

**Interfaces:**
- Produces:
  - `enum AiToolKind { listEntities, breakdown, monthlyTotals, filteredTotals, budgetStatus, goalsOverview, billsOverview }`
  - `class AiToolDef { final String name; final String description; final Map<String,String> args; }` (`args` is `argName → "type: description"`)
  - `Map<String, AiToolDef> aiToolCatalog` keyed by name.
  - `String get kAiToolCatalogText` — the prompt-facing catalog (name + description + args for each tool).

- [ ] **Step 1: Write the failing tests**

Create `test/ai/ai_tool_catalog_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/tools/ai_tool_catalog.dart';

void main() {
  test('catalog defines the 6 tools', () {
    expect(aiToolCatalog.keys, containsAll(const [
      'list_entities', 'breakdown', 'monthly_totals', 'filtered_totals',
      'budget_status', 'goals_overview', 'bills_overview',
    ]));
    expect(aiToolCatalog.length, 7);
  });

  test('catalog text names every tool and its args', () {
    final t = kAiToolCatalogText;
    for (final name in aiToolCatalog.keys) {
      expect(t, contains(name));
    }
    // breakdown must document its required args.
    expect(t, contains('group_by'));
    expect(t, contains('from'));
    expect(t, contains('to'));
  });

  test('filtered_totals documents amount_min/amount_max and entity filters', () {
    final def = aiToolCatalog['filtered_totals']!;
    expect(def.args.keys, containsAll(const ['amount_min', 'amount_max', 'category', 'kind']));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ai/ai_tool_catalog_test.dart`
Expected: FAIL — `aiToolCatalog` not defined.

- [ ] **Step 3: Implement**

Create `lib/features/ai/tools/ai_tool_catalog.dart`:

```dart
/// The fixed set of on-device tools the AI may call. Safety comes from this set
/// being closed and named — the LLM never authors SQL. Each tool returns
/// aggregates only (no rows, no notes, no contact data); entity references in
/// args use opaque labels (`cat_3`) the executor resolves to real ids on-device.
class AiToolDef {
  const AiToolDef({required this.name, required this.description, required this.args});
  final String name;
  final String description;
  /// `argName → "type: description"`. Required args are described as such.
  final Map<String, String> args;
}

const Map<String, AiToolDef> aiToolCatalog = {
  'list_entities': AiToolDef(
    name: 'list_entities',
    description:
        'List all active entities of a kind with their labels (+ real names if '
        'the legend is shared) and the total count. Use this to answer "how '
        'many X do I have" and to discover what exists.',
    args: {'kind': 'String (required): one of category, account, mode, tag, goal, bill'},
  ),
  'breakdown': AiToolDef(
    name: 'breakdown',
    description:
        'Spend broken down by a dimension over a date range. Returns '
        '[{id, amount, count, pct}] sorted desc, capped top-20 + an "other" '
        'rollup. Handles "per-category spend in October", "UPI spend last week".',
    args: {
      'group_by': 'String (required): category | account | mode | tag',
      'from': 'String (required): ISO date yyyy-MM-dd, inclusive',
      'to': 'String (required): ISO date yyyy-MM-dd, exclusive',
      'kind': 'String (optional): expense | income | all (default expense)',
    },
  ),
  'monthly_totals': AiToolDef(
    name: 'monthly_totals',
    description:
        'Per-month income/expense/net over a date range (capped 24 months). '
        'Handles "how much did I spend last March", year-over-year.',
    args: {
      'from': 'String (required): ISO date yyyy-MM-dd, inclusive',
      'to': 'String (required): ISO date yyyy-MM-dd, exclusive',
    },
  ),
  'filtered_totals': AiToolDef(
    name: 'filtered_totals',
    description:
        'Count + total + per-dimension breakdowns for transactions matching '
        'filters. Returns {count, total, by_category, by_mode, by_account, '
        'by_tag} (each capped top-10 + other). NO rows, NO notes, NO merchants. '
        'Handles "how many transactions over 5000 in April", "total UPI spend '
        'last week". Entity filters use opaque labels (cat_3).',
    args: {
      'from': 'String (required): ISO date yyyy-MM-dd, inclusive',
      'to': 'String (required): ISO date yyyy-MM-dd, exclusive',
      'amount_min': 'Number (optional): minimum transaction amount',
      'amount_max': 'Number (optional): maximum transaction amount',
      'category': 'String (optional): opaque label cat_N',
      'account': 'String (optional): opaque label acc_N',
      'mode': 'String (optional): opaque label mode_N',
      'tag': 'String (optional): opaque label tag_N',
      'kind': 'String (optional): expense | income | all (default expense)',
    },
  ),
  'budget_status': AiToolDef(
    name: 'budget_status',
    description:
        'Per-budget status for a month (default current): {id, spent, '
        'effective, over, over_by}.',
    args: {'month': 'String (optional): yyyy-MM (default current month)'},
  ),
  'goals_overview': AiToolDef(
    name: 'goals_overview',
    description:
        'Your savings goals as anonymized aggregates: {id, target, saved, pct, '
        'months_left?, monthly_commitment?}. No names unless the legend is shared.',
    args: {},
  ),
  'bills_overview': AiToolDef(
    name: 'bills_overview',
    description:
        'Your recurring bills as anonymized aggregates: {id, amount, cadence, '
        'next_due_in_days?, source}. No names unless the legend is shared.',
    args: {},
  ),
};

/// The catalog as it appears in the system prompt.
String get kAiToolCatalogText {
  final buf = StringBuffer('You may call these on-device tools to look up the '
      'user\'s data. To call one, reply with ONLY a JSON object: '
      '{"tool": "<name>", "args": {…}}. Results come back as anonymized JSON; '
      'use them to answer. Tools return aggregates only — never rows, notes, '
      'or contact details. Entity references in args use the opaque labels from '
      'the summary (cat_N, acc_N, mode_N, tag_N, goal_N, bill_N).\n');
  for (final def in aiToolCatalog.values) {
    buf.writeln('\n- ${def.name}: ${def.description}');
    if (def.args.isNotEmpty) {
      for (final e in def.args.entries) {
        buf.writeln('    - ${e.key}: ${e.value}');
      }
    }
  }
  return buf.toString();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ai/ai_tool_catalog_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit (if the user has asked for commits)**

```bash
git add lib/features/ai/tools/ai_tool_catalog.dart test/ai/ai_tool_catalog_test.dart
git commit -m "feat(ai): fixed tool catalog for on-device queries (Phase 2)"
```

---

## Task 5: Tool executor — validate / resolve / execute / anonymize (TDD)

The heart of the safety model. Takes a `(tool, args)`, validates, resolves labels → real ids via `labelToId`, runs a **fixed** repo query, anonymizes results back to labels (or real names when `shareNames`), applies caps, and returns the JSON body plus the amounts/names it emitted (so the gatekeeper can accept a reply quoting them).

**Files:**
- Create: `lib/features/ai/tools/ai_tool_executor.dart`
- Test: `test/ai/ai_tool_executor_test.dart`

**Interfaces:**
- Consumes: `ReportsRepository` (`categoryBreakdown`, `modeBreakdown`, `tagBreakdown`, `monthlyTotalsInRange`, `filteredTotals`, `accountBalances`), `BudgetsRepository` (`progressForMonth`), `AiMentionData` (directories), `List<GoalSummary> goals`, `List<BillSummary> bills`, `Map<String,String> labelToId`, `bool shareNames`.
- Produces:
  - `class AiToolResult { final Map<String,Object?> body; final Set<double> amounts; final Set<String> names; final bool isError; }`
  - `class AiToolExecutor { AiToolExecutor({required ReportsRepository reports, required BudgetsRepository budgets, required AiMentionData directory, required List<GoalSummary> goals, required List<BillSummary> bills, required Map<String,String> labelToId, required bool shareNames}); Future<AiToolResult> execute(String tool, Map<String,Object?> args); }`
  - `body` for success is the anonymized JSON the LLM sees; on a validation/exec error, `body = {'error': '<message>'}`, `isError = true`. `amounts`/`names` are populated only on success (so the gatekeeper accepts quoted figures).

- [ ] **Step 1: Write the failing tests**

Create `test/ai/ai_tool_executor_test.dart`. Uses the in-memory DB harness + a real `ReportsRepository`/`BudgetsRepository`.

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/reports_repository.dart';
import 'package:spendwise/data/repositories/budgets_repository.dart';
import 'package:spendwise/features/ai/domain/ai_mention_resolver.dart';
import 'package:spendwise/features/ai/domain/ai_payload_builder.dart';
import 'package:spendwise/features/ai/tools/ai_tool_executor.dart';

void main() {
  late AppDatabase db;
  late ReportsRepository reports;
  late BudgetsRepository budgets;
  late AiToolExecutor exec;

  // Label map mirroring a builder run over two categories + one mode + one
  // account. cat_0 -> c-fuel, cat_1 -> c-food, mode_0 -> m-upi, acc_0 -> a1.
  const labelToId = {
    'cat_0': 'c-fuel', 'cat_1': 'c-food',
    'mode_0': 'm-upi', 'acc_0': 'a1',
  };

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    reports = ReportsRepository(db);
    budgets = BudgetsRepository(db);

    await db.into(db.accounts).insert(
            AccountsCompanion.insert(id: 'a1', name: 'HDFC', icon: '💳', color: '#059669', createdAt: 0, updatedAt: 0));
    await db.into(db.categories).insert(
            CategoriesCompanion.insert(id: 'c-fuel', name: 'Fuel', icon: '⛽', createdAt: 0, updatedAt: 0));
    await db.into(db.categories).insert(
            CategoriesCompanion.insert(id: 'c-food', name: 'Food', icon: '🍔', createdAt: 0, updatedAt: 0));
    await db.into(db.modes).insert(
            ModesCompanion.insert(id: 'm-upi', name: 'UPI', icon: '📱', createdAt: 0, updatedAt: 0));

    Future<void> tx(String id, double amount, String cat, String day) async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id, amount: amount, transactionDate: '2026-10-${day}T10:00:00.000',
        accountId: 'a1', categoryId: cat, modeId: 'm-upi',
        kind: const Value('expense'), createdAt: 0, updatedAt: 0,
      ));
    }
    await tx('tx1', 2000, 'c-fuel', '05');
    await tx('tx2', 500, 'c-fuel', '06');
    await tx('tx3', 3000, 'c-food', '07');

    final directory = AiMentionData(
      categories: const [(id: 'c-fuel', name: 'Fuel'), (id: 'c-food', name: 'Food')],
      accounts: const [(id: 'a1', name: 'HDFC')],
      modes: const [(id: 'm-upi', name: 'UPI')],
      tags: const [],
      categoryAmount: const {}, modeAmount: const {}, tagAmount: const {}, accountBalance: const {},
    );
    exec = AiToolExecutor(
      reports: reports,
      budgets: budgets,
      directory: directory,
      goals: const [],
      bills: const [],
      labelToId: labelToId,
      shareNames: false,
    );
  });

  tearDown(() => db.close());

  test('list_entities(category) returns labels + count', () async {
    final r = await exec.execute('list_entities', {'kind': 'category'});
    expect(r.isError, isFalse);
    final list = r.body['entities']! as List;
    expect(list.length, 2);
    expect((list[0] as Map)['id'], startsWith('cat_'));
    expect(r.body['count'], 2);
    // shareNames off → no real names in body.
    final json = r.body.toString();
    expect(json, isNot(contains('Fuel')));
  });

  test('breakdown(group_by=category) anonymizes ids to labels', () async {
    final r = await exec.execute('breakdown', {
      'group_by': 'category', 'from': '2026-10-01', 'to': '2026-11-01',
    });
    expect(r.isError, isFalse);
    final rows = r.body['rows']! as List;
    expect(rows.length, 2);
    final ids = rows.map((m) => (m as Map)['id'] as String).toSet();
    expect(ids.intersection(const {'cat_0', 'cat_1'}).length, 2);
    // Real category ids never leak.
    final json = r.body.toString();
    expect(json, isNot(contains('c-fuel')));
    expect(json, isNot(contains('c-food')));
    // Emitted amounts are returned for gatekeeper merging.
    expect(r.amounts, contains(3000.0));
  });

  test('filtered_totals with a label filter resolves cat_0 -> c-fuel', () async {
    final r = await exec.execute('filtered_totals', {
      'from': '2026-10-01', 'to': '2026-11-01',
      'category': 'cat_0', 'kind': 'expense',
    });
    expect(r.isError, isFalse);
    expect(r.body['count'], 2); // tx1 + tx2 (both c-fuel)
    expect(r.body['total'], 2500);
  });

  test('monthly_totals returns per-month aggregates', () async {
    final r = await exec.execute('monthly_totals', {
      'from': '2026-10-01', 'to': '2026-11-01',
    });
    expect(r.isError, isFalse);
    final months = r.body['months']! as List;
    expect(months.length, 1);
    expect((months[0] as Map)['expense'], 5500);
  });

  test('unknown label cat_99 returns a structured error (fed back to LLM)', () async {
    final r = await exec.execute('filtered_totals', {
      'from': '2026-10-01', 'to': '2026-11-01', 'category': 'cat_99',
    });
    expect(r.isError, isTrue);
    expect(r.body['error'], contains('cat_99'));
    expect(r.amounts, isEmpty);
  });

  test('unknown tool name returns a structured error', () async {
    final r = await exec.execute('not_a_tool', {});
    expect(r.isError, isTrue);
    expect(r.body['error'], contains('not_a_tool'));
  });

  test('bad date range (from > to) returns a structured error', () async {
    final r = await exec.execute('monthly_totals', {
      'from': '2026-11-01', 'to': '2026-10-01',
    });
    expect(r.isError, isTrue);
    expect(r.body['error'], contains('date'));
  });

  test('shareNames on → breakdown body includes real names', () async {
    final execNamed = AiToolExecutor(
      reports: reports, budgets: budgets,
      directory: AiMentionData(
        categories: const [(id: 'c-fuel', name: 'Fuel'), (id: 'c-food', name: 'Food')],
        accounts: const [(id: 'a1', name: 'HDFC')],
        modes: const [(id: 'm-upi', name: 'UPI')],
        tags: const [],
        categoryAmount: const {}, modeAmount: const {}, tagAmount: const {}, accountBalance: const {},
      ),
      goals: const [], bills: const [],
      labelToId: labelToId, shareNames: true,
    );
    final r = await execNamed.execute('breakdown', {
      'group_by': 'category', 'from': '2026-10-01', 'to': '2026-11-01',
    });
    final json = r.body.toString();
    expect(json, contains('Fuel'));
    expect(json, contains('Food'));
  });

  test('goals_overview returns anonymized goal aggregates (no names when off)', () async {
    final execG = AiToolExecutor(
      reports: reports, budgets: budgets,
      directory: AiMentionData(
        categories: const [], accounts: const [], modes: const [], tags: const [],
        categoryAmount: const {}, modeAmount: const {}, tagAmount: const {}, accountBalance: const {},
      ),
      goals: const [(id: 'g1', name: 'Phone', target: 60000, saved: 15000, monthsLeft: 10, monthlyCommitment: 4500)],
      bills: const [],
      labelToId: const {'goal_0': 'g1'},
      shareNames: false,
    );
    final r = await execG.execute('goals_overview', {});
    expect(r.isError, isFalse);
    final goals = r.body['goals']! as List;
    expect((goals[0] as Map)['id'], 'goal_0');
    expect((goals[0] as Map)['target'], 60000);
    expect(r.body.toString(), isNot(contains('Phone')));
  });
}
```

> **Note:** `BudgetsRepository` import path is `package:spendwise/data/repositories/budgets_repository.dart` and its method is `progressForMonth(DateTime)`. If the import or method name differs, run `grep -n "progressForMonth\|class BudgetsRepository" lib/data/repositories/budgets_repository.dart` and adjust. The `budget_status` tool implementation calls `budgets.progressForMonth(DateTime(year, month))`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ai/ai_tool_executor_test.dart`
Expected: FAIL — `AiToolExecutor` not defined.

- [ ] **Step 3: Implement**

Create `lib/features/ai/tools/ai_tool_executor.dart`:

```dart
import '../../../data/models/budget_progress.dart';
import '../../../data/repositories/budgets_repository.dart';
import '../../../data/repositories/reports_repository.dart';
import '../domain/ai_mention_resolver.dart';
import '../domain/ai_payload_builder.dart';

/// The outcome of executing one tool call. [body] is the JSON the LLM sees
/// (anonymized on success; `{'error': …}` on a validation/execution failure).
/// [amounts] and [names] are the figures/names the body emitted (success only)
/// so the gatekeeper can accept a final reply that quotes them. [isError]
/// marks a structured error to feed back to the LLM for self-correction.
class AiToolResult {
  const AiToolResult({
    required this.body,
    this.amounts = const <double>{},
    this.names = const <String>{},
    this.isError = false,
  });
  final Map<String, Object?> body;
  final Set<double> amounts;
  final Set<String> names;
  final bool isError;
}

/// Executes a named, fixed on-device query for an LLM tool-call. Safety is in
/// the closed tool set — the LLM never authors SQL. Steps per call:
/// validate → resolve labels to real ids (on-device) → run a fixed repo query
/// → anonymize results back to labels (or real names when [shareNames]) → cap.
/// Never reads `note`/`receipt_path`; never touches `due_*`/`ai_*`/`goals`/
/// `recurring_items` tables (goals/bills come from the in-memory aggregates
/// passed in, not a table query).
class AiToolExecutor {
  AiToolExecutor({
    required this.reports,
    required this.budgets,
    required this.directory,
    required this.goals,
    required this.bills,
    required this.labelToId,
    required this.shareNames,
  });

  final ReportsRepository reports;
  final BudgetsRepository budgets;
  final AiMentionData directory;
  final List<GoalSummary> goals;
  final List<BillSummary> bills;
  final Map<String, String> labelToId;
  final bool shareNames;

  static const int _maxRows = 20;
  static const int _maxGroup = 10;
  static const int _maxMonths = 24;

  Future<AiToolResult> execute(String tool, Map<String, Object?> args) async {
    try {
      switch (tool) {
        case 'list_entities':
          return _listEntities(args);
        case 'breakdown':
          return await _breakdown(args);
        case 'monthly_totals':
          return await _monthlyTotals(args);
        case 'filtered_totals':
          return await _filteredTotals(args);
        case 'budget_status':
          return await _budgetStatus(args);
        case 'goals_overview':
          return _goalsOverview();
        case 'bills_overview':
          return _billsOverview();
        default:
          return AiToolResult(body: {'error': 'Unknown tool: $tool'}, isError: true);
      }
    } on _ToolError catch (e) {
      return AiToolResult(body: {'error': e.message}, isError: true);
    } catch (e) {
      return AiToolResult(body: {'error': 'Tool failed: $e'}, isError: true);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _resolveLabel(String label, String kind) {
    final id = labelToId[label];
    if (id == null) throw _ToolError('Unknown $kind label: $label');
    return id;
  }

  /// id → display token. Label by default; real name when shareNames.
  String _labelOf(String id, String kind) {
    if (shareNames) {
      final name = _nameOf(id, kind);
      if (name != null) return name;
    }
    // Invert labelToId for the anonymized default.
    final entry = labelToId.entries.firstWhere(
      (e) => e.value == id,
      orElse: () => MapEntry('', id),
    );
    return entry.key.isNotEmpty ? entry.key : id;
  }

  String? _nameOf(String id, String kind) {
    switch (kind) {
      case 'category':
        return directory.categories.firstWhere(
          (c) => c.id == id, orElse: () => (id: id, name: id)).name;
      case 'account':
        return directory.accounts.firstWhere(
          (a) => a.id == id, orElse: () => (id: id, name: id)).name;
      case 'mode':
        return directory.modes.firstWhere(
          (m) => m.id == id, orElse: () => (id: id, name: id)).name;
      case 'tag':
        return directory.tags.firstWhere(
          (t) => t.id == id, orElse: () => (id: id, name: id)).name;
      case 'goal':
        return goals.firstWhere(
          (g) => g.id == id, orElse: () => (id: id, name: id, target: 0, saved: 0, monthsLeft: null, monthlyCommitment: null)).name;
      case 'bill':
        return bills.firstWhere(
          (b) => b.id == id, orElse: () => (id: id, name: id, amount: 0, cadence: '', nextDueInDays: null, source: '')).name;
    }
    return null;
  }

  ({String from, String to}) _dateRange(Map<String, Object?> args) {
    final from = _isoDate(args, 'from');
    final to = _isoDate(args, 'to');
    if (from.compareTo(to) > 0) {
      throw _ToolError('Invalid date range: from ($from) is after to ($to).');
    }
    return (from: from, to: to);
  }

  String _isoDate(Map<String, Object?> args, String key) {
    final v = args[key];
    if (v is! String) throw _ToolError('Missing or invalid date arg: $key');
    // Accept yyyy-MM-dd or full ISO. Normalize to a start-of-day ISO string.
    final s = v.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return '${s}T00:00:00.000';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) return s;
    throw _ToolError('Bad date format for $key: $v (use yyyy-MM-dd).');
  }

  String? _kind(Map<String, Object?> args) {
    final v = args['kind'];
    if (v == null) return 'expense';
    if (v is! String) throw _ToolError('Bad kind: $v.');
    if (const {'expense', 'income', 'all'}.contains(v)) {
      return v == 'all' ? null : v;
    }
    throw _ToolError('Bad kind: $v (use expense, income, or all).');
  }

  double? _numOpt(Map<String, Object?> args, String key) {
    final v = args[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    throw _ToolError('Bad number for $key: $v.');
  }

  Set<double> _amounts = <double>{};
  Set<String> _names = <String>{};

  void _emit(double amt) => _amounts.add(amt);
  void _emitName(String n) => _names.add(n);

  // ── Tools ─────────────────────────────────────────────────────────────────

  AiToolResult _listEntities(Map<String, Object?> args) {
    final kind = args['kind'];
    if (kind is! String) {
      return const AiToolResult(body: {'error': 'list_entities requires arg "kind".'}, isError: true);
    }
    final out = <Map<String, Object?>>[];
    switch (kind) {
      case 'category':
        for (final c in directory.categories) {
          out.add({'id': _labelOf(c.id, 'category'), if (shareNames) 'name': c.name});
        }
        break;
      case 'account':
        for (final a in directory.accounts) {
          out.add({'id': _labelOf(a.id, 'account'), if (shareNames) 'name': a.name});
        }
        break;
      case 'mode':
        for (final m in directory.modes) {
          out.add({'id': _labelOf(m.id, 'mode'), if (shareNames) 'name': m.name});
        }
        break;
      case 'tag':
        for (final t in directory.tags) {
          out.add({'id': _labelOf(t.id, 'tag'), if (shareNames) 'name': t.name});
        }
        break;
      case 'goal':
        for (final g in goals) {
          out.add({'id': _labelOf(g.id, 'goal'), if (shareNames) 'name': g.name});
        }
        break;
      case 'bill':
        for (final b in bills) {
          out.add({'id': _labelOf(b.id, 'bill'), if (shareNames) 'name': b.name});
        }
        break;
      default:
        return AiToolResult(body: {'error': 'Unknown entity kind: $kind'}, isError: true);
    }
    if (shareNames) for (final e in out) {
      final n = e['name'];
      if (n is String) _emitName(n);
    }
    return AiToolResult(body: {'kind': kind, 'count': out.length, 'entities': out}, names: _names);
  }

  Future<AiToolResult> _breakdown(Map<String, Object?> args) async {
    final groupBy = args['group_by'];
    if (groupBy is! String) {
      return const AiToolResult(body: {'error': 'breakdown requires arg "group_by".'}, isError: true);
    }
    final range = _dateRange(args);
    final kind = _kind(args);
    _amounts = {};
    List<Map<String, Object?>> rows;
    double totalForPct = 0;
    switch (groupBy) {
      case 'category':
        final data = await reports.categoryBreakdown(from: range.from, to: range.to, kind: kind);
        rows = data.map((c) {
          final amt = c.total;
          _emit(amt);
          return {'id': _labelOf(c.categoryId, 'category'), if (shareNames) 'name': c.name, 'amount': amt, 'count': null};
        }).toList();
        totalForPct = data.fold<double>(0, (s, c) => s + c.total);
        break;
      case 'mode':
        final data = await reports.modeBreakdown(from: range.from, to: range.to, kind: kind);
        rows = data.map((m) {
          final amt = m.total;
          _emit(amt);
          return {'id': _labelOf(m.modeId, 'mode'), if (shareNames) 'name': m.name, 'amount': amt, 'count': null};
        }).toList();
        totalForPct = data.fold<double>(0, (s, m) => s + m.total);
        break;
      case 'tag':
        // tagBreakdown is expense-only in the repo; ignore kind for tags.
        final data = await reports.tagBreakdown(from: range.from, to: range.to);
        rows = data.map((t) {
          final amt = t.total;
          _emit(amt);
          return {'id': _labelOf(t.tagId, 'tag'), if (shareNames) 'name': t.name, 'amount': amt, 'count': null};
        }).toList();
        totalForPct = data.fold<double>(0, (s, t) => s + t.total);
        break;
      case 'account':
        // No per-range account breakdown in the repo → use filteredTotals'
        // by_account via a lightweight query. Reuse filteredTotals with no
        // filters, kind only.
        final f = await reports.filteredTotals(from: range.from, to: range.to, kind: kind);
        rows = f.byAccount.map((a) {
          _emit(a.amount);
          return {'id': _labelOf(a.id, 'account'), if (shareNames) 'name': a.name, 'amount': a.amount, 'count': a.count};
        }).toList();
        totalForPct = f.total;
        break;
      default:
        return AiToolResult(body: {'error': 'Unknown group_by: $groupBy'}, isError: true);
    }
    final capped = rows.take(_maxRows).toList();
    if (rows.length > _maxRows) {
      final otherAmt = rows.skip(_maxRows).fold<double>(0, (s, r) => s + (r['amount'] as double));
      capped.add({'id': 'other', 'amount': otherAmt});
    }
    final withPct = capped.map((r) {
      final amt = r['amount'] as double;
      return {...r, 'pct': totalForPct > 0 ? (amt / totalForPct * 100).roundToDouble() / 10 : 0.0};
    }).toList();
    return AiToolResult(body: {'group_by': groupBy, 'rows': withPct}, amounts: _amounts, names: _names);
  }

  Future<AiToolResult> _monthlyTotals(Map<String, Object?> args) async {
    final range = _dateRange(args);
    _amounts = {};
    final data = await reports.monthlyTotalsInRange(from: range.from, to: range.to);
    final months = data.take(_maxMonths).map((m) {
      _emit(m.income);
      _emit(m.expense);
      _emit(m.net);
      return {'month': '${m.year}-${m.month.toString().padLeft(2, '0')}', 'income': m.income, 'expense': m.expense, 'net': m.net};
    }).toList();
    return AiToolResult(body: {'months': months}, amounts: _amounts);
  }

  Future<AiToolResult> _filteredTotals(Map<String, Object?> args) async {
    final range = _dateRange(args);
    final kind = _kind(args);
    _amounts = {};
    String? catId, accId, modeId, tagId;
    if (args['category'] is String) catId = _resolveLabel(args['category'] as String, 'category');
    if (args['account'] is String) accId = _resolveLabel(args['account'] as String, 'account');
    if (args['mode'] is String) modeId = _resolveLabel(args['mode'] as String, 'mode');
    if (args['tag'] is String) tagId = _resolveLabel(args['tag'] as String, 'tag');
    final amountMin = _numOpt(args, 'amount_min');
    final amountMax = _numOpt(args, 'amount_max');

    final r = await reports.filteredTotals(
      from: range.from, to: range.to, kind: kind,
      accountId: accId, categoryId: catId, modeId: modeId, tagId: tagId,
      amountMin: amountMin, amountMax: amountMax,
    );
    _emit(r.total);

    List<Map<String, Object?>> cap(List<({String id, String name, double amount, int count})> src, String kindName) {
      final mapped = src.map((e) {
        _emit(e.amount);
        return {'id': _labelOf(e.id, kindName), if (shareNames) 'name': e.name, 'amount': e.amount, 'count': e.count};
      }).toList();
      final capped = mapped.take(_maxGroup).toList();
      if (mapped.length > _maxGroup) {
        final otherAmt = mapped.skip(_maxGroup).fold<double>(0, (s, m) => s + (m['amount'] as double));
        final otherCnt = src.skip(_maxGroup).fold<int>(0, (s, m) => s + m.count);
        capped.add({'id': 'other', 'amount': otherAmt, 'count': otherCnt});
      }
      return capped;
    }

    return AiToolResult(body: {
      'count': r.count,
      'total': r.total,
      'by_category': cap(r.byCategory, 'category'),
      'by_mode': cap(r.byMode, 'mode'),
      'by_account': cap(r.byAccount, 'account'),
      'by_tag': cap(r.byTag, 'tag'),
    }, amounts: _amounts, names: _names);
  }

  Future<AiToolResult> _budgetStatus(Map<String, Object?> args) async {
    DateTime monthDate;
    final m = args['month'];
    if (m is String && RegExp(r'^\d{4}-\d{2}$').hasMatch(m)) {
      final parts = m.split('-');
      monthDate = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    } else {
      final now = DateTime.now();
      monthDate = DateTime(now.year, now.month);
    }
    _amounts = {};
    final list = await budgets.progressForMonth(monthDate);
    final rows = list.map((b) {
      _emit(b.spent);
      _emit(b.effectiveAmount);
      return {
        'id': _labelOf(b.budget.categoryId, 'category'),
        if (shareNames) 'name': b.categoryName,
        'spent': b.spent,
        'effective': b.effectiveAmount,
        'over': b.isOver,
        if (b.isOver) 'over_by': b.spent - b.effectiveAmount,
      };
    }).toList();
    return AiToolResult(body: {'month': '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}', 'budgets': rows}, amounts: _amounts, names: _names);
  }

  AiToolResult _goalsOverview() {
    _amounts = {};
    final rows = goals.map((g) {
      _emit(g.target); _emit(g.saved);
      if (g.monthlyCommitment != null) _emit(g.monthlyCommitment!);
      final label = _labelOf(g.id, 'goal');
      if (shareNames) _emitName(g.name);
      return {
        'id': label,
        'target': g.target,
        'saved': g.saved,
        'pct': g.target > 0 ? (g.saved / g.target * 100).roundToDouble() / 10 : 0.0,
        if (g.monthsLeft != null) 'months_left': g.monthsLeft,
        if (g.monthlyCommitment != null) 'monthly_commitment': g.monthlyCommitment,
      };
    }).toList();
    return AiToolResult(body: {'goals': rows}, amounts: _amounts, names: _names);
  }

  AiToolResult _billsOverview() {
    _amounts = {};
    final rows = bills.map((b) {
      _emit(b.amount);
      final label = _labelOf(b.id, 'bill');
      if (shareNames) _emitName(b.name);
      return {
        'id': label,
        'amount': b.amount,
        'cadence': b.cadence,
        if (b.nextDueInDays != null) 'next_due_in_days': b.nextDueInDays,
        'source': b.source,
      };
    }).toList();
    return AiToolResult(body: {'bills': rows}, amounts: _amounts, names: _names);
  }
}

class _ToolError implements Exception {
  const _ToolError(this.message);
  final String message;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ai/ai_tool_executor_test.dart`
Expected: PASS (all 10 tests green). If `BudgetsRepository` import/method differs, fix per the note in Step 1.

Run: `flutter analyze lib/`
Expected: no issues.

- [ ] **Step 5: Commit (if the user has asked for commits)**

```bash
git add lib/features/ai/tools/ai_tool_executor.dart test/ai/ai_tool_executor_test.dart
git commit -m "feat(ai): on-device AiToolExecutor — fixed named queries, aggregates only (Phase 2)"
```

---

## Task 6: The buffered round loop — `AiToolRunner` (TDD)

A pure, injectable class that owns the tool-use round loop. Takes an `LlmClient` (so a fake can script rounds), an `AiToolExecutor`, a gatekeeper-builder, the preamble + history, and a status callback. Returns the restored + checked final answer. Unit-testable without Riverpod.

**Files:**
- Create: `lib/features/ai/tools/ai_tool_runner.dart`
- Test: `test/ai/ai_tool_runner_test.dart`

**Interfaces:**
- Consumes: `LlmClient.complete(AiConfig, List<ChatMessage>, {int? maxTokens, bool json})`; `AiToolExecutor.execute(tool, args)`; `AiToolProtocol.parse`; `AiGatekeeper`.
- Produces:
  - `typedef AiGatekeeperBuilder = AiGatekeeper Function(Set<double> extraAmounts, Set<String> extraNames);`
  - `class AiToolRunner { AiToolRunner({required LlmClient client, required AiConfig config, required AiToolExecutor executor, required AiGatekeeperBuilder gatekeeperBuilder, required void Function(String) onStatus, int maxRounds = 4}); Future<({String content, AiCheckResult check})> run({required List<ChatMessage> preamble, required List<ChatMessage> history}); }`
  - On a non-tool-call reply: `content = gatekeeper.restore(reply)`, `check = gatekeeper.check(content)`. On max rounds: append a final "Answer now…" instruction and force one more `complete`. Errors from `complete` propagate as `LlmException` (the controller maps them).

- [ ] **Step 1: Write the failing tests**

Create `test/ai/ai_tool_runner_test.dart` with a fake `LlmClient`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/ai_config.dart';
import 'package:spendwise/features/ai/domain/ai_gatekeeper.dart';
import 'package:spendwise/features/ai/domain/ai_payload_builder.dart';
import 'package:spendwise/features/ai/domain/llm_client.dart';
import 'package:spendwise/features/ai/domain/ai_mention_resolver.dart';
import 'package:spendwise/features/ai/tools/ai_tool_executor.dart';
import 'package:spendwise/features/ai/tools/ai_tool_runner.dart';

/// A fake client that returns scripted replies in order, recording every call.
class _FakeClient implements LlmClient {
  _FakeClient(this.replies);
  final List<String> replies;
  final List<List<ChatMessage>> calls = [];
  int _i = 0;
  @override
  Future<String> complete(AiConfig config, List<ChatMessage> messages,
      {int? maxTokens, bool json = false}) async {
    calls.add(messages);
    return replies[_i++ < replies.length ? _i - 1 : replies.length - 1];
  }
  @override
  Stream<String> stream(AiConfig config, List<ChatMessage> messages,
      {int? maxTokens}) async* {
    yield await complete(config, messages, maxTokens: maxTokens);
  }
}

AiConfig get _config => AiConfig(preset: LlmProviderPreset.all.first);

AiToolExecutor _noopExecutor() => AiToolExecutor(
      reports: null as dynamic, // not invoked in the no-tool tests
      budgets: null as dynamic,
      directory: AiMentionData(
        categories: const [], accounts: const [], modes: const [], tags: const [],
        categoryAmount: const {}, modeAmount: const {}, tagAmount: const {}, accountBalance: const {},
      ),
      goals: const [], bills: const [],
      labelToId: const {}, shareNames: false,
    );

void main() {
  test('a non-tool-call first reply is the final answer (no tool round)', () async {
    final client = _FakeClient(['You spent 3000 on Food.']);
    final runner = AiToolRunner(
      client: client,
      config: _config,
      executor: _noopExecutor(),
      gatekeeperBuilder: (a, n) => AiGatekeeper(legend: const {}, validLabels: const {}, sentAmounts: a),
      onStatus: (_) {},
    );
    final res = await runner.run(
      preamble: const [ChatMessage(role: 'system', content: 'sys')],
      history: const [ChatMessage(role: 'user', content: 'how much on Food?')],
    );
    expect(client.calls.length, 1);
    expect(res.content, 'You spent 3000 on Food.');
    expect(res.check.severity, AiCheckSeverity.ok);
  });

  test('a tool-call then a final answer runs two rounds and feeds the result back', () async {
    final client = _FakeClient([
      '{"tool":"goals_overview","args":{}}',
      'Your goal is 25% funded.',
    ]);
    final executor = AiToolExecutor(
      reports: null as dynamic,
      budgets: null as dynamic,
      directory: AiMentionData(
        categories: const [], accounts: const [], modes: const [], tags: const [],
        categoryAmount: const {}, modeAmount: const {}, tagAmount: const {}, accountBalance: const {},
      ),
      goals: const [(id: 'g1', name: 'Phone', target: 60000, saved: 15000, monthsLeft: 10, monthlyCommitment: 4500)],
      bills: const [],
      labelToId: const {'goal_0': 'g1'},
      shareNames: false,
    );
    final statuses = <String>[];
    final runner = AiToolRunner(
      client: client,
      config: _config,
      executor: executor,
      gatekeeperBuilder: (a, n) => AiGatekeeper(legend: const {}, validLabels: const {'goal_0'}, sentAmounts: a),
      onStatus: statuses.add,
    );
    final res = await runner.run(
      preamble: const [ChatMessage(role: 'system', content: 'sys')],
      history: const [ChatMessage(role: 'user', content: 'how is my goal?')],
    );
    expect(client.calls.length, 2);
    // The second call's messages include the tool_result.
    final second = client.calls[1];
    expect(second.any((m) => m.content.contains('Tool result')), isTrue);
    expect(statuses, contains('Looking up your data…'));
    expect(res.content, 'Your goal is 25% funded.');
  });

  test('max rounds forces a final answer', () async {
    // Always replies with a tool-call → after maxRounds the runner forces one.
    final client = _FakeClient(['{"tool":"goals_overview","args":{}}']);
    final runner = AiToolRunner(
      client: client,
      config: _config,
      executor: _noopExecutor(),
      gatekeeperBuilder: (a, n) => AiGatekeeper(legend: const {}, validLabels: const {}, sentAmounts: a),
      onStatus: (_) {},
      maxRounds: 2,
    );
    final res = await runner.run(
      preamble: const [ChatMessage(role: 'system', content: 'sys')],
      history: const [ChatMessage(role: 'user', content: 'go')],
    );
    // The last call carries the "answer now" instruction and the reply (still a
    // tool-call) is treated as the final answer text rather than looping forever.
    expect(res.content, contains('tool'));
  });
}
```

> **Note:** the `_noopExecutor` uses `null as dynamic` for the repos because the no-tool tests never call `execute`. This is test-only and compiles because `complete` is the only path exercised. If the analyzer rejects `null as dynamic`, instead pass a tiny in-memory `AppDatabase(NativeDatabase.memory())` + real repos (mirror Task 5's setUp). Prefer the real-repo approach if `null as dynamic` warns.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ai/ai_tool_runner_test.dart`
Expected: FAIL — `AiToolRunner` not defined.

- [ ] **Step 3: Implement**

Create `lib/features/ai/tools/ai_tool_runner.dart`:

```dart
import 'dart:convert';

import '../domain/ai_config.dart';
import '../domain/ai_gatekeeper.dart';
import '../domain/llm_client.dart';
import 'ai_tool_executor.dart';
import 'ai_tool_protocol.dart';

typedef AiGatekeeperBuilder = AiGatekeeper Function(Set<double> extraAmounts, Set<String> extraNames);

/// Runs the buffered tool-use round loop for one user question. Pure-ish: takes
/// an [LlmClient] (so a fake can script rounds in tests) and an [AiToolExecutor].
/// Every round is non-streaming ([LlmClient.complete]) — the full reply must be
/// in hand to decide tool-call vs final answer, and streaming an internal
/// tool-call JSON to the user would leak the protocol.
///
/// Round: request completion → if [AiToolProtocol.parse] yields a tool-call,
/// execute it via [executor], append the tool-call + an anonymized `tool_result`
/// message, merge the emitted amounts/names into the gatekeeper, call
/// [onStatus] ("Looking up your data…"), and loop (≤ [maxRounds]). On a
/// non-tool-call reply: restore + check via the gatekeeper and return. On
/// reaching [maxRounds]: append an "answer now" instruction and force one final
/// completion, treating its reply as the final answer.
class AiToolRunner {
  AiToolRunner({
    required this.client,
    required this.config,
    required this.executor,
    required this.gatekeeperBuilder,
    required this.onStatus,
    this.maxRounds = 4,
  });

  final LlmClient client;
  final AiConfig config;
  final AiToolExecutor executor;
  final AiGatekeeperBuilder gatekeeperBuilder;
  final void Function(String status) onStatus;
  final int maxRounds;

  Future<({String content, AiCheckResult check})> run({
    required List<ChatMessage> preamble,
    required List<ChatMessage> history,
  }) async {
    final messages = <ChatMessage>[...preamble, ...history];
    Set<double> extraAmounts = const {};
    Set<String> extraNames = const {};

    for (int round = 0; round < maxRounds; round++) {
      final reply = await client.complete(config, messages, maxTokens: 1024);
      final parsed = AiToolProtocol.parse(reply);
      if (!parsed.isToolCall) {
        return _finalize(reply, extraAmounts, extraNames);
      }
      // Tool round.
      onStatus('Looking up your data…');
      final result = await executor.execute(parsed.call!.tool, parsed.call!.args);
      extraAmounts = {...extraAmounts, ...result.amounts};
      extraNames = {...extraNames, ...result.names};
      // Append the assistant tool-call (so the LLM sees its own call) + the
      // tool_result as a user message (provider-safe role).
      messages.add(ChatMessage(role: 'assistant', content: reply));
      messages.add(ChatMessage(
        role: 'user',
        content: '[Tool result for ${parsed.call!.tool}]: '
            '${const JsonEncoder.withIndent('  ').convert(result.body)}\n'
            'Now answer the user using this data, or call another tool if needed.',
      ));
    }

    // Maxed out → force a final answer.
    onStatus('Looking up your data…');
    messages.add(const ChatMessage(
      role: 'user',
      content: 'Answer the user now using the data you have. Do not call another tool.',
    ));
    final reply = await client.complete(config, messages, maxTokens: 1024);
    return _finalize(reply, extraAmounts, extraNames);
  }

  ({String content, AiCheckResult check}) _finalize(
      String reply, Set<double> extraAmounts, Set<String> extraNames) {
    final gatekeeper = gatekeeperBuilder(extraAmounts, extraNames);
    final restored = gatekeeper.restore(reply);
    return (content: restored, check: gatekeeper.check(restored));
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ai/ai_tool_runner_test.dart`
Expected: PASS (all 3 tests green).

- [ ] **Step 5: Commit (if the user has asked for commits)**

```bash
git add lib/features/ai/tools/ai_tool_runner.dart test/ai/ai_tool_runner_test.dart
git commit -m "feat(ai): AiToolRunner — buffered tool-use round loop (Phase 2)"
```

---

## Task 7: `aiToolCalling` pref + provider + settings toggle

The on-by-default, privacy-safe toggle. When off, the controller uses today's streaming path + `kAskSystemPrompt`; when on, it runs the tool loop + `kAskToolSystemPrompt`.

**Files:**
- Modify: `lib/services/prefs_service.dart`
- Modify: `lib/state/ai_providers.dart`
- Modify: `lib/features/ai/presentation/ai_settings_section.dart`

**Interfaces:**
- Produces: `PrefsService.aiToolCalling` (default true) + `setAiToolCalling`; `aiToolCallingProvider` (StateNotifierProvider<bool>); a `SwitchListTile` in the AI settings section.

- [ ] **Step 1 (no unit test — wiring): implement**

In `lib/services/prefs_service.dart`, after the `aiCustomSql` block (line ~127), add:

```dart
  /// Whether the AI Copilot chat may call on-device lookup tools to answer
  /// questions (any category, any date range, filtered totals, goal status).
  /// On by default — tools return aggregates only (no rows, notes, contacts, or
  /// real names unless `aiShareNames` is also on). When off, the chat uses a
  /// static snapshot only.
  bool get aiToolCalling => _prefs.getBool('ai_tool_calling') ?? true;
  Future<void> setAiToolCalling(bool v) => _prefs.setBool('ai_tool_calling', v);
```

In `lib/state/ai_providers.dart`, after `aiCustomSqlProvider` (line ~78), add:

```dart
/// Whether the AI Copilot chat may call on-device lookup tools. On by default
/// (privacy-safe — aggregates only). See [PrefsService.aiToolCalling].
final aiToolCallingProvider =
    StateNotifierProvider<AiToolCallingNotifier, bool>(
        (ref) => AiToolCallingNotifier(ref.watch(prefsServiceProvider)));

class AiToolCallingNotifier extends StateNotifier<bool> {
  AiToolCallingNotifier(this._prefs) : super(_prefs.aiToolCalling);
  final PrefsService _prefs;
  Future<void> set(bool v) async {
    await _prefs.setAiToolCalling(v);
    state = v;
  }
}
```

In `lib/features/ai/presentation/ai_settings_section.dart`, insert a new `SwitchListTile` immediately after the "Share category & account names" switch (after the `SwitchListTile` that ends at line ~102, before the `const Divider(height: 1),` that precedes "Dynamic charts"):

```dart
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Allow AI to look up my data'),
            subtitle: const Text(
                'Lets the chat AI run read-only lookups on your device to '
                'answer questions about any category, date range, or filtered '
                'totals — and help plan around goals and budgets. Your data '
                'never leaves; lookups return aggregates only (no notes, '
                'contacts, or raw rows). On by default.'),
            secondary: const Icon(Icons.manage_search_outlined),
            value: ref.watch(aiToolCallingProvider),
            onChanged: (v) => ref.read(aiToolCallingProvider.notifier).set(v),
          ),
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/`
Expected: no issues.

- [ ] **Step 3: Commit (if the user has asked for commits)**

```bash
git add lib/services/prefs_service.dart lib/state/ai_providers.dart lib/features/ai/presentation/ai_settings_section.dart
git commit -m "feat(ai): aiToolCalling toggle (on by default) + settings switch (Phase 2)"
```

---

## Task 8: `kAskToolSystemPrompt` + controller wiring

Branch `_streamReply` on the toggle. When on: build `AiToolExecutor` from the stored directory/goals/bills/labelToId, run `AiToolRunner` with `kAskToolSystemPrompt`, render the final answer (via `AiMarkdown`), persist. When off: today's streaming path. Store the directory + labelToId + goals + bills on the notifier in `_buildContext` so the executor can be built without re-gathering.

**Files:**
- Modify: `lib/features/ai/domain/ai_prompts.dart` (add `kAskToolSystemPrompt`)
- Modify: `lib/features/ai/services/ai_chat_controller.dart` (`_buildContext` store fields + `_streamReply` branch + a new `_streamReplyWithTools`)

**Interfaces:**
- Consumes: `aiToolCallingProvider`; `AiToolExecutor`, `AiToolRunner`, `kAiToolCatalogText`; `LlmClient.complete`; `AiGatekeeper`; `_Labeler`/`AiContext.labelToId`; `AiMentionData`; `List<GoalSummary>`/`List<BillSummary>`.
- Produces: the chat replies via the tool loop when the toggle is on.

- [ ] **Step 1 (no unit test — wiring; the loop is tested in Task 6): implement the prompt**

In `lib/features/ai/domain/ai_prompts.dart`, add `import` for the catalog if not present, and add `kAskToolSystemPrompt`. It MUST reuse the privacy/label/numeric rules of `kAskSystemPrompt` and append the catalog + protocol. Concretely, define it as `kAskSystemPrompt` plus the tool block. If `kAskSystemPrompt` is a `const String`, build `kAskToolSystemPrompt` as a computed `String` (not const) by concatenation:

```dart
import '../tools/ai_tool_catalog.dart';
```

```dart
/// System prompt for the tool-calling chat mode. The privacy/label/numeric
/// rules are identical to [kAskSystemPrompt]; this adds the tool catalog + the
/// JSON tool-call protocol. Tools are a fallback for data not in the snapshot —
/// the AI should answer from the snapshot when it can, and call a tool when it
/// cannot. It must never invent figures, never claim a category "doesn't exist"
/// (call `list_entities` if unsure), and always use the opaque labels from the
/// summary when referring to entities.
final String kAskToolSystemPrompt = '''
$kAskSystemPrompt

## On-device lookup tools

$kAiToolCatalogText

Rules:
- Answer from the summary snapshot when it already has the data. Call a tool
  only when the snapshot does not cover the question (other months, arbitrary
  ranges, filtered counts/totals, refreshed goal/bill status).
- To call a tool, reply with ONLY the JSON object {"tool": "...", "args": {…}}.
  Do not wrap it in prose. You will receive the result as a "[Tool result …]"
  message; then answer the user (or call one more tool if truly needed).
- Use at most a few tool calls per question. Stop and answer once you have
  enough.
- Never invent figures — every number in your final answer must come from the
  snapshot or a tool result. Never claim a category/account/mode/tag "doesn't
  exist"; if unsure, call list_entities.
- Refer to entities by their opaque labels (cat_0, acc_1, …) when calling
  tools; in your final answer, use the real names from the legend when one is
  provided, otherwise describe them plainly.
''';
```

> If `kAskSystemPrompt` is `const`, the interpolation above makes `kAskToolSystemPrompt` a `final String` (not const) — that's fine; the controller uses it at runtime. Ensure `kAskSystemPrompt` is in scope (same file).

- [ ] **Step 2: Store the executor inputs on the notifier**

In `lib/features/ai/services/ai_chat_controller.dart`:

Add imports:

```dart
import '../tools/ai_tool_catalog.dart';
import '../tools/ai_tool_executor.dart';
import '../tools/ai_tool_runner.dart';
import '../tools/ai_tool_protocol.dart';
```

Add fields to `AskChatNotifier` (near `_resolver`):

```dart
  AiMentionData? _mentionData;
  Map<String, String> _labelToId = const {};
  List<GoalSummary> _goals = const [];
  List<BillSummary> _bills = const [];
```

In `_buildContext`, after `final ctx = builder.buildAskContext(...)` and after `_resolver = AiMentionResolver(...)`, store:

```dart
    _mentionData = mentionData;
    _labelToId = ctx.labelToId;
    _goals = extras.goals;
    _bills = extras.recurringBills;
```

(`mentionData` is already gathered there from Phase 1; `extras.goals`/`extras.recurringBills` are already fetched.)

- [ ] **Step 3: Branch `_streamReply` on the toggle**

In `_streamReply`, after `final config = await _aiConfigWithKey();` (and the null-check) and after the preamble-build block, read the toggle and branch. Replace the block that builds `history`/`requestMessages` and starts the stream with:

```dart
    final toolCallingOn = _ref.read(aiToolCallingProvider);

    // History = all persisted (non-placeholder) messages so far.
    final history = state.messages
        .map((m) => ChatMessage(role: m.role, content: m.content))
        .toList();

    // The mention resolver runs in BOTH modes (it composes with tools): it
    // appends a `[Context note]` to the latest user message as sent to the LLM
    // only, bridging the user's real names to the anonymized labels.
    final resolution = _resolveLastUserMessage(history);
    if (resolution != null) {
      _gatekeeper = _buildGatekeeper(resolution.amounts, resolution.matchedNames);
    }

    if (toolCallingOn) {
      await _streamReplyWithTools(config, history);
      return;
    }

    // ── Tools OFF: today's streaming path (unchanged) ──
    final requestMessages = [..._preamble, ...history];
    state = state.copyWith(
      messages: [
        ...state.messages,
        const AskMessage(role: 'assistant', content: '', streaming: true),
      ],
      isLoading: true,
    );
    await _sub?.cancel();
    final client = _ref.read(aiClientProvider);
    _sub = client.stream(config, requestMessages).listen(
      _onChunk,
      onError: (Object e) => _failLast(_errorMessage(e)),
      onDone: () {
        if (state.isLoading) _finishLast();
      },
    );
```

Also: when `toolCallingOn`, the preamble's system message must be `kAskToolSystemPrompt` instead of `kAskSystemPrompt`. Modify the preamble-build block to choose the prompt:

```dart
    if (!_contextSent) {
      final context = await _buildContext(config);
      final toolCallingOn = _ref.read(aiToolCallingProvider);
      _preamble = [
        ChatMessage(
            role: 'system',
            content: toolCallingOn ? kAskToolSystemPrompt : kAskSystemPrompt),
        ChatMessage(
            role: 'user',
            content:
                'Here is my anonymized financial summary for context (JSON). '
                'Use only this data to answer my questions:\n'
                '${const JsonEncoder.withIndent('  ').convert(context)}'),
        ChatMessage(
            role: 'assistant',
            content: 'Got it — I have your summary. What would you like to know?'),
      ];
      _contextSent = true;
    }
```

(Read the toggle fresh here so the prompt matches the mode the user currently has; if they flip it mid-session, the next `send` after a notifier rebuild picks it up. The preamble is built once per session; that's acceptable — flipping the toggle is rare.)

- [ ] **Step 4: Implement `_streamReplyWithTools`**

Add the method to `AskChatNotifier`:

```dart
  /// Tool-calling path: buffered (non-streaming) rounds via [AiToolRunner].
  /// Shows a "Looking up your data…" status during tool rounds, then renders the
  /// final answer whole (restored + gatekeeper-checked) and persists it.
  Future<void> _streamReplyWithTools(AiConfig config, List<ChatMessage> history) async {
    final mentionData = _mentionData;
    if (mentionData == null) {
      // No context yet (shouldn't happen — _buildContext ran). Fall back.
      final requestMessages = [..._preamble, ...history];
      _streamFallback(config, requestMessages);
      return;
    }
    final executor = AiToolExecutor(
      reports: _ref.read(reportsRepositoryProvider),
      budgets: _ref.read(budgetsRepositoryProvider),
      directory: mentionData,
      goals: _goals,
      bills: _bills,
      labelToId: _labelToId,
      shareNames: config.shareNames,
    );
    final runner = AiToolRunner(
      client: _ref.read(aiClientProvider),
      config: config,
      executor: executor,
      gatekeeperBuilder: _buildGatekeeper,
      onStatus: (s) {
        // Show the status as a transient streaming bubble that gets replaced.
        final messages = List<AskMessage>.of(state.messages);
        if (messages.isNotEmpty && messages.last.streaming) {
          messages[messages.length - 1] = AskMessage(
              role: 'assistant', content: s, streaming: true, isError: false);
        } else {
          messages.add(AskMessage(role: 'assistant', content: s, streaming: true));
        }
        state = state.copyWith(messages: messages, isLoading: true);
      },
    );

    state = state.copyWith(
      messages: [
        ...state.messages,
        const AskMessage(role: 'assistant', content: '', streaming: true),
      ],
      isLoading: true,
    );

    try {
      final res = await runner.run(preamble: _preamble, history: history);
      if (!mounted) return;
      final check = res.check;
      final messages = List<AskMessage>.of(state.messages);
      if (res.content.isEmpty) {
        messages.removeLast();
        state = state.copyWith(messages: messages, isLoading: false);
        return;
      }
      if (check.severity == AiCheckSeverity.bad) {
        messages[messages.length - 1] =
            AskMessage(role: 'assistant', content: check.issues.join(' '), isError: true);
        state = state.copyWith(messages: messages, isLoading: false);
        return;
      }
      final saved = await _ref
          .read(aiChatRepositoryProvider)
          .addAssistantMessage(_threadId, res.content);
      if (!mounted) return;
      messages[messages.length - 1] = AskMessage(
        role: 'assistant',
        content: res.content,
        id: saved.id,
        createdAt: saved.createdAt,
        streaming: false,
      );
      state = state.copyWith(messages: messages, isLoading: false);
    } on LlmException catch (e) {
      _failLast(e.userMessage);
    } catch (e) {
      _failLast('Something went wrong. Try again.');
    }
  }

  /// Streaming fallback used only if the tool path can't run (no context).
  Future<void> _streamFallback(AiConfig config, List<ChatMessage> requestMessages) async {
    state = state.copyWith(
      messages: [
        ...state.messages,
        const AskMessage(role: 'assistant', content: '', streaming: true),
      ],
      isLoading: true,
    );
    await _sub?.cancel();
    final client = _ref.read(aiClientProvider);
    _sub = client.stream(config, requestMessages).listen(
      _onChunk,
      onError: (Object e) => _failLast(_errorMessage(e)),
      onDone: () {
        if (state.isLoading) _finishLast();
      },
    );
  }
```

- [ ] **Step 5: Verify it compiles + no regressions**

Run: `flutter analyze lib/`
Expected: no issues.

Run: `flutter test`
Expected: all green (the controller wiring is exercised by the Task 6 runner tests + manual smoke; no new controller test needed).

- [ ] **Step 6: Commit (if the user has asked for commits)**

```bash
git add lib/features/ai/domain/ai_prompts.dart lib/features/ai/services/ai_chat_controller.dart
git commit -m "feat(ai): wire the tool-calling chat loop + kAskToolSystemPrompt (Phase 2)"
```

---

## Task 9: Full verify + privacy audit + docs

**Files:** none (verification + audit + `CHANGELOG.md` + `CLAUDE.md`).

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze lib/ test/`
Expected: no issues.

Run: `flutter test`
Expected: all green (existing + Phase 2: protocol, catalog, executor, runner, repo, labelToId).

- [ ] **Step 2: Privacy audit (mandatory — touches the AI outbound path + a new on-device query layer)**

Run the `@spendwise-privacy-auditor` agent (or the `spendwise-privacy-audit` skill) on the Phase 2 diff. The auditor must confirm:
- Tools return **aggregates only** — no `note`, no `receipt_path`, no contact columns, no raw transaction rows. (Verify `filteredTotals`/`monthlyTotalsInRange` select only `amount`/`kind`/`transaction_date` + joined `name`s; verify the executor never surfaces a note or a row list.)
- No tool reads `due_*`/`ai_*`/`goals`/`recurring_items` tables. Goals/bills come from the in-memory `extras` aggregates, not a table query.
- Labels never leak the legend: tool results use `cat_N` (or real names only when `shareNames`); the `labelToId` map never leaves the device.
- The gatekeeper's `sentAmounts`/`sentNameVocabulary` are extended with tool-emitted figures/names (so quoting a fetched figure is accepted); the final reply is still gatekeeper-checked.
- The `aiToolCalling` toggle is on by default and its UI copy states aggregates-only / no PII.

Expected: PASS, 0 blockers. If FAIL, fix before proceeding (hard merge blocker — no override).

- [ ] **Step 3: Reviewer pass**

Run `@spendwise-reviewer` on the full Phase 2 diff. Expected: no rule violations (no DB schema change; list-row rules N/A; changelog subset; no-shame tone in prompts).

- [ ] **Step 4: Manual smoke**

With AI on + a key set + `aiToolCalling` on:
- "How much did I spend on fuel last October?" → expect a `breakdown` or `filtered_totals` tool round ("Looking up your data…") then a real answer.
- "How many transactions over 5000 in April?" → `filtered_totals(amount_min=5000, …)` → count + total, no rows.
- "Can I reach my goal by December?" → `goals_overview` + `monthly_totals`/`breakdown` rounds, then a reasoned projection.
- An unknown label / bad date → executor returns a structured error → the LLM self-corrects or answers with what it has; never crashes.
- Toggle `aiToolCalling` off → replies stream as today (Phase 1 snapshot only), no tool rounds.
- With `shareNames` off, confirm tool results + final reply use restored real names on-device and no raw name leaks.

- [ ] **Step 5: Update CHANGELOG + CLAUDE.md**

In `CHANGELOG.md` under `## Unreleased` → `### Added`, add bullets describing Phase 2 (on-device tool-calling: list_entities / breakdown / monthly_totals / filtered_totals / budget_status / goals_overview / bills_overview; the `aiToolCalling` toggle on by default; "Looking up your data…" indicator). In `CLAUDE.md`, add a new subsection under AI Privacy Rules documenting the tool layer: named fixed queries only (no LLM-authored SQL), aggregates only, `due_*`/`ai_*`/`goals`/`recurring_items` tables hard-blocked from tools, `labelToId` on-device only, gatekeeper `sentAmounts` merges tool figures, and the `aiToolCalling` toggle. Keep within the changelog parser's supported subset.

- [ ] **Step 6: Final commit (if the user has asked for commits)**

```bash
git add CHANGELOG.md CLAUDE.md
git commit -m "docs(ai): changelog + CLAUDE.md for Phase 2 on-device tool-calling"
```

---

## Self-Review notes

- **Spec coverage:** tool catalog (Task 4) + executor validate/resolve/fixed-query/anonymize (Task 5) + JSON protocol with fence stripping + retry-then-final (Task 3) + chat loop ≤4 rounds with "Looking up…" + buffered non-streaming (Task 6 + Task 8) + gatekeeper sentAmounts merge (Task 6 gatekeeperBuilder wires through `extraAmounts`/`extraNames`) + `aiToolCalling` toggle default true (Task 7) + `kAskToolSystemPrompt` (Task 8) + tests + privacy audit (Task 9). All 6 tools present (`list_entities`, `breakdown`, `monthly_totals`, `filtered_totals`, `budget_status`, `goals_overview`, `bills_overview` — 7 names; the spec lists goals_overview/bills_overview as one bullet "goals_overview() / bills_overview()", counted as 2 tools = 7 total, matching Task 4's `length 7`).
- **Placeholder scan:** Task 2 Step 3 contains a stub `group(...)` helper that is explicitly marked for removal — the four inlined queries are the real implementation; the implementer must delete the stub. Task 5 Step 1's `BudgetsRepository` import/method is given with a grep fallback. Task 6 Step 1's `null as dynamic` is given with a real-repo fallback. No other placeholders.
- **Type consistency:** `AiToolResult.body/amounts/names/isError` matches across executor (Task 5), runner (Task 6 consumes `result.amounts`/`result.names`/`result.body`), and the controller (Task 8). `AiGatekeeperBuilder` signature `(Set<double>, Set<String>) → AiGatekeeper` matches `_buildGatekeeper(mentionAmounts, mentionNames)` in the controller (Task 8 reuses it). `labelToId` (Task 1) flows: builder → `_buildContext` stores `_labelToId` → executor constructed with it (Task 8). `AiMentionData` directory fields (`categories`/`accounts`/`modes`/`tags`) match executor usage. Repo method names (`monthlyTotalsInRange`, `filteredTotals`, `categoryBreakdown`, `modeBreakdown`, `tagBreakdown`, `progressForMonth`) match their definitions/usage.
- **Track boundaries (per spec):** Phase 2 touches `lib/features/ai/tools/**` (new), `ai_chat_controller.dart` (`_streamReply` loop), `ai_prompts.dart` (new `kAskToolSystemPrompt`), `ai_context.dart` + `ai_payload_builder.dart` (labelToId — on-device only), `reports_repository.dart` (new methods), `prefs_service.dart`, `ai_providers.dart`, `ai_settings_section.dart`. The privacy-audit gate is mandatory (Task 9 Step 2).