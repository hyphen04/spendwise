import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/models/budget_progress.dart';
import 'package:spendwise/data/models/report_models.dart';
import 'package:spendwise/features/ai/domain/ai_payload_builder.dart';

// Reuses the same fixture shape as ai_payload_builder_test.dart, adapted for
// buildReportContext (which also takes topExpenseCategories + modeBreakdown).

MonthlySummary _summary({
  double income = 85000,
  double expense = 62000,
  String? biggestSpendNote = 'bought a surprise gift for mom',
}) {
  return MonthlySummary(
    income: income,
    expense: expense,
    topExpenseCategories: const [
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

Budget _budget({required String categoryId, required double amount}) => Budget(
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

ModeTotal _mode(String id, String name, double total) =>
    ModeTotal(modeId: id, name: name, icon: '💳', total: total);

void main() {
  group('AiPayloadBuilder.buildReportContext — privacy boundary (anonymized)',
      () {
    final builder = AiPayloadBuilder(); // shareNames = false

    Map<String, Object?> build() => builder.buildReportContext(
          summary: _summary(),
          budgets: [
            _progress(
                categoryId: 'c-food',
                name: 'Food & Dining',
                amount: 15000,
                spent: 18000),
          ],
          cashflow: [
            _m(2026, 2, 80000, 60000),
            _m(2026, 7, 85000, 62000),
          ],
          topExpenseCategories: const [
            CategoryTotal(
                categoryId: 'c-food',
                name: 'Food & Dining',
                icon: '🍔',
                color: '#059669',
                total: 18000),
          ],
          modeBreakdown: [
            _mode('m-upi', 'UPI', 52000),
            _mode('m-card', 'HDFC Card', 10000),
          ],
          period: '2026-07',
        ).json;

    test('serialized payload contains NO note text or single-transaction data',
        () {
      final json = jsonEncode(build());
      expect(json, isNot(contains('surprise gift')));
      expect(json, isNot(contains('mom')));
      expect(json, isNot(contains('Home Rent')));
    });

    test('contains NO real category, account, or mode names when anonymized',
        () {
      final json = jsonEncode(build());
      expect(json, isNot(contains('Food & Dining')));
      expect(json, isNot(contains('UPI')));
      expect(json, isNot(contains('HDFC Card')));
    });

    test('uses opaque rank keys for categories and modes', () {
      final payload = build();
      final cats = payload['top_expense_categories']! as List;
      expect((cats[0] as Map)['id'], 'cat_0');
      final modes = payload['payment_modes']! as List;
      expect((modes[0] as Map)['id'], 'mode_0');
      expect((modes[1] as Map)['id'], 'mode_1');
    });

    test('emits no legend when anonymized', () {
      expect(build().containsKey('legend'), isFalse);
    });

    test('returns a non-empty on-device legend even when anonymized', () {
      final ctx = builder.buildReportContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        topExpenseCategories: const [
          CategoryTotal(
              categoryId: 'c-food',
              name: 'Food & Dining',
              icon: '🍔',
              color: '#059669',
              total: 18000),
        ],
        modeBreakdown: [_mode('m-upi', 'UPI', 52000)],
        period: '2026-07',
      );
      expect(ctx.json.containsKey('legend'), isFalse);
      expect(ctx.legend, isNotEmpty);
      expect(ctx.legend['cat_0'], 'Food & Dining');
      expect(ctx.legend['mode_0'], 'UPI');
    });

    test('includes opening/closing balance and payment_modes', () {
      final payload = build();
      final summary = payload['summary']! as Map;
      expect(summary['opening_balance'], 100000.0);
      expect(summary['closing_balance'], 123000.0);
      expect((payload['payment_modes']! as List).length, 2);
    });

    test('no note/phone/photo keys anywhere in the payload', () {
      final json = jsonEncode(build());
      expect(json, isNot(contains('"note"')));
      expect(json, isNot(contains('"phone"')));
      expect(json, isNot(contains('"photo"')));
    });
  });

  group('AiPayloadBuilder.buildReportContext — share-names mode', () {
    final builder = AiPayloadBuilder(shareNames: true);

    test('attaches a legend with category + mode names', () {
      final payload = builder.buildReportContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        topExpenseCategories: const [
          CategoryTotal(
              categoryId: 'c-food',
              name: 'Food & Dining',
              icon: '🍔',
              color: '#059669',
              total: 18000),
        ],
        modeBreakdown: [_mode('m-upi', 'UPI', 52000)],
        period: '2026-07',
      ).json;
      final legend = payload['legend']! as Map;
      expect(legend['cat_0'], 'Food & Dining');
      expect(legend['mode_0'], 'UPI');
    });

    test('still drops notes even when names are shared', () {
      final json = jsonEncode(builder.buildReportContext(
        summary: _summary(),
        budgets: const [],
        cashflow: const [],
        topExpenseCategories: const [],
        modeBreakdown: const [],
        period: '2026-07',
      ).json);
      expect(json, isNot(contains('surprise gift')));
      expect(json, isNot(contains('mom')));
    });
  });
}