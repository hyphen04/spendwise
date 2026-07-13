import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/goals_repository.dart';

void main() {
  late AppDatabase db;
  late GoalsRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get(); // force creation + seed defaults
    repo = GoalsRepository(db);
  });

  tearDown(() => db.close());

  group('CRUD', () {
    test('create → getById roundtrip uses defaults', () async {
      await repo.create(name: 'New Phone', targetAmount: 60000);
      final all = await repo.getAll();
      expect(all.length, 1);
      final got = await repo.getById(all.first.id);
      expect(got, isNotNull);
      expect(got!.name, 'New Phone');
      expect(got.targetAmount, 60000);
      expect(got.savedAmount, 0);
      expect(got.icon, '🎯');
      expect(got.isActive, isTrue);
    });

    test('update mutates fields', () async {
      await repo.create(name: 'Trip', targetAmount: 30000);
      final id = (await repo.getAll()).first.id;
      final existing = (await repo.getById(id))!;
      await repo.update(
        existing,
        name: 'Goa Trip',
        targetAmount: 35000,
        icon: '✈️',
        color: '#DC2626',
        monthlyCommitment: 5000,
        targetDate: DateTime(2027, 1, 15),
      );
      final after = await repo.getById(id);
      expect(after!.name, 'Goa Trip');
      expect(after.targetAmount, 35000);
      expect(after.icon, '✈️');
      expect(after.color, '#DC2626');
      expect(after.monthlyCommitment, 5000);
      expect(after.targetDate, '2027-01-15');
    });

    test('delete removes the row', () async {
      await repo.create(name: 'Gone', targetAmount: 1000);
      final id = (await repo.getAll()).first.id;
      await repo.delete(id);
      expect(await repo.getAll(), isEmpty);
    });
  });

  group('contribute', () {
    test('adds to savedAmount and clamps at zero for withdrawals', () async {
      await repo.create(name: 'Laptop', targetAmount: 100000, savedAmount: 20000);
      final id = (await repo.getAll()).first.id;
      var g = (await repo.getById(id))!;
      await repo.contribute(g, 5000);
      expect((await repo.getById(id))!.savedAmount, 25000);

      // Withdraw more than saved → clamps to 0 (never negative).
      g = (await repo.getById(id))!;
      await repo.contribute(g, -99999);
      expect((await repo.getById(id))!.savedAmount, 0);
    });

    test('non-finite amounts are ignored', () async {
      await repo.create(name: 'X', targetAmount: 1000);
      final id = (await repo.getAll()).first.id;
      final g = (await repo.getById(id))!;
      await repo.contribute(g, double.nan);
      await repo.contribute(g, double.infinity);
      expect((await repo.getById(id))!.savedAmount, 0);
    });
  });

  group('progressFor', () {
    test('fraction and remaining', () async {
      await repo.create(name: 'Bike', targetAmount: 80000, savedAmount: 20000);
      final g = (await repo.getAll()).first;
      final p = repo.progressFor(g);
      expect(p.fraction, closeTo(0.25, 1e-9));
      expect(p.remaining, 60000);
      expect(p.isComplete, isFalse);
    });

    test('complete when saved >= target', () async {
      await repo.create(name: 'Done', targetAmount: 5000, savedAmount: 5000);
      final g = (await repo.getAll()).first;
      final p = repo.progressFor(g);
      expect(p.remaining, 0);
      expect(p.isComplete, isTrue);
    });

    test('zero target → fraction 0, no crash', () async {
      await repo.create(name: 'Zero', targetAmount: 0);
      final g = (await repo.getAll()).first;
      final p = repo.progressFor(g);
      expect(p.fraction, 0);
      expect(p.remaining, 0);
    });
  });

  group('monthsLeft / requiredPerMonth', () {
    test('monthsLeft null when no target date', () async {
      await repo.create(name: 'NoDate', targetAmount: 1000);
      final g = (await repo.getAll()).first;
      expect(repo.progressFor(g).monthsLeft, isNull);
      expect(repo.progressFor(g).requiredPerMonth, isNull);
    });

    test('requiredPerMonth splits remaining across months left', () async {
      // Target 12 months out, saved 0 → 1000/month.
      final target = DateTime.now().add(const Duration(days: 365));
      await repo.create(
          name: 'Year', targetAmount: 12000, targetDate: target);
      final g = (await repo.getAll()).first;
      final p = repo.progressFor(g);
      expect(p.monthsLeft, greaterThanOrEqualTo(11));
      expect(p.requiredPerMonth, isNotNull);
      expect(p.requiredPerMonth! / 1000, closeTo(1.0, 0.15));
    });
  });

  group('watchAll ordering', () {
    test('active goals before inactive', () async {
      await repo.create(name: 'ActiveOne', targetAmount: 1000);
      await repo.create(
          name: 'PausedOne', targetAmount: 1000, isActive: false);
      final names = (await repo.getAll()).map((g) => g.name).toList();
      // getAll() doesn't guarantee order, but watchAll emits active-first.
      final streamed = await repo.watchAll().first;
      final activeIdx = streamed.indexWhere((g) => g.name == 'ActiveOne');
      final pausedIdx = streamed.indexWhere((g) => g.name == 'PausedOne');
      expect(activeIdx, lessThan(pausedIdx));
      expect(names, containsAll(<String>['ActiveOne', 'PausedOne']));
    });
  });
}