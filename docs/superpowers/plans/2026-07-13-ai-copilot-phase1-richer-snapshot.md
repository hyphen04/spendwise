# AI Copilot Phase 1 — Richer Snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Ask chat AI see the full picture (all categories/modes/tags + counts + 12-month cashflow) instead of a top-5 current-month snapshot, so it can answer "how many categories do we have?" and "tell me about fuel" correctly.

**Architecture:** Extend `AiPayloadBuilder.buildAskContext` (chat only — the report narrative keeps top-5) to label and emit *every* active category/mode/tag (including 0-spend ones) with current-month amount + 3-month trend, plus entity counts and a 12-month cashflow. The full entity directory is already gathered on-device by `gatherAiMentionData`; reuse it. Privacy is unchanged — same aggregates + anonymized labels, just more of them; the legend still leaves only with `shareNames`.

**Tech Stack:** Flutter, Riverpod, Drift, pure-Dart unit tests (`flutter_test`). No new deps. No DB schema change.

## Global Constraints

- **Privacy invariant (primary):** only aggregates + anonymized labels leave the device. Never notes, contact names/phones/photos, receipt paths, raw rows, or real category/account/mode/tag/goal/bill names (anonymized to `cat_0`/`acc_1`/`mode_1`/`tag_1`/`goal_N`/`bill_N`; real names only with the opt-in `shareNames` toggle, restored on-device). `due_*`/`ai_*` tables and PII columns (`note`, `receipt_path`, `phone`, `phones`, `photo_path`, `device_contact_id`) are hard-blocked.
- **Scope:** chat only (`buildAskContext`). Do NOT change `buildReportContext` — the report narrative keeps its top-5 highlights.
- **TDD:** write the failing test first, watch it fail, implement, watch it pass, commit.
- **Tooling:** the engineer may run `flutter analyze lib/ test/` and `flutter test`. Run `dart format` if the project formats on commit (check the precommit hook).
- **Commit policy:** commit only when the user asks. If implementing on `main`, branch first (`git checkout -b ai-copilot-phase1`). Each task's commit step is conditional on the user having asked for commits — otherwise leave changes staged/unstaged and note it.
- **Entity record type:** the directory uses the existing typedef `AiEntityName = ({String id, String name})` from `lib/features/ai/domain/ai_mention_resolver.dart`.
- **Field renames in the chat payload JSON:** `top_expense_categories` → `categories`; `cashflow_6mo` → `cashflow_12mo`. Existing tests asserting the old names must be updated.

---

## File Structure

- **Modify** `lib/features/ai/domain/ai_payload_builder.dart` — `buildAskContext`: new `allCategories`/`allModes`/`allTags` params; emit `categories` (all, with `trend_3mo`), all `payment_modes`/`tag_breakdown`, `*_count` scalars, `cashflow_12mo`. New private helpers `_buildAllCategories`/`_buildAllModes`/`_buildAllTags`.
- **Modify** `lib/features/ai/services/ai_chat_controller.dart` — `_buildContext`: gather `mentionData` before building the payload; fetch 12-month cashflow; pass the directories to `buildAskContext`.
- **Modify** `lib/features/ai/domain/ai_prompts.dart` — `kAskSystemPrompt`: note the fuller picture (all categories/modes/tags, counts, 12-mo cashflow).
- **Modify** `test/ai/ai_payload_builder_test.dart` — update assertions for `categories` / `cashflow_12mo`; add all-categories + counts tests.
- **Modify** `test/ai/ai_payload_builder_extras_test.dart` — update any `cashflow_6mo`/`top_expense_categories` assertions (see Task 4).
- **No DB schema change. No new files.**

---

## Task 1: Builder — emit all categories with trend + counts (TDD)

**Files:**
- Modify: `lib/features/ai/domain/ai_payload_builder.dart` (`buildAskContext` + new helpers)
- Test: `test/ai/ai_payload_builder_test.dart`

**Interfaces:**
- Consumes: `AiEntityName = ({String id, String name})` (existing, from `ai_mention_resolver.dart`); `CategoryTotal` (`categoryId`, `name`, `total`); `ModeTotal` (`modeId`, `name`, `total`); `TagTotal` (`tagId`, `name`, `total`); `MonthTotal` (`year`, `month`, `income`, `expense`, `net`).
- Produces: `buildAskContext` gains three optional params `allCategories`/`allModes`/`allTags` (each `List<AiEntityName>`, default `const []`). The returned `AiContext.json` now has `categories` (replaces `top_expense_categories`), `cashflow_12mo` (replaces `cashflow_6mo`), and top-level `category_count`/`account_count`/`mode_count`/`tag_count`/`goal_count`/`bill_count`. `ctx.legend` still maps every label → real name (now including 0-spend entities).

