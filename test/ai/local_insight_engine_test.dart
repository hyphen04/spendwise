import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/models/budget_progress.dart';
import 'package:spendwise/data/models/report_models.dart';
import 'package:spendwise/features/ai/domain/local_insight_engine.dart';

/// Helpers to build minimal domain objects for the detectors. The Drift
/// `Budget`/`Category` classes are generated; we construct only the fields the
/// engine reads (amount, period, categoryId, startDate for Budget; name, icon,
/// color for Category).

Budget _budget({
  required String categoryId,
  required double amount,
  String period = 'month',
  String startDate = '2026-01-01',
}) {
  return Budget(
    id: 'b-$categoryId',
    categoryId: categoryId,
    accountId: null,
    period: period,
    amount: amount,
    startDate: startDate,
    createdAt: 0,
    updatedAt: 0,
  );
}

Category _category(String name) =>
    Category(id: name, name: name, icon: '📦', color: '#059669', kind: 'expense',
        isArchived: false, createdAt: 0, updatedAt: 0);

BudgetProgress _progress({
  required String categoryId,
  required String name,
  required double amount,
  required double spent,
  DateTime? month,
  String period = 'month',
}) {
  final m = month ?? DateTime(2026, 7, 15);
  return BudgetProgress(
    budget: _budget(categoryId: categoryId, amount: amount, period: period),
    spent: spent,
    month: m,
    category: _category(name),
  );
}

CategoryTotal _cat(String id, String name, double total) =>
    CategoryTotal(categoryId: id, name: name, icon: '📦', color: '#059669', total: total);

MonthTotal _month(int y, int m, double income, double expense) =>
    MonthTotal(year: y, month: m, income: income, expense: expense);

ExportRow _expense(String date, double amount,
        {String category = 'Food', String mode = 'Card'}) =>
    ExportRow(
        id: 'e-$date-$amount',
        amount: amount,
        date: date,
        kind: 'expense',
        accountName: 'Acc',
        categoryName: category,
        modeName: mode,
        createdAt: 0);

