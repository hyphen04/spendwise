import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/budget_progress.dart';
import 'package:spendwise/data/models/report_models.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/features/ai/domain/ai_payload_builder.dart';
import 'package:spendwise/features/ai/domain/ai_mention_resolver.dart';

// Fixtures shared in shape with the other payload builder tests.

MonthlySummary _summary({List<CategoryTotal>? topCats}) => MonthlySummary(
      income: 85000,
      expense: 62000,
      topExpenseCategories: topCats ??
          [
            CategoryTotal(
                categoryId: 'c-food',
                name: 'Food & Dining',
                icon: '🍔',
                color: '#059669',
                total: 18000),
            CategoryTotal(
                categoryId: 'c-rent',
                name: 'Home Rent',
                icon: '🏠',
                color: '#475569',
                total: 9000),
          ],
      biggestSpendNote: null,
      openingBalance: 100000,
      closingBalance: 123000,
    );

BudgetProgress _progress() => BudgetProgress(
      budget: Budget(
          id: 'b-food',
          categoryId: 'c-food',
          accountId: null,
          period: 'month',
          amount: 15000,
          startDate: '2026-01-01',
          createdAt: 0,
          updatedAt: 0),
      spent: 18000,
      month: DateTime(2026, 7, 15),
      category: Category(
          id: 'c-food',
          name: 'Food & Dining',
          icon: '📦',
          color: '#059669',
          kind: 'expense',
          isArchived: false,
          createdAt: 0,
          updatedAt: 0),
    );

MonthTotal _m(int y, int mo, double income, double expense) =>
    MonthTotal(year: y, month: mo, income: income, expense: expense);

ModeTotal _mode(String id, String name, double total) =>
    ModeTotal(modeId: id, name: name, icon: '💳', total: total);

TagTotal _tag(String id, String name, double total) =>
    TagTotal(tagId: id, name: name, color: '#475569', total: total);

AccountBalance _acc(String id, String name, double balance) =>
    (id: id, name: name, balance: balance);

GoalSummary _goal({
  String id = 'g1',
  String name = 'New Phone',
  double target = 60000,
  double saved = 15000,
  int? monthsLeft = 10,
  double? monthlyCommitment = 4500,
}) =>
    (
      id: id,
      name: name,
      target: target,
      saved: saved,
      monthsLeft: monthsLeft,
      monthlyCommitment: monthlyCommitment,
    );

BillSummary _bill({
  String id = 'r1',
  String name = 'Netflix',
  double amount = 649,
  String cadence = 'monthly',
  int? nextDueInDays = 5,
  String source = 'manual',
}) =>
    (
      id: id,
      name: name,
      amount: amount,
      cadence: cadence,
      nextDueInDays: nextDueInDays,
      source: source,
    );

