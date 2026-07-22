import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/recurring_repository.dart';
import 'package:spendwise/data/repositories/reports_repository.dart';
import 'package:spendwise/data/repositories/transactions_repository.dart';

/// Helpers to resolve the default-seeded category / mode / account by name.
Future<Category> _cat(AppDatabase db, String name) async =>
    (await db.categoriesDao.getAllActive()).firstWhere((c) => c.name == name);

Future<Mode> _mode(AppDatabase db, String name) async =>
    (await db.modesDao.getAllActive()).firstWhere((m) => m.name == name);

Future<Account> _acc(AppDatabase db, String name) async =>
    (await db.accountsDao.getAllActive()).firstWhere((a) => a.name == name);

void main() {
  late AppDatabase db;
  late RecurringRepository repo;
  late TransactionsRepository txRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get(); // force creation + _seedDefaults
    repo = RecurringRepository(db);
    txRepo = TransactionsRepository(db);
  });

  tearDown(() => db.close());

  group('CRUD', () {
    test('create → getById roundtrip', () async {
      final cat = await _cat(db, 'Food & Dining');
      final due = DateTime.now().add(const Duration(days: 5));
      await repo.create(
        name: 'Netflix',
        amount: 649,
        categoryId: cat.id,
        nextDueDate: due,
      );
      final all = await repo.getAll();
      expect(all.length, 1);
      final got = await repo.getById(all.first.id);
      expect(got, isNotNull);
      expect(got!.name, 'Netflix');
      expect(got.amount, 649);
      expect(got.cadence, 'monthly');
      expect(got.source, 'manual');
      expect(got.isActive, isTrue);
    });

    test('update mutates fields and keeps source', () async {
      final cat = await _cat(db, 'Food & Dining');
      await repo.create(
        name: 'Netflix',
        amount: 649,
        categoryId: cat.id,
        nextDueDate: DateTime.now().add(const Duration(days: 2)),
      );
      final id = (await repo.getAll()).first.id;
      final existing = (await repo.getById(id))!;

      await repo.update(
        existing,
        name: 'Netflix Premium',
        amount: 799,
        categoryId: cat.id,
        cadence: 'yearly',
        nextDueDate: DateTime.now().add(const Duration(days: 30)),
        note: 'annual plan',
      );
      final after = await repo.getById(id);
      expect(after!.name, 'Netflix Premium');
      expect(after.amount, 799);
      expect(after.cadence, 'yearly');
      expect(after.note, 'annual plan');
      // source is preserved across edits.
      expect(after.source, 'manual');
    });

    test('delete removes the row', () async {
      final cat = await _cat(db, 'Food & Dining');
      await repo.create(
        name: 'Gym',
        amount: 1200,
        categoryId: cat.id,
        nextDueDate: DateTime.now().add(const Duration(days: 1)),
      );
      final id = (await repo.getAll()).first.id;
      await repo.delete(id);
      expect(await repo.getAll(), isEmpty);
    });
  });

  group('dueInDays', () {
    test('only active items within the horizon', () async {
      final cat = await _cat(db, 'Food & Dining');
      // Due today — included with horizon 0.
      await repo.create(
        name: 'DueToday',
        amount: 100,
        categoryId: cat.id,
        nextDueDate: DateTime.now(),
      );
      // Due in 5 days — included with horizon 7, excluded with horizon 3.
      await repo.create(
        name: 'DueIn5',
        amount: 100,
        categoryId: cat.id,
        nextDueDate: DateTime.now().add(const Duration(days: 5)),
      );
      // Due in 20 days — always excluded here.
      await repo.create(
        name: 'DueIn20',
        amount: 100,
        categoryId: cat.id,
        nextDueDate: DateTime.now().add(const Duration(days: 20)),
      );

      final today = await repo.dueInDays(0);
      expect(today.map((e) => e.name).toList(), contains('DueToday'));
      expect(today.any((e) => e.name == 'DueIn5'), isFalse);

      final week = await repo.dueInDays(7);
      expect(week.map((e) => e.name).toSet(),
          containsAll(<String>{'DueToday', 'DueIn5'}));
      expect(week.any((e) => e.name == 'DueIn20'), isFalse);
    });

    test('inactive items are excluded even when due', () async {
      final cat = await _cat(db, 'Food & Dining');
      await repo.create(
        name: 'Paused',
        amount: 50,
        categoryId: cat.id,
        nextDueDate: DateTime.now(),
      );
      final id = (await repo.getAll()).first.id;
      final existing = (await repo.getById(id))!;
      await repo.update(
        existing,
        name: 'Paused',
        amount: 50,
        categoryId: cat.id,
        cadence: 'monthly',
        nextDueDate: DateTime.now(),
        isActive: false,
      );
      expect(await repo.dueInDays(7), isEmpty);
    });
  });

  group('daysUntilDue', () {
    test('sign reflects past vs future', () async {
      final cat = await _cat(db, 'Food & Dining');
      await repo.create(
        name: 'Overdue',
        amount: 10,
        categoryId: cat.id,
        nextDueDate: DateTime.now().subtract(const Duration(days: 3)),
      );
      await repo.create(
        name: 'Future',
        amount: 10,
        categoryId: cat.id,
        nextDueDate: DateTime.now().add(const Duration(days: 4)),
      );
      final items = {for (final r in await repo.getAll()) r.name: r};
      expect(repo.daysUntilDue(items['Overdue']!), lessThanOrEqualTo(-3));
      expect(repo.daysUntilDue(items['Future']!), greaterThanOrEqualTo(3));
    });
  });

  group('advanceDueDate', () {
    test('monthly advances ~1 month', () async {
      final cat = await _cat(db, 'Food & Dining');
      final due = DateTime(2026, 3, 15);
      await repo.create(
        name: 'Rent',
        amount: 15000,
        categoryId: cat.id,
        cadence: 'monthly',
        nextDueDate: due,
      );
      final item = (await repo.getAll()).first;
      final next = repo.advanceDueDate(item);
      expect(next.year, 2026);
      expect(next.month, 4);
      expect(next.day, 15);
    });

    test('weekly advances 7 days', () async {
      final cat = await _cat(db, 'Food & Dining');
      await repo.create(
        name: 'Milk',
        amount: 60,
        categoryId: cat.id,
        cadence: 'weekly',
        nextDueDate: DateTime(2026, 3, 15),
      );
      final item = (await repo.getAll()).first;
      expect(repo.advanceDueDate(item).difference(DateTime(2026, 3, 15)).inDays,
          7);
    });
  });

  group('autoRefreshFromTransactions', () {
    test('detects recurring expenses and is idempotent', () async {
      final cat = await _cat(db, 'Food & Dining');
      final mode = await _mode(db, 'Online / UPI');
      final acc = await _acc(db, 'Cash');

      // 4 equal monthly payments of 499, ~30 days apart, ending recently.
      final now = DateTime.now();
      final dates = [
        now.subtract(const Duration(days: 90)),
        now.subtract(const Duration(days: 60)),
        now.subtract(const Duration(days: 30)),
        now.subtract(const Duration(days: 2)),
      ];
      for (final d in dates) {
        await txRepo.create(
          amount: 499,
          transactionDate: d.toIso8601String(),
          accountId: acc.id,
          categoryId: cat.id,
          modeId: mode.id,
          kind: 'expense',
        );
      }

      final reports = ReportsRepository(db);
      final first = await repo.autoRefreshFromTransactions(reports);
      expect(first, greaterThanOrEqualTo(1),
          reason: 'should detect and seed at least one recurring bill');

      final seeded = await repo.getAll();
      expect(seeded, isNotEmpty);
      expect(seeded.any((r) => r.source == 'detected'), isTrue);

      // Running again must not duplicate.
      final second = await repo.autoRefreshFromTransactions(reports);
      expect(second, 0, reason: 'idempotent: no new items on second run');
      expect((await repo.getAll()).length, seeded.length);
    });

    test('returns 0 when there is nothing recurring', () async {
      final cat = await _cat(db, 'Food & Dining');
      final mode = await _mode(db, 'Online / UPI');
      final acc = await _acc(db, 'Cash');
      // Only 2 transactions — below the 3-occurrence minimum.
      final now = DateTime.now();
      for (final d in [
        now.subtract(const Duration(days: 30)),
        now.subtract(const Duration(days: 2)),
      ]) {
        await txRepo.create(
          amount: 250,
          transactionDate: d.toIso8601String(),
          accountId: acc.id,
          categoryId: cat.id,
          modeId: mode.id,
          kind: 'expense',
        );
      }
      final reports = ReportsRepository(db);
      expect(await repo.autoRefreshFromTransactions(reports), 0);
    });

    test('ignored category is not re-seeded on re-detect', () async {
      final cat = await _cat(db, 'Food & Dining');
      final mode = await _mode(db, 'Online / UPI');
      final acc = await _acc(db, 'Cash');

      final now = DateTime.now();
      for (final d in [
        now.subtract(const Duration(days: 90)),
        now.subtract(const Duration(days: 60)),
        now.subtract(const Duration(days: 30)),
        now.subtract(const Duration(days: 2)),
      ]) {
        await txRepo.create(
          amount: 499,
          transactionDate: d.toIso8601String(),
          accountId: acc.id,
          categoryId: cat.id,
          modeId: mode.id,
          kind: 'expense',
        );
      }

      final reports = ReportsRepository(db);
      await repo.autoRefreshFromTransactions(reports);
      final detected = (await repo.getAll()).firstWhere((r) => r.source == 'detected');
      expect(detected.categoryId, cat.id);

      // User marks it "not a bill" → row removed + category ignored.
      await repo.ignoreDetected(detected);
      expect(await repo.getById(detected.id), isNull);
      expect(await repo.ignoredCategoryIds(), contains(cat.id));

      // Re-detect must NOT resurrect it (the whole point of the ignore list).
      expect(await repo.autoRefreshFromTransactions(reports), 0);
      expect((await repo.getAll()).where((r) => r.source == 'detected'), isEmpty);

      // Undo: unignore → re-detect seeds it again.
      await repo.unignoreCategory(cat.id);
      expect(await repo.autoRefreshFromTransactions(reports), greaterThanOrEqualTo(1));
      expect(
        (await repo.getAll()).any((r) => r.source == 'detected' && r.categoryId == cat.id),
        isTrue,
      );
    });
  });
}