- [ ] **Step 1: Write the failing tests**

Add to `test/ai/ai_payload_builder_test.dart` (inside `void main()`, new group). Also update the two existing assertions that use the old field names.

First, update the existing "uses opaque rank keys for categories" test (~line 106) to pass `allCategories` and assert `categories`:

```dart
test('uses opaque rank keys for categories', () {
  final payload = builder.buildAskContext(
    summary: _summary(topCats: const []),
    budgets: const [],
    cashflow: const [],
    period: '2026-07',
    allCategories: const [
      (id: 'c-food', name: 'Food & Dining'),
      (id: 'c-rent', name: 'Home Rent'),
    ],
  ).json;
  final cats = payload['categories']! as List;
  expect(cats.length, 2);
  final ids = cats.map((c) => (c as Map)['id'] as String).toSet();
  expect(ids, contains('cat_0'));
  expect(ids, contains('cat_1'));
});
```

Update the existing cashflow test (~line 152) to the new field name:

```dart
final cf = build()['cashflow_12mo']! as List;
expect(cf.length, 2);
```

Update the pct-of-expense test (~line 207) to read from `categories` and pass `allCategories`:

```dart
test('pct_of_expense is 0 when total expense is 0', () {
  final payload = builder.buildAskContext(
    summary: _summary(expense: 0, topCats: const []),
    budgets: const [],
    cashflow: const [],
    period: '2026-07',
    allCategories: const [(id: 'c-food', name: 'Food & Dining')],
  ).json;
  final cat = (payload['categories']! as List)[0] as Map;
  expect(cat['pct_of_expense'], 0.0);
});
```

Then add a new group for the Phase 1 behavior:

