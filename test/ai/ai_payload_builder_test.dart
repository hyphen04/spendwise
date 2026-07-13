import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/models/budget_progress.dart';
import 'package:spendwise/data/models/report_models.dart';
import 'package:spendwise/features/ai/domain/ai_payload_builder.dart';

MonthlySummary _summary({
  double income = 85000,
  double expense = 62000,
  String? biggestSpendNote = 'bought a surprise gift for mom',
  List<CategoryTotal>? topCats,
}) {
  return MonthlySummary(
    income: income,
    expense: expense,
    topExpenseCategories: topCats ?? [
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
    biggestSpendTitle: 'Home Rent',
    biggestSpendAmount: 9000,
    biggestSpendNote: biggestSpendNote,
    openingBalance: 100000,
    closingBalance: 123000,
  );
}

Budget _budget({required String categoryId, required double amount}) =>
    Budget(
        id: 'b-$categoryId',
        categoryId: categoryId,
        accountId: null,
        period: 'month',
        amount: amount,
        startDate: '2026-01-01',
        createdAt: 0,
        updatedAt: 0);

BudgetProgress _progress(
        {required String categoryId,
        required String name,
        required double amount,
        required double spent}) =>
    BudgetProgress(
      budget: _budget(categoryId: categoryId, amount: amount),
      spent: spent,
      month: DateTime(2026, 7, 15),
      category: Category(
          id: categoryId,
          name: name,
          icon: '📦',
          color: '#059669',
          kind: 'expense',
          isArchived: false,
          createdAt: 0,
          updatedAt: 0),
    );

MonthTotal _m(int y, int mo, double income, double expense) =>
    MonthTotal(year: y, month: mo, income: income, expense: expense);

void main() {
  group('AiPayloadBuilder — privacy boundary (default, anonymized)', () {
    final builder = AiPayloadBuilder(); // shareNames = false (default)

    Map<String, Object?> build() => builder.buildAskContext(
          summary: _summary(),
          budgets: [
            _progress(
                categoryId: 'c-food', name: 'Food & Dining', amount: 15000, spent: 18000),
          ],
          cashflow: [
            _m(2026, 2, 80000, 60000),
            _m(2026, 7, 85000, 62000),
          ],
          period: '2026-07',
        ).json;

    test('serialized payload contains NO note text', () {
      final json = jsonEncode(build());
      // The raw note we planted must never escape.
      expect(json, isNot(contains('surprise gift')));
      expect(json, isNot(contains('mom')));
      // The biggestSpendTitle (a category-by-name leak) must also be absent.
      expect(json, isNot(contains('Home Rent')));
    });

    test('contains NO real category or account names', () {
      final json = jsonEncode(build());
      expect(json, isNot(contains('Food & Dining')));
      expect(json, isNot(contains('Food')));
    });

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

    test('emits no legend when anonymized', () {
      final payload = build();
      expect(payload.containsKey('legend'), isFalse);
    });

    test('returns a non-empty on-device legend even when anonymized', () {
      // The legend is NOT in the JSON (above), but it IS returned to the caller
      // so AiGatekeeper can restore real names on-device. This pins the
      // invariant the gatekeeper relies on.
      final ctx = builder.buildAskContext(
        summary: _summary(),
        budgets: [
          _progress(
              categoryId: 'c-food', name: 'Food & Dining', amount: 15000, spent: 18000),
        ],
        cashflow: const [],
        period: '2026-07',
        allCategories: const [
          (id: 'c-food', name: 'Food & Dining'),
          (id: 'c-rent', name: 'Home Rent'),
        ],
      );
      expect(ctx.json.containsKey('legend'), isFalse);
      expect(ctx.legend, isNotEmpty);
      expect(ctx.legend['cat_0'], 'Food & Dining');
      expect(ctx.legend['cat_1'], 'Home Rent');
    });

    test('includes aggregates but not single-transaction details', () {
      final payload = build();
      expect((payload['summary'] as Map)['income'], 85000.0);
      expect((payload['summary'] as Map)['expense'], 62000.0);
      expect((payload['summary'] as Map)['net'], 23000.0);
      expect(payload['period'], '2026-07');
      // biggestSpend* fields are single-transaction → never present.
      expect(payload.containsKey('biggest_spend'), isFalse);
      expect(payload.containsKey('biggestSpendNote'), isFalse);
    });

    test('cashflow carries month + amounts, no notes', () {
      final cf = build()['cashflow_12mo']! as List;
      expect(cf.length, 2);
      final first = cf[0] as Map;
      expect(first['month'], '2026-02');
      expect(first.containsKey('note'), isFalse);
    });
  });

  group('AiPayloadBuilder — share-names mode', () {
    final builder = AiPayloadBuilder(shareNames: true);

    test('attaches a legend mapping rank keys to real names', () {
      final payload = builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        allCategories: const [
          (id: 'c-food', name: 'Food & Dining'),
          (id: 'c-rent', name: 'Home Rent'),
        ],
      ).json;
      final legend = payload['legend']! as Map;
      expect(legend['cat_0'], 'Food & Dining');
      expect(legend['cat_1'], 'Home Rent');
    });

    test('still drops notes even when names are shared', () {
      final json = jsonEncode(builder.buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
      ).json);
      expect(json, isNot(contains('surprise gift')));
      expect(json, isNot(contains('mom')));
    });
  });

  group('AiPayloadBuilder — edge cases', () {
    test('pct_of_expense is 0 when total expense is 0', () {
      final payload = AiPayloadBuilder().buildAskContext(
        summary: _summary(
          income: 0,
          expense: 0,
          topCats: [
            CategoryTotal(
                categoryId: 'c1',
                name: 'Food',
                icon: '🍔',
                color: '#059669',
                total: 0),
          ],
          biggestSpendNote: null,
        ),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
        allCategories: const [(id: 'c1', name: 'Food')],
      ).json;
      final cat = (payload['categories']! as List)[0] as Map;
      expect(cat['pct_of_expense'], 0.0);
    });

    test('omits the budgets key when there are no budgets', () {
      final payload = AiPayloadBuilder().buildAskContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        period: '2026-07',
      ).json;
      expect(payload.containsKey('budgets'), isFalse);
    });
  });

  group('savingsRateTrend', () {
    test('rising', () {
      expect(
        AiPayloadBuilder.savingsRateTrend([
          _m(2026, 2, 100000, 90000),
          _m(2026, 3, 100000, 85000),
          _m(2026, 4, 100000, 70000),
        ]),
        'rising',
      );
    });

    test('falling', () {
      expect(
        AiPayloadBuilder.savingsRateTrend([
          _m(2026, 2, 100000, 70000),
          _m(2026, 3, 100000, 85000),
          _m(2026, 4, 100000, 95000),
        ]),
        'falling',
      );
    });

    test('unknown with too little data', () {
      expect(AiPayloadBuilder.savingsRateTrend([_m(2026, 7, 100, 50)]), 'unknown');
    });
  });

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
      // Privacy: with shareNames off (default), no real category name — including
      // the 0-spend one — leaves the device, and no legend is embedded.
      expect(payload.containsKey('legend'), isFalse);
      final serialized = jsonEncode(payload);
      expect(serialized, isNot(contains('Fuel')));
      expect(serialized, isNot(contains('Food & Dining')));
      expect(serialized, isNot(contains('Home Rent')));
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
        modeBreakdown: const [ModeTotal(modeId: 'm-upi', name: 'UPI', icon: '', total: 40000)],
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
}