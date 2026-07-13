import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/reports_repository.dart';
import 'package:spendwise/data/repositories/transactions_repository.dart';
import 'package:spendwise/features/digest/weekly_digest.dart';

void main() {
  late AppDatabase db;
  late WeeklyDigestService service;
  late TransactionsRepository txRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    final reports = ReportsRepository(db);
    service = WeeklyDigestService(reports);
    txRepo = TransactionsRepository(db);
  });

  tearDown(() => db.close());

  Future<String> catId() async =>
      (await db.categoriesDao.getAllActive()).firstWhere((c) => c.name == 'Food & Dining').id;
  Future<String> modeId() async =>
      (await db.modesDao.getAllActive()).firstWhere((m) => m.name == 'Online / UPI').id;
  Future<String> accId() async =>
      (await db.accountsDao.getAllActive()).firstWhere((a) => a.name == 'Cash').id;

  test('empty history → zero spend, no prior week, gentle tip', () async {
    final d = await service.compute();
    expect(d.spentThisWeek, 0);
    expect(d.txnCountThisWeek, 0);
    expect(d.hasPriorWeek, isFalse);
    expect(d.deltaPct.isNaN, isTrue);
    expect(d.tip, isNotEmpty);
    expect(d.toShareText(), contains('SpendWise'));
  });

  test('this-week vs last-week split and delta', () async {
    final cat = await catId();
    final mode = await modeId();
    final acc = await accId();
    final now = DateTime.now();
    // Monday of this week.
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final lastWeek = monday.subtract(const Duration(days: 5));
    final thisWeek = monday.add(const Duration(days: 1));

    // Last week: 1000. This week: 500 + 300 = 800.
    await txRepo.create(
        amount: 1000,
        transactionDate: lastWeek.toIso8601String(),
        accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');
    await txRepo.create(
        amount: 500,
        transactionDate: thisWeek.toIso8601String(),
        accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');
    await txRepo.create(
        amount: 300,
        transactionDate: thisWeek.add(const Duration(days: 1)).toIso8601String(),
        accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');

    final d = await service.compute();
    expect(d.spentLastWeek, 1000);
    expect(d.spentThisWeek, 800);
    expect(d.txnCountThisWeek, 2);
    expect(d.hasPriorWeek, isTrue);
    // Down 20%.
    expect(d.deltaPct, closeTo(-0.20, 0.001));
    expect(d.topCategoryName, 'Food & Dining');
    expect(d.topCategoryAmount, 800);
    expect(d.toShareText(), contains('Food & Dining'));
    expect(d.toShareText(), contains('down 20%'));
  });

  test('income transactions are excluded (kind filter)', () async {
    final cat = await catId();
    final mode = await modeId();
    final acc = await accId();
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    await txRepo.create(
        amount: 50000,
        transactionDate: monday.toIso8601String(),
        accountId: acc, categoryId: cat, modeId: mode, kind: 'income');
    final d = await service.compute();
    expect(d.spentThisWeek, 0);
    expect(d.txnCountThisWeek, 0);
  });

  test('observations include a top-category share line', () async {
    final cat = await catId();
    final mode = await modeId();
    final acc = await accId();
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    await txRepo.create(
        amount: 400,
        transactionDate: monday.add(const Duration(days: 2)).toIso8601String(),
        accountId: acc, categoryId: cat, modeId: mode, kind: 'expense');
    final d = await service.compute();
    expect(d.observations, isNotEmpty);
    expect(d.observations.any((o) => o.contains('Food & Dining')), isTrue);
  });
}