```dart
group('AiPayloadBuilder — richer snapshot (Phase 1)', () {
  final b = AiPayloadBuilder();

  test('categories lists every active category incl 0-spend, sorted by amount desc', () {
    final payload = b.buildAskContext(
      summary: _summary(expense: 62000, topCats: const []),
      budgets: const [],
      cashflow: const [],
      period: '2026-07',
      allCategories: const [
        (id: 'c-fuel', name: 'Fuel'), // 0 spend this month
        (id: 'c-food', name: 'Food & Dining'),
        (id: 'c-rent', name: 'Home Rent'),
      ],
      categoryBreakdown3mo: [
        const [CategoryTotal(categoryId: 'c-food', name: 'Food & Dining', icon: '', color: '', total: 18000)],
        const [CategoryTotal(categoryId: 'c-food', name: 'Food & Dining', icon: '', color: '', total: 16000)],
        const [CategoryTotal(categoryId: 'c-food', name: 'Food & Dining', icon: '', color: '', total: 18000),
          CategoryTotal(categoryId: 'c-rent', name: 'Home Rent', icon: '', color: '', total: 9000)],
      ],
    ).json;
    final cats = (payload['categories']! as List).cast<Map>();
    expect(cats.length, 3); // includes 0-spend Fuel
    // Sorted by current-month amount desc: food(18000) > rent(9000) > fuel(0).
    expect(cats[0]['amount'], 18000.0);
    expect(cats[2]['amount'], 0.0);
    // 0-spend category still got a label and is in the legend.
    final fuelEntry = cats.firstWhere((c) => c['amount'] == 0.0);
    expect(fuelEntry['id'], startsWith('cat_'));
  });

  test('each category has a uniform trend_3mo (zeros when no 3-mo data)', () {
    final payload = b.buildAskContext(
      summary: _summary(expense: 62000, topCats: const []),
      budgets: const [],
      cashflow: const [],
      period: '2026-07',
      allCategories: const [
        (id: 'c-food', name: 'Food & Dining'),
        (id: 'c-fuel', name: 'Fuel'),
      ],
      categoryBreakdown3mo: [
        const [CategoryTotal(categoryId: 'c-food', name: 'Food & Dining', icon: '', color: '', total: 16000)],
        const [CategoryTotal(categoryId: 'c-food', name: 'Food & Dining', icon: '', color: '', total: 17000)],
        const [CategoryTotal(categoryId: 'c-food', name: 'Food & Dining', icon: '', color: '', total: 18000)],
      ],
    ).json;
    final cats = (payload['categories']! as List).cast<Map>();
    final food = cats.firstWhere((c) => (c['amount'] as double) == 18000.0);
    expect(food['trend_3mo'], [16000.0, 17000.0, 18000.0]);
    final fuel = cats.firstWhere((c) => (c['amount'] as double) == 0.0);
    expect(fuel['trend_3mo'], [0.0, 0.0, 0.0]);
  });

  test('emits entity counts', () {
    final payload = b.buildAskContext(
      summary: _summary(topCats: const []),
      budgets: const [],
      cashflow: const [],
      period: '2026-07',
      allCategories: const [(id: 'c1', name: 'A'), (id: 'c2', name: 'B'), (id: 'c3', name: 'C')],
      allModes: const [(id: 'm1', name: 'UPI')],
      allTags: const [(id: 't1', name: 'work'), (id: 't2', name: 'home')],
      accountBalances: const [(id: 'a1', name: 'HDFC', balance: 1000)],
      goals: const [
        (id: 'g1', name: 'Phone', target: 60000, saved: 15000, monthsLeft: 10, monthlyCommitment: 4500),
      ],
      recurringBills: const [
        (id: 'b1', name: 'Netflix', amount: 649, cadence: 'monthly', nextDueInDays: 5, source: 'manual'),
        (id: 'b2', name: 'Rent', amount: 9000, cadence: 'monthly', nextDueInDays: 1, source: 'manual'),
      ],
    ).json;
    expect(payload['category_count'], 3);
    expect(payload['mode_count'], 1);
    expect(payload['tag_count'], 2);
    expect(payload['account_count'], 1);
    expect(payload['goal_count'], 1);
    expect(payload['bill_count'], 2);
  });

  test('payment_modes and tag_breakdown include 0-spend entities', () {
    final payload = b.buildAskContext(
      summary: _summary(expense: 62000, topCats: const []),
      budgets: const [],
      cashflow: const [],
      period: '2026-07',
      allModes: const [(id: 'm-upi', name: 'UPI'), (id: 'm-card', name: 'Card')],
      modeBreakdown: const [ModeTotal(modeId: 'm-upi', name: 'UPI', total: 40000)],
      allTags: const [(id: 't-work', name: 'work')],
      tagBreakdown: const [],
    ).json;
    final modes = (payload['payment_modes']! as List).cast<Map>();
    expect(modes.length, 2);
    final card = modes.firstWhere((m) => (m['amount'] as double) == 0.0);
    expect(card['id'], startsWith('mode_'));
    final tags = (payload['tag_breakdown']! as List).cast<Map>();
    expect(tags.length, 1);
    expect((tags[0])['amount'], 0.0);
  });

  test('cashflow_12mo field name replaces cashflow_6mo', () {
    final payload = b.buildAskContext(
      summary: _summary(topCats: const []),
      budgets: const [],
      cashflow: [_m(2026, 6, 80000, 55000), _m(2026, 7, 85000, 62000)],
      period: '2026-07',
    ).json;
    expect(payload.containsKey('cashflow_6mo'), isFalse);
    expect((payload['cashflow_12mo']! as List).length, 2);
  });

  test('legend includes 0-spend categories (restorable on-device)', () {
    final ctx = b.buildAskContext(
      summary: _summary(topCats: const []),
      budgets: const [],
      cashflow: const [],
      period: '2026-07',
      allCategories: const [(id: 'c-fuel', name: 'Fuel')],
    );
    expect(ctx.legend.values, contains('Fuel'));
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ai/ai_payload_builder_test.dart`
Expected: FAIL — `categories` key missing / `cashflow_12mo` missing / counts missing (the builder still emits `top_expense_categories` and `cashflow_6mo`).

- [ ] **Step 3: Implement the builder changes**

In `lib/features/ai/domain/ai_payload_builder.dart`:

Add `import 'ai_mention_resolver.dart';` at the top (for `AiEntityName`). Actually `AiEntityName` is defined in `ai_mention_resolver.dart` — import it. (If there is a circular-import concern: `ai_mention_resolver.dart` imports only `money_format.dart`, so importing it into the builder is safe.)

Add three params to `buildAskContext` (after `recurringBills`):

