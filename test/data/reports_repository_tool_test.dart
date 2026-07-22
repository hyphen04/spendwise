import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/reports_repository.dart';

void main() {
  late AppDatabase db;
  late ReportsRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get(); // force creation + seed defaults
    repo = ReportsRepository(db);

    // Seed one account, two categories, one mode.
    await db.into(db.accounts).insert(
            AccountsCompanion.insert(id: 'a1', name: 'HDFC', icon: '💳', color: '#059669', createdAt: 0, updatedAt: 0));
    await db.into(db.categories).insert(
            CategoriesCompanion.insert(id: 'c-fuel', name: 'Fuel', icon: '⛽', createdAt: 0, updatedAt: 0));
    await db.into(db.categories).insert(
            CategoriesCompanion.insert(id: 'c-food', name: 'Food', icon: '🍔', createdAt: 0, updatedAt: 0));
    await db.into(db.modes).insert(
            ModesCompanion.insert(id: 'm-upi', name: 'UPI', icon: '📱', createdAt: 0, updatedAt: 0));

    // October 2026 expenses.
    Future<void> tx(String id, double amount, String cat, String day) async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        amount: amount,
        transactionDate: '2026-10-${day}T10:00:00.000',
        accountId: 'a1',
        categoryId: cat,
        modeId: 'm-upi',
        kind: const Value('expense'),
        createdAt: 0,
        updatedAt: 0,
      ));
    }

    await tx('tx1', 2000, 'c-fuel', '05');
    await tx('tx2', 500, 'c-fuel', '06'); // filtered out by amount_min=1000
    await tx('tx3', 3000, 'c-food', '07');
    // September 2026 (outside the October range).
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'txSep',
      amount: 9999,
      transactionDate: '2026-09-15T10:00:00.000',
      accountId: 'a1',
      categoryId: 'c-fuel',
      modeId: 'm-upi',
      kind: const Value('expense'),
      createdAt: 0,
      updatedAt: 0,
    ));
  });

  tearDown(() => db.close());

  test('monthlyTotalsInRange returns per-month income/expense for the window', () async {
    final rows = await repo.monthlyTotalsInRange(
      from: '2026-09-01T00:00:00.000',
      to: '2026-11-01T00:00:00.000',
    );
    expect(rows.length, 2); // Sep + Oct
    final sep = rows.firstWhere((m) => m.month == 9);
    final oct = rows.firstWhere((m) => m.month == 10);
    expect(sep.expense, 9999);
    expect(oct.expense, 5500); // 2000 + 500 + 3000
    expect(oct.income, 0);
  });

  test('filteredTotals: count + total with amount_min filter, byCategory breakdown', () async {
    final r = await repo.filteredTotals(
      from: '2026-10-01T00:00:00.000',
      to: '2026-11-01T00:00:00.000',
      kind: 'expense',
      amountMin: 1000,
    );
    expect(r.count, 2); // tx1 (2000) + tx3 (3000); tx2 (500) excluded
    expect(r.total, 5000);
    final byCat = r.byCategory;
    final food = byCat.firstWhere((c) => c.id == 'c-food');
    final fuel = byCat.firstWhere((c) => c.id == 'c-fuel');
    expect(food.amount, 3000);
    expect(food.count, 1);
    expect(fuel.amount, 2000);
    expect(fuel.count, 1);
  });

  test('filteredTotals: categoryId filter narrows to one category', () async {
    final r = await repo.filteredTotals(
      from: '2026-10-01T00:00:00.000',
      to: '2026-11-01T00:00:00.000',
      kind: 'expense',
      categoryId: 'c-fuel',
    );
    expect(r.count, 2); // tx1 + tx2
    expect(r.total, 2500);
  });

  test('filteredTotals reads no notes — amount_min/max use amount only', () async {
    // A transaction with a PII note still filters purely on amount/date/kind.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'txNote',
      amount: 4000,
      transactionDate: '2026-10-08T10:00:00.000',
      accountId: 'a1',
      categoryId: 'c-food',
      modeId: 'm-upi',
      kind: const Value('expense'),
      note: const Value('secret note with phone 9876543210'),
      createdAt: 0,
      updatedAt: 0,
    ));
    final r = await repo.filteredTotals(
      from: '2026-10-01T00:00:00.000',
      to: '2026-11-01T00:00:00.000',
      kind: 'expense',
      amountMin: 3500,
    );
    expect(r.count, 1);
    expect(r.total, 4000);
    // The note is never returned by filteredTotals (no note field in the result).
  });

  test('filteredTotals: modeId filter narrows to one payment mode', () async {
    // All three October txs use m-upi, so the filter keeps them all.
    final r = await repo.filteredTotals(
      from: '2026-10-01T00:00:00.000',
      to: '2026-11-01T00:00:00.000',
      kind: 'expense',
      modeId: 'm-upi',
    );
    expect(r.count, 3); // tx1 + tx2 + tx3
    expect(r.total, 5500);
  });
}