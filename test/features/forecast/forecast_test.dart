import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/recurring_repository.dart';
import 'package:spendwise/data/repositories/reports_repository.dart';
import 'package:spendwise/data/repositories/transactions_repository.dart';
import 'package:spendwise/features/forecast/cashflow_forecast.dart';
import 'package:spendwise/features/forecast/run_rate.dart';

void main() {
  late AppDatabase db;
  late TransactionsRepository txRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    txRepo = TransactionsRepository(db);
  });

  tearDown(() => db.close());

  Future<String> catId() async =>
      (await db.categoriesDao.getAllActive()).firstWhere((c) => c.name == 'Food & Dining').id;
  Future<String> modeId() async =>
      (await db.modesDao.getAllActive()).firstWhere((m) => m.name == 'Online / UPI').id;
  Future<String> accId() async =>
      (await db.accountsDao.getAllActive()).firstWhere((a) => a.name == 'Cash').id;

  group('CashflowForecastService', () {
    test('empty month → hasData false', () async {
      final f = await CashflowForecastService(
              ReportsRepository(db), RecurringRepository(db))
          .computeMonthly();
      expect(f.hasData, isFalse);
      expect(f.mode, ForecastMode.monthly);
    });

    test('monthly: projects full-month expense from spend-so-far', () async {
      final cat = await catId();
      final mode = await modeId();
      final acc = await accId();
      final now = DateTime.now();
      // Spend 1000 today (day-of-month = daysElapsed).
      await txRepo.create(
          amount: 1000,
          transactionDate: now.toIso8601String(),
          accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');

      final f = await CashflowForecastService(
              ReportsRepository(db), RecurringRepository(db))
          .computeMonthly();
      expect(f.hasData, isTrue);
      expect(f.expenseSoFar, 1000);
      expect(f.daysElapsed, now.day);
      // projectedExpense = 1000 * daysInMonth / daysElapsed
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      expect(f.projectedExpense, closeTo(1000 * daysInMonth / now.day, 0.01));
      // Monthly does NOT extrapolate income → projectedIncome == incomeSoFar.
      expect(f.projectedIncome, f.incomeSoFar);
    });

    test('monthly: known bills due before month-end are listed', () async {
      final cat = await catId();
      final acc = await accId();
      final repo = RecurringRepository(db);
      // A bill due in 2 days (within this month if not the last day).
      await repo.create(
          name: 'Netflix',
          amount: 649,
          categoryId: cat,
          nextDueDate: DateTime.now().add(const Duration(days: 2)));
      // A bill due far out (outside the month) — 40 days ahead.
      await repo.create(
          name: 'FarBill',
          amount: 100,
          categoryId: cat,
          nextDueDate: DateTime.now().add(const Duration(days: 40)));
      // Need some expense so hasData is true.
      await txRepo.create(
          amount: 50,
          transactionDate: DateTime.now().toIso8601String(),
          accountId: acc,
          categoryId: cat,
          modeId: await modeId(),
          kind: 'expense');

      final f = await CashflowForecastService(
              ReportsRepository(db), repo)
          .computeMonthly();
      // Netflix (2 days) should be listed; FarBill only if month has 40+ days
      // left (never), so it must not appear.
      expect(f.billsDueBeforePeriodEnd, contains('Netflix'));
      expect(f.billsDueBeforePeriodEnd, isNot(contains('FarBill')));
    });

    test('sixMonths: projects balance 6 months out from 6-month pace',
        () async {
      final cat = await catId();
      final mode = await modeId();
      final acc = await accId();
      final now = DateTime.now();
      // Log income + expense today (this month) so there's current activity.
      await txRepo.create(
          amount: 5000,
          transactionDate: now.toIso8601String(),
          accountId: acc, categoryId: cat, modeId: mode, kind: 'income');
      await txRepo.create(
          amount: 1000,
          transactionDate: now.toIso8601String(),
          accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');

      final f = await CashflowForecastService(
              ReportsRepository(db), RecurringRepository(db))
          .computeSixMonths();
      expect(f.mode, ForecastMode.sixMonths);
      expect(f.hasData, isTrue);
      // daysElapsed/daysInPeriod are not meaningful for the 6-month view.
      expect(f.daysInPeriod, 0);
      expect(f.daysElapsed, 0);
      // projectedEnd = currentBalance + 6 * avgNet over last 6 completed months.
      // With no completed-month history, avgNet = 0 → projectedEnd == opening
      // (current balance).
      expect(f.projectedIncome, 0);
      expect(f.projectedExpense, 0);
      expect(f.projectedEnd, f.openingBalance);
    });

    test('dailyExpenseByDay groups expense by date in one query', () async {
      final cat = await catId();
      final mode = await modeId();
      final acc = await accId();
      final now = DateTime.now();
      await txRepo.create(
          amount: 100,
          transactionDate: now.toIso8601String(),
          accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');
      await txRepo.create(
          amount: 250,
          transactionDate: now.toIso8601String(),
          accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');
      // An income row must NOT appear in the expense map.
      await txRepo.create(
          amount: 9999,
          transactionDate: now.toIso8601String(),
          accountId: acc, categoryId: cat, modeId: mode, kind: 'income');

      final map = await ReportsRepository(db).dailyExpenseByDay(
          from: DateTime(now.year, now.month).toIso8601String(),
          to: DateTime(now.year, now.month + 1).toIso8601String());
      final key =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      expect(map[key], 350); // 100 + 250, income excluded.
      expect(map.length, greaterThanOrEqualTo(1));
    });
  });

  group('RunRateService', () {
    test('no trailing history → empty observations', () async {
      final obs = await RunRateService(ReportsRepository(db)).topObservations();
      expect(obs, isEmpty);
    });

    test('computes ratio vs typical-by-now', () async {
      final cat = await catId();
      final mode = await modeId();
      final acc = await accId();
      final now = DateTime.now();
      final todayDay = now.day;

      // Two trailing months with spend up to todayDay: 400 each → typical 400.
      for (final monthsAgo in [1, 2]) {
        final d = DateTime(now.year, now.month - monthsAgo, todayDay.clamp(1, 28));
        await txRepo.create(
            amount: 400,
            transactionDate: d.toIso8601String(),
            accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');
      }
      // This month: 800 (2x typical).
      await txRepo.create(
          amount: 800,
          transactionDate: now.toIso8601String(),
          accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');

      final obs = await RunRateService(ReportsRepository(db)).topObservations();
      expect(obs, isNotEmpty);
      final food = obs.firstWhere((o) => o.categoryName == 'Food & Dining');
      expect(food.typical, closeTo(400, 0.01));
      expect(food.actual, closeTo(800, 0.01));
      expect(food.ratio, closeTo(2.0, 0.01));
      // 2.0 → "Running higher than usual" (>1.3).
      expect(food.label, 'Running higher than usual');
    });
  });
}