```dart
    List<AiEntityName> allCategories = const [],
    List<AiEntityName> allModes = const [],
    List<AiEntityName> allTags = const [],
```

Replace the `topCats` construction block (the `for (final c in summary.topExpenseCategories)` loop ~lines 88–96) and the `modes`/`tags`/`trendCats` lines (~121–125) with calls to the new helpers. The body of `buildAskContext` becomes (showing the changed region, starting after `final labeler = _Labeler(); final expense = summary.expense;`):

```dart
    final allCats = _buildAllCategories(allCategories, categoryBreakdown3mo, labeler, expense);
    final modes = _buildAllModes(allModes, modeBreakdown, labeler, expense);
    final accBalances = _buildAccountBalances(accountBalances, labeler);
    final tags = _buildAllTags(allTags, tagBreakdown, labeler, expense);
    final txFrequency = _buildTxFrequency(expenseCount, daysInPeriod);
    final dayDist = _buildDayDistribution(dailyExpenseByDay);
    final goalsList = _buildGoals(goals, labeler);
    final billsList = _buildBills(recurringBills, labeler);
```

(Delete the old `topCats`, `_buildModes`, `_buildTags`, `_buildCategoryTrend` call sites for Ask. Keep `_buildCategoryTrend` and `_buildModes`/`_buildTags` methods if `buildReportContext` still uses them — check: `buildReportContext` uses `_buildModes` and `_buildCategoryTrend`. So KEEP `_buildModes`/`_buildTags`/`_buildCategoryTrend` methods; only stop calling them from `buildAskContext`. Add the new `_buildAll*` methods.)

Update the returned `json` map: replace `'top_expense_categories': topCats,` with `'categories': allCats,`; replace `'cashflow_6mo': cashflowList,` with `'cashflow_12mo': cashflowList,`; remove the `'category_trend_3mo': trendCats,` line from Ask (trend is now inside `categories`); add the count scalars. The `json` map's relevant lines:

```dart
        'categories': allCats,
        if (modes.isNotEmpty) 'payment_modes': modes,
        if (accBalances.isNotEmpty) 'account_balances': accBalances,
        if (budgetList.isNotEmpty) 'budgets': budgetList,
        if (tags.isNotEmpty) 'tag_breakdown': tags,
        if (txFrequency != null) 'tx_frequency': txFrequency,
        if (dayDist.isNotEmpty) 'day_distribution': dayDist,
        if (goalsList.isNotEmpty) 'goals': goalsList,
        if (billsList.isNotEmpty) 'recurring_bills': billsList,
        'cashflow_12mo': cashflowList,
        'savings_rate_trend': savingsRateTrend(cashflow),
        'category_count': allCategories.length,
        'account_count': accountBalances.length,
        'mode_count': allModes.length,
        'tag_count': allTags.length,
        'goal_count': goals.length,
        'bill_count': recurringBills.length,
        if (shareNames && labeler.legend.isNotEmpty) 'legend': labeler.legend,
```

Note: `payment_modes`/`tag_breakdown`/`account_balances` keep their `if (…isNotEmpty)` gates — now they're non-empty whenever the directory is non-empty (even with all-zero amounts), which is the desired Phase 1 behavior (the AI sees all modes/tags). If you want 0-spend modes to always appear, drop the `isNotEmpty` gate for modes/tags — but keep it gated on the directory being non-empty. Simplest: change the gates to `if (allModes.isNotEmpty)` / `if (allTags.isNotEmpty)` / `if (accountBalances.isNotEmpty)`.

Add the three new private helpers (place them near `_buildModes`):