void main() {
  // ── Budget trajectory ──────────────────────────────────────────────────

  group('budgetTrajectory', () {
    test('does not project before day 5 of the month', () {
      final insights = LocalInsightEngine.budgetTrajectory(
        [_progress(categoryId: 'c1', name: 'Food', amount: 10000, spent: 4000)],
        DateTime(2026, 7, 3), // day 3 → guard fires, no projection
      );
      expect(insights, isEmpty);
    });

    test('warns when on track to exceed budget', () {
      // Day 15 of a 31-day month. Spent 6000 by day 15 → rate 400/day →
      // projected 12400 > 10000 budget.
      final insights = LocalInsightEngine.budgetTrajectory(
        [_progress(categoryId: 'c1', name: 'Food', amount: 10000, spent: 6000)],
        DateTime(2026, 7, 15),
      );
      expect(insights.length, 1);
      expect(insights.first.severity, InsightSeverity.warning);
      expect(insights.first.title, contains('on track to exceed'));
      expect(insights.first.body, contains('12.4K'));
    });

    test('reports an over-budget breach directly', () {
      final insights = LocalInsightEngine.budgetTrajectory(
        [_progress(categoryId: 'c1', name: 'Food', amount: 10000, spent: 12000)],
        DateTime(2026, 7, 15),
      );
      expect(insights.length, 1);
      expect(insights.first.title, contains('over budget'));
      expect(insights.first.body, contains('2.0K')); // 12000-10000 → ₹2.0K
    });

    test('stays quiet when spend is within pace', () {
      final insights = LocalInsightEngine.budgetTrajectory(
        [_progress(categoryId: 'c1', name: 'Food', amount: 10000, spent: 2000)],
        DateTime(2026, 7, 15),
      );
      expect(insights, isEmpty);
    });
  });

  // ── Spending spikes ────────────────────────────────────────────────────

  group('spendingSpikes', () {
    test('flags a category well above its 3-month average', () {
      final current = [_cat('c1', 'Food', 9000)];
      // Trailing mean for Food = (2000+3000+2500)/3 = 2500. 9000 > 1.5*2500 and
      // 9000-2500 = 6500 > absolute floor 500.
      final trailing = [
        [_cat('c1', 'Food', 2000)],
        [_cat('c1', 'Food', 3000)],
        [_cat('c1', 'Food', 2500)],
      ];
      final insights = LocalInsightEngine.spendingSpikes(current, trailing);
      expect(insights.length, 1);
      expect(insights.first.title, contains('Food spending spiked'));
      expect(insights.first.body, contains('260%')); // (9000-2500)/2500 = 260%
    });

    test('does not flag a small absolute jump even if relative threshold met', () {
      // Trailing mean 50, current 200 → 4× but extra = 150 < 500 floor.
      final current = [_cat('c1', 'Snacks', 200)];
      final trailing = [
        [_cat('c1', 'Snacks', 50)],
        [_cat('c1', 'Snacks', 50)],
        [_cat('c1', 'Snacks', 50)],
      ];
      expect(LocalInsightEngine.spendingSpikes(current, trailing), isEmpty);
    });

    test('flags a genuinely new category above the new-category floor', () {
      final current = [_cat('c2', 'Travel', 5000)];
      final trailing = [
        <CategoryTotal>[],
        <CategoryTotal>[],
        <CategoryTotal>[],
      ];
      final insights = LocalInsightEngine.spendingSpikes(current, trailing);
      expect(insights.length, 1);
      expect(insights.first.title, contains('New spending: Travel'));
    });
  });

  // ── Recurring payments ─────────────────────────────────────────────────

  group('recurringPayments', () {
    test('detects a monthly subscription', () {
      final rows = [
        _expense('2026-02-10T08:00:00.000', 199.0),
        _expense('2026-03-10T08:00:00.000', 199.0),
        _expense('2026-04-10T08:00:00.000', 199.0),
        _expense('2026-05-10T08:00:00.000', 199.0),
      ];
      final insights = LocalInsightEngine.recurringPayments(rows);
      expect(insights.length, 1);
      expect(insights.first.title, contains('recurring charge'));
      expect(insights.first.body, contains('monthly'));
    });

    test('ignores irregular one-off payments', () {
      final rows = [
        _expense('2026-02-03T08:00:00.000', 199.0),
        _expense('2026-03-19T08:00:00.000', 199.0), // 44-day gap
        _expense('2026-04-02T08:00:00.000', 199.0), // 14-day gap — too irregular
        _expense('2026-05-21T08:00:00.000', 199.0),
      ];
      expect(LocalInsightEngine.recurringPayments(rows), isEmpty);
    });

    test('ignores varying amounts', () {
      final rows = [
        _expense('2026-02-10T08:00:00.000', 199.0),
        _expense('2026-03-10T08:00:00.000', 4000.0), // wildly different
        _expense('2026-04-10T08:00:00.000', 199.0),
        _expense('2026-05-10T08:00:00.000', 199.0),
      ];
      expect(LocalInsightEngine.recurringPayments(rows), isEmpty);
    });

    test('requires at least 3 occurrences', () {
      final rows = [
        _expense('2026-03-10T08:00:00.000', 199.0),
        _expense('2026-04-10T08:00:00.000', 199.0),
      ];
      expect(LocalInsightEngine.recurringPayments(rows), isEmpty);
    });
  });

  // ── Savings trend ──────────────────────────────────────────────────────

  group('savingsTrend', () {
    test('celebrates a high, rising savings rate', () {
      // Income 100k each month; net (savings) rising 10k→20k→30k over 6 months.
      final cashflow = [
        _month(2026, 2, 100000, 90000), // 10%
        _month(2026, 3, 100000, 88000), // 12%
        _month(2026, 4, 100000, 85000), // 15%
        _month(2026, 5, 100000, 80000), // 20%
        _month(2026, 6, 100000, 75000), // 25%
        _month(2026, 7, 100000, 70000), // 30%
      ];
      final insights = LocalInsightEngine.savingsTrend(cashflow);
      expect(insights.length, 1);
      expect(insights.first.severity, InsightSeverity.positive);
      expect(insights.first.body, contains('30%'));
    });

    test('flags a falling savings rate', () {
      // Savings rate dropping: 30% → 10% over the window.
      final cashflow = [
        _month(2026, 2, 100000, 70000), // 30%
        _month(2026, 3, 100000, 72000), // 28%
        _month(2026, 4, 100000, 78000), // 22%
        _month(2026, 5, 100000, 82000), // 18%
        _month(2026, 6, 100000, 88000), // 12%
        _month(2026, 7, 100000, 90000), // 10%
      ];
      final insights = LocalInsightEngine.savingsTrend(cashflow);
      expect(insights.length, 1);
      expect(insights.first.severity, InsightSeverity.warning);
      expect(insights.first.title, contains('slipping'));
    });

    test('stays quiet with too little data', () {
      final cashflow = [
        _month(2026, 6, 100000, 70000),
        _month(2026, 7, 100000, 75000),
      ];
      expect(LocalInsightEngine.savingsTrend(cashflow), isEmpty);
    });
  });
}