void main() {
  group('AiPayloadBuilder — goals (anonymized)', () {
    final builder = AiPayloadBuilder(); // shareNames = false

    test('emits goal_N labels with figures only — no name/icon/note', () {
      final payload = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        goals: [
          _goal(name: 'New Phone', target: 60000, saved: 15000),
          _goal(id: 'g2', name: 'Japan Trip', target: 200000, saved: 50000),
        ],
      ).json;
      final goals = payload['goals']! as List;
      expect(goals.length, 2);
      expect((goals[0] as Map)['id'], 'goal_0');
      expect((goals[1] as Map)['id'], 'goal_1');
      expect((goals[0] as Map)['target'], 60000.0);
      expect((goals[0] as Map)['saved'], 15000.0);
      expect((goals[0] as Map)['pct'], 25.0);
      expect((goals[0] as Map)['months_left'], 10);
      expect((goals[0] as Map)['monthly_commitment'], 4500.0);

      final json = jsonEncode(payload);
      expect(json, isNot(contains('New Phone')));
      expect(json, isNot(contains('Japan Trip')));
      expect(json, isNot(contains('"icon"')));
      expect(json, isNot(contains('"note"')));
    });

    test('omits months_left / monthly_commitment when null', () {
      final payload = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        goals: [_goal(monthsLeft: null, monthlyCommitment: null)],
      ).json;
      final g = (payload['goals']! as List)[0] as Map;
      expect(g.containsKey('months_left'), isFalse);
      expect(g.containsKey('monthly_commitment'), isFalse);
    });

    test('no legend when anonymized; on-device legend records goal names', () {
      final ctx = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        goals: [_goal(name: 'New Phone')],
      );
      expect(ctx.json.containsKey('legend'), isFalse);
      expect(ctx.legend['goal_0'], 'New Phone');
    });
  });

  group('AiPayloadBuilder — recurring_bills (anonymized)', () {
    final builder = AiPayloadBuilder();

    test('emits bill_N labels with amount/cadence/source — no name/note', () {
      final payload = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        recurringBills: [
          _bill(name: 'Netflix', amount: 649),
          _bill(id: 'r2', name: 'Electricity', amount: 1200, cadence: 'quarterly'),
        ],
      ).json;
      final bills = payload['recurring_bills']! as List;
      expect(bills.length, 2);
      expect((bills[0] as Map)['id'], 'bill_0');
      expect((bills[1] as Map)['id'], 'bill_1');
      expect((bills[0] as Map)['amount'], 649.0);
      expect((bills[0] as Map)['cadence'], 'monthly');
      expect((bills[0] as Map)['next_due_in_days'], 5);
      expect((bills[0] as Map)['source'], 'manual');

      final json = jsonEncode(payload);
      expect(json, isNot(contains('Netflix')));
      expect(json, isNot(contains('Electricity')));
      expect(json, isNot(contains('"note"')));
    });

    test('on-device legend records bill names even when anonymized', () {
      final ctx = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        recurringBills: [_bill(name: 'Netflix')],
      );
      expect(ctx.json.containsKey('legend'), isFalse);
      expect(ctx.legend['bill_0'], 'Netflix');
    });
  });

  group('AiPayloadBuilder — account_balances + tags (anonymized)', () {
    final builder = AiPayloadBuilder();

    test('account_balances uses acc_N and omits names', () {
      final payload = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        accountBalances: [
          _acc('a1', 'HDFC Savings', 50000),
          _acc('a2', 'Cash', 5000),
        ],
      ).json;
      final accs = payload['account_balances']! as List;
      expect((accs[0] as Map)['id'], 'acc_0');
      expect((accs[1] as Map)['id'], 'acc_1');
      expect((accs[0] as Map)['balance'], 50000.0);
      final json = jsonEncode(payload);
      expect(json, isNot(contains('HDFC Savings')));
      expect(json, isNot(contains('Cash')));
    });

    test('tag_breakdown uses tag_N and omits names', () {
      final payload = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        allTags: const [
          (id: 't1', name: 'Essential'),
          (id: 't2', name: 'Optional'),
        ],
        tagBreakdown: [
          _tag('t1', 'Essential', 30000),
          _tag('t2', 'Optional', 12000),
        ],
      ).json;
      final tags = payload['tag_breakdown']! as List;
      expect((tags[0] as Map)['id'], 'tag_0');
      expect((tags[1] as Map)['id'], 'tag_1');
      expect((tags[0] as Map)['amount'], 30000.0);
      final json = jsonEncode(payload);
      expect(json, isNot(contains('Essential')));
      expect(json, isNot(contains('Optional')));
    });
  });

  group('AiPayloadBuilder — category_trend_3mo + tx_frequency + day_distribution',
      () {
    final builder = AiPayloadBuilder();

    test('category_trend_3mo emits per-month amounts for top categories', () {
      // The standalone category_trend_3mo field lives on buildReportContext
      // (Ask folds trend into categories[].trend_3mo instead). Verifying the
      // standalone field here preserves the test's original intent.
      final payload = builder.buildReportContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        topExpenseCategories: [
          CategoryTotal(
              categoryId: 'c-food',
              name: 'Food',
              icon: '🍔',
              color: '#059669',
              total: 18000),
        ],
        modeBreakdown: const [],
        period: '2026-07',
        categoryBreakdown3mo: [
          [CategoryTotal(categoryId: 'c-food', name: 'Food', icon: '🍔', color: '#059669', total: 12000)],
          [CategoryTotal(categoryId: 'c-food', name: 'Food', icon: '🍔', color: '#059669', total: 15000)],
          [CategoryTotal(categoryId: 'c-food', name: 'Food', icon: '🍔', color: '#059669', total: 18000)],
        ],
      ).json;
      final trend = payload['category_trend_3mo']! as List;
      // Top category (c-food) → one entry with 3 months.
      expect(trend.length, greaterThanOrEqualTo(1));
      final first = trend[0] as Map;
      expect(first['id'], 'cat_0');
      expect(first['months'], [12000.0, 15000.0, 18000.0]);
    });

    test('category_trend_3mo omitted when not exactly 3 breakdowns', () {
      final payload = builder.buildReportContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        topExpenseCategories: [
          CategoryTotal(
              categoryId: 'c-food',
              name: 'Food',
              icon: '🍔',
              color: '#059669',
              total: 12000),
        ],
        modeBreakdown: const [],
        period: '2026-07',
        categoryBreakdown3mo: [
          [CategoryTotal(categoryId: 'c-food', name: 'Food', icon: '🍔', color: '#059669', total: 12000)],
        ],
      ).json;
      expect(payload.containsKey('category_trend_3mo'), isFalse);
    });

    test('tx_frequency emits count + per_day_avg', () {
      final payload = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        expenseCount: 120,
        daysInPeriod: 30,
      ).json;
      final f = payload['tx_frequency']! as Map;
      expect(f['expense_count'], 120);
      expect(f['per_day_avg'], 4.0);
    });

    test('day_distribution buckets spend by day-of-month thirds', () {
      final payload = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        dailyExpenseByDay: {
          '2026-07-03': 1000,
          '2026-07-15': 2000,
          '2026-07-25': 3000,
        },
      ).json;
      final dist = payload['day_distribution']! as List;
      expect(dist.length, 3);
      final byBucket = {
        for (final b in dist) (b as Map)['bucket'] as String: (b)['amount'] as double,
      };
      expect(byBucket['1-10'], 1000.0);
      expect(byBucket['11-20'], 2000.0);
      expect(byBucket['21-31'], 3000.0);
    });
  });

  group('AiPayloadBuilder — payment_modes now in Ask too', () {
    test('Ask context includes payment_modes when supplied', () {
      final payload = AiPayloadBuilder().buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        allModes: const [
          (id: 'm-upi', name: 'UPI'),
          (id: 'm-card', name: 'HDFC Card'),
        ],
        modeBreakdown: [
          _mode('m-upi', 'UPI', 52000),
          _mode('m-card', 'HDFC Card', 10000),
        ],
      ).json;
      final modes = payload['payment_modes']! as List;
      expect(modes.length, 2);
      expect((modes[0] as Map)['id'], 'mode_0');
      expect((modes[1] as Map)['id'], 'mode_1');
      // Anonymized → no real mode names in JSON.
      final json = jsonEncode(payload);
      expect(json, isNot(contains('UPI')));
      expect(json, isNot(contains('HDFC Card')));
    });
  });

  group('AiPayloadBuilder — share-names legend includes goals + bills', () {
    final builder = AiPayloadBuilder(shareNames: true);

    test('legend maps goal_N / bill_N to real names', () {
      final payload = builder.buildAskContext(
        summary: _summary(),
        budgets: [_progress()],
        cashflow: [_m(2026, 6, 80000, 60000)],
        period: '2026-07',
        allModes: const [(id: 'm-upi', name: 'UPI')],
        allTags: const [(id: 't1', name: 'Essential')],
        modeBreakdown: [_mode('m-upi', 'UPI', 52000)],
        accountBalances: [_acc('a1', 'HDFC Savings', 50000)],
        tagBreakdown: [_tag('t1', 'Essential', 30000)],
        goals: [_goal(name: 'New Phone')],
        recurringBills: [_bill(name: 'Netflix')],
      ).json;
      final legend = payload['legend']! as Map;
      expect(legend['cat_0'], 'Food & Dining');
      expect(legend['mode_0'], 'UPI');
      expect(legend['acc_0'], 'HDFC Savings');
      expect(legend['tag_0'], 'Essential');
      expect(legend['goal_0'], 'New Phone');
      expect(legend['bill_0'], 'Netflix');
    });
  });

  group('AiPayloadBuilder.collectAmounts', () {
    test('recursively gathers every numeric value in the payload', () {
      final ctx = AiPayloadBuilder().buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        goals: [_goal(target: 60000, saved: 15000)],
        recurringBills: [_bill(amount: 649)],
      );
      final amounts = AiPayloadBuilder.collectAmounts(ctx.json);
      // income/expense/net + goal target/saved/pct + bill amount are all in.
      expect(amounts, contains(85000.0));
      expect(amounts, contains(62000.0));
      expect(amounts, contains(60000.0));
      expect(amounts, contains(15000.0));
      expect(amounts, contains(649.0));
    });
  });
}