```dart
  /// Every active category (incl 0-spend), labeled, with current-month amount,
  /// pct of total expense, and a uniform 3-month trend (zeros when no 3-mo data
  /// was supplied). Sorted by current-month amount desc.
  List<Map<String, Object?>> _buildAllCategories(
      List<AiEntityName> all,
      List<List<CategoryTotal>> breakdown3mo,
      _Labeler labeler,
      double expense) {
    final has3 = breakdown3mo.length == 3;
    final currentMap = has3
        ? {for (final c in breakdown3mo[2]) c.categoryId: c.total}
        : const <String, double>{};
    final out = <Map<String, Object?>>[];
    for (final c in all) {
      final key = labeler.category(c.id, c.name);
      final amt = currentMap[c.id] ?? 0.0;
      final trend = has3
          ? breakdown3mo
              .map((m) => _round(
                  m.where((x) => x.categoryId == c.id).fold(0.0, (s, x) => s + x.total)))
              .toList()
          : [0.0, 0.0, 0.0];
      out.add({
        'id': key,
        'amount': _round(amt),
        'pct_of_expense': expense > 0 ? _round1(amt / expense * 100) : 0.0,
        'trend_3mo': trend,
      });
    }
    out.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    return out;
  }

  /// Every active payment mode (incl 0-spend), labeled, sorted by amount desc.
  List<Map<String, Object?>> _buildAllModes(
      List<AiEntityName> all,
      List<ModeTotal> modeBreakdown,
      _Labeler labeler,
      double expense) {
    final amtMap = {for (final m in modeBreakdown) m.modeId: m.total};
    final out = <Map<String, Object?>>[];
    for (final m in all) {
      final key = labeler.mode(m.id, m.name);
      final amt = amtMap[m.id] ?? 0.0;
      out.add({
        'id': key,
        'amount': _round(amt),
        'pct_of_expense': expense > 0 ? _round1(amt / expense * 100) : 0.0,
      });
    }
    out.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    return out;
  }

  /// Every active tag (incl 0-spend), labeled, sorted by amount desc.
  List<Map<String, Object?>> _buildAllTags(
      List<AiEntityName> all,
      List<TagTotal> tagBreakdown,
      _Labeler labeler,
      double expense) {
    final amtMap = {for (final t in tagBreakdown) t.tagId: t.total};
    final out = <Map<String, Object?>>[];
    for (final t in all) {
      final key = labeler.tag(t.id, t.name);
      final amt = amtMap[t.id] ?? 0.0;
      out.add({
        'id': key,
        'amount': _round(amt),
        'pct_of_expense': expense > 0 ? _round1(amt / expense * 100) : 0.0,
      });
    }
    out.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    return out;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ai/ai_payload_builder_test.dart`
Expected: PASS — all new + updated tests green.

- [ ] **Step 5: Commit (if the user has asked for commits)**

```bash
git add lib/features/ai/domain/ai_payload_builder.dart test/ai/ai_payload_builder_test.dart
git commit -m "feat(ai): chat payload lists all categories/modes/tags + counts + 12-mo cashflow (Phase 1)"
```

(If on `main`, branch first: `git checkout -b ai-copilot-phase1`.)

---

## Task 2: Wire the gatherer + controller to pass the full directory + 12-mo cashflow

**Files:**
- Modify: `lib/features/ai/services/ai_chat_controller.dart` (`_buildContext`)

**Interfaces:**
- Consumes: `gatherAiMentionData(...)` (existing, returns `AiMentionData` with `categories`/`accounts`/`modes`/`tags` `List<AiEntityName>`); `ReportsRepository.cashFlowMonths({int count = 6})` — call with `count: 12`; the new `buildAskContext` params `allCategories`/`allModes`/`allTags`.
- Produces: the chat context JSON now contains all categories/modes/tags + counts + 12-mo cashflow; the `AiMentionResolver` is still built from `mentionData` + `ctx.legend` (unchanged).

- [ ] **Step 1: Write the failing test (controller-level, if feasible without a full harness)**

The controller has no existing test harness (noted in the prior privacy audit). Rather than scaffold one for Phase 1, verify via the builder tests (Task 1) + a manual smoke. **Skip the failing-test step here** is NOT acceptable for TDD — instead, add a focused test that the wiring produces a 12-month cashflow by testing the repo contract is honored. Since `cashFlowMonths(count: 12)` is a repo method (DB-backed, not unit-testable without a Drift in-memory DB), and the existing test suite has no such harness, the pragmatic verification is:

- Run `flutter analyze lib/` (compile check) and `flutter test` (no regressions).
- Manual smoke (Task 5).

Document this deviation in the commit message ("wiring verified by analyze + builder tests + manual smoke; controller harness is a future gap").

- [ ] **Step 2: Implement the wiring**

In `lib/features/ai/services/ai_chat_controller.dart`, `_buildContext`:

Reorder so `mentionData` is gathered **before** `buildAskContext`, and fetch 12-month cashflow. Replace the relevant region (the `final cashflow = await repo.cashFlowMonths();` line and the `final extras = …` / `final builder = …` / `final ctx = builder.buildAskContext(...)` / `final mentionData = …` sequence) with:

