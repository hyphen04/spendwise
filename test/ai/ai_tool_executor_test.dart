import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/reports_repository.dart';
import 'package:spendwise/data/repositories/budgets_repository.dart';
import 'package:spendwise/features/ai/domain/ai_mention_resolver.dart';
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