```dart
    final List<MonthTotal> cashflow = await repo.cashFlowMonths(count: 12);

    final extras = await gatherAiContextExtras(
      reports: repo,
      goalsRepo: _ref.read(goalsRepositoryProvider),
      recurringRepo: _ref.read(recurringRepositoryProvider),
      year: now.year,
      month: now.month,
    );

    // Full entity directory (on-device only) — reused both for mention resolution
    // and now for the payload's all-categories/modes/tags.
    final mentionData = await gatherAiMentionData(
      db: _ref.read(appDatabaseProvider),
      modeBreakdown: modes,
      extras: extras,
    );

    final builder = AiPayloadBuilder(shareNames: config.shareNames);
    final ctx = builder.buildAskContext(
      summary: summary,
      budgets: budgets,
      cashflow: cashflow,
      period: '${now.year}-${now.month.toString().padLeft(2, '0')}',
      modeBreakdown: modes,
      accountBalances: extras.accountBalances,
      tagBreakdown: extras.tagBreakdown,
      categoryBreakdown3mo: extras.categoryBreakdown3mo,
      expenseCount: extras.expenseCount,
      daysInPeriod: extras.daysInPeriod,
      dailyExpenseByDay: extras.dailyExpenseByDay,
      goals: extras.goals,
      recurringBills: extras.recurringBills,
      allCategories: mentionData.categories,
      allModes: mentionData.modes,
      allTags: mentionData.tags,
    );
    _resolver = AiMentionResolver(data: mentionData, legend: ctx.legend);
```

(Delete the now-duplicate later `gatherAiMentionData` call that previously sat after `buildAskContext` — it has moved up. Keep the `_legend`/`_validLabels`/`_maxContextAmount`/`_baseAmounts`/`_shareNames` assignments and `_gatekeeper = _buildGatekeeper(const {}, const []);` exactly as they are, after `ctx` is built.)

- [ ] **Step 3: Run analyze + tests**

Run: `flutter analyze lib/ test/`
Expected: No issues.

Run: `flutter test`
Expected: All green (no regressions; builder tests still pass).

- [ ] **Step 4: Commit (if the user has asked for commits)**

```bash
git add lib/features/ai/services/ai_chat_controller.dart
git commit -m "feat(ai): wire full entity directory + 12-mo cashflow into chat context (Phase 1)"
```

---

## Task 3: Update the Ask system prompt for the fuller picture

**Files:**
- Modify: `lib/features/ai/domain/ai_prompts.dart` (`kAskSystemPrompt`)

**Interfaces:**
- Produces: a prompt that tells the LLM the summary lists **all** categories/modes/tags (including 0-spend) with `*_count` scalars and a 12-month cashflow, and to answer count questions from `*_count` and per-category questions from the `categories` list.

- [ ] **Step 1: Write the failing test**

Prompt strings are not unit-tested directly in this codebase (no existing prompt test). The verification is behavioral (manual smoke in Task 5). Add no test here; instead make the edit and verify by analyze.

- [ ] **Step 2: Implement the prompt edit**

In `lib/features/ai/domain/ai_prompts.dart`, in `kAskSystemPrompt`, update the opening paragraph and the relevant rules. Replace the first paragraph:

```dart
You are SpendWise's private money copilot. You are answering the user's
questions about their own spending, based ONLY on the anonymized financial
summary provided in the conversation. The summary uses opaque category ids like
"cat_0"; when a legend is provided, you may use the real names from it.
```

with:

```dart
You are SpendWise's private money copilot. You are answering the user's
questions about their own spending, based ONLY on the anonymized financial
summary provided in the conversation. The summary lists ALL of your categories,
payment modes, and tags (including ones with 0 spend this month) as opaque ids
like "cat_0", "mode_1", "tag_2"; it also includes `category_count`, `mode_count`,
`tag_count`, `account_count`, `goal_count`, and `bill_count` scalars and a
12-month cashflow. When a legend is provided, you may use the real names from it.
```

And in the rules, add a bullet after the "Base every answer strictly…" rule:

```dart
- Answer "how many X do I have" from the `*_count` scalars, not by counting list
  entries (the lists may be capped). Per-category questions: every category you
  have is in the `categories` list, including ones with 0 spend this month
  (amount 0, trend_3mo all zeros) — never claim a category "doesn't exist"; say
  it has no activity this month if its amount is 0.
```

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/`
Expected: No issues.

- [ ] **Step 4: Commit (if the user has asked for commits)**

```bash
git add lib/features/ai/domain/ai_prompts.dart
git commit -m "feat(ai): tell the Ask LLM about all-categories + counts + 12-mo cashflow (Phase 1)"
```

---

## Task 4: Update the extras payload test for the field renames

**Files:**
- Modify: `test/ai/ai_payload_builder_extras_test.dart`

**Interfaces:**
- Consumes: the renamed fields (`categories`, `cashflow_12mo`).

- [ ] **Step 1: Find any assertions on the old field names**

Run: `grep -n "top_expense_categories\|cashflow_6mo\|category_trend_3mo" test/ai/ai_payload_builder_extras_test.dart`
If matches: update them. `top_expense_categories` → `categories` (and pass `allCategories` in that test's `buildAskContext` call if it currently relies on `summary.topExpenseCategories`); `cashflow_6mo` → `cashflow_12mo`; `category_trend_3mo` references → trend is now inside `categories[].trend_3mo` (update or remove the assertion).

- [ ] **Step 2: Run the extras tests**

Run: `flutter test test/ai/ai_payload_builder_extras_test.dart`
Expected: PASS. If a test still references a removed field, update it per Step 1 and re-run.

- [ ] **Step 3: Commit (if the user has asked for commits)**

```bash
git add test/ai/ai_payload_builder_extras_test.dart
git commit -m "test(ai): update extras payload test for categories/cashflow_12mo renames (Phase 1)"
```

---

## Task 5: Full verify + privacy audit

**Files:** none (verification + audit)

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze lib/ test/`
Expected: No issues.

Run: `flutter test`
Expected: All tests pass (existing + new Phase 1 tests).

- [ ] **Step 2: Privacy audit (mandatory — touches the AI outbound path)**

Run the privacy auditor agent (or the `spendwise-privacy-audit` skill) on the Phase 1 diff. The auditor must confirm:
- No new data class leaves — only more aggregates + labels of the same kinds already sent.
- 0-spend category/mode/tag names are still anonymized by default (legend sent only with `shareNames`).
- No `note`/`receipt_path`/contact/`due_*`/`ai_*` access added.
- The legend still never leaves unless `shareNames`.

Expected: PASS, 0 blockers. If FAIL, fix before proceeding (hard merge blocker).

- [ ] **Step 3: Manual smoke**

With AI on + a key set, in the Ask chat:
- Ask "how many categories do we have?" → expect the real count (not 5).
- Ask "tell me about fuel" (a category with no/little spend this month) → expect a real answer using its current-month amount (incl. 0) + trend, not "no category named fuel".
- With `shareNames` off, confirm replies still restore real names on-device (gatekeeper) and no raw name leaks.
- With `shareNames` on, confirm all category names appear correctly.

- [ ] **Step 4: Update CHANGELOG + CLAUDE.md**

In `CHANGELOG.md` under `## Unreleased` → `### Added` (or `### Changed`), add a bullet describing Phase 1 (all categories/modes/tags + counts + 12-mo cashflow in the chat payload; fixes "how many categories" / "no category named fuel"). In `CLAUDE.md`, update the `AiPayloadBuilder` description in the AI Privacy Rules to note the chat payload now sends all entities + counts (privacy unchanged). Keep within the changelog parser's supported subset (no tables/fenced code).

- [ ] **Step 5: Final commit (if the user has asked for commits)**

```bash
git add CHANGELOG.md CLAUDE.md
git commit -m "docs(ai): changelog + CLAUDE.md for Phase 1 richer chat snapshot"
```

---

## Self-Review notes

- **Spec coverage:** Phase 1 spec items (all categories incl 0-spend, all modes/tags, counts, 12-mo cashflow, chat-only, prompt) → Tasks 1–3. Verify + audit → Task 5. Test updates → Tasks 1 & 4.
- **Type consistency:** `AiEntityName` used everywhere; `buildAskContext` param names `allCategories`/`allModes`/`allTags` match Task 1's signatures and Task 2's call site; field names `categories`/`cashflow_12mo`/`*_count` match across tests and prompt.
- **Placeholder scan:** Task 2 Step 2's "delete the now-duplicate later `gatherAiMentionData` call" — the implementer must locate the original call (currently after `buildAskContext` in `_buildContext`) and remove it since it moved up. Task 4 Step 1 is conditional on grep matches (explicit command given).