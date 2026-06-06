import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';
import '../models/budget_progress.dart';

class BudgetsRepository {
  BudgetsRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Budget>> watchAll() => _db.budgetsDao.watchAll();
  Future<List<Budget>> getAll() => _db.budgetsDao.getAll();

  Future<void> create({
    required String categoryId,
    required double amount,
    String period = 'month',
    String? accountId,
    DateTime? startDate,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = (startDate ?? DateTime.now()).toIso8601String().substring(0, 10);
    return _db.budgetsDao.upsert(BudgetsCompanion.insert(
      id: _uuid.v4(),
      categoryId: categoryId,
      accountId: Value(accountId),
      period: Value(period),
      amount: amount,
      startDate: start,
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> update(
    Budget existing, {
    required double amount,
    required String period,
    String? accountId,
  }) {
    return _db.budgetsDao.upsert(BudgetsCompanion(
      id: Value(existing.id),
      categoryId: Value(existing.categoryId),
      startDate: Value(existing.startDate),
      amount: Value(amount),
      period: Value(period),
      accountId: Value(accountId),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<int> delete(String id) => _db.budgetsDao.deleteById(id);

  Future<double> spendingForBudget(Budget b, DateTime month) async {
    DateTime from, to;
    if (b.period == 'week') {
      final now = DateTime.now();
      final monday =
          now.subtract(Duration(days: now.weekday - 1));
      from = DateTime(monday.year, monday.month, monday.day);
      to = from.add(const Duration(days: 7));
    } else {
      from = DateTime(month.year, month.month);
      to = DateTime(month.year, month.month + 1);
    }

    final fromIso = from.toIso8601String();
    final toIso = to.toIso8601String();

    final row = b.accountId != null
        ? await _db
            .customSelect(
              'SELECT COALESCE(SUM(amount),0) AS total FROM transactions '
              'WHERE kind=\'expense\' AND category_id=? AND account_id=? '
              'AND transaction_date>=? AND transaction_date<?',
              variables: [
                Variable.withString(b.categoryId),
                Variable.withString(b.accountId!),
                Variable.withString(fromIso),
                Variable.withString(toIso),
              ],
            )
            .getSingle()
        : await _db
            .customSelect(
              'SELECT COALESCE(SUM(amount),0) AS total FROM transactions '
              'WHERE kind=\'expense\' AND category_id=? '
              'AND transaction_date>=? AND transaction_date<?',
              variables: [
                Variable.withString(b.categoryId),
                Variable.withString(fromIso),
                Variable.withString(toIso),
              ],
            )
            .getSingle();

    return (row.data['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<BudgetProgress>> progressForMonth(DateTime month) async {
    final budgets = await getAll();
    final cats = await _db.categoriesDao.getAllActive();
    final catMap = {for (final c in cats) c.id: c};

    final result = <BudgetProgress>[];
    for (final b in budgets) {
      final spent = await spendingForBudget(b, month);
      result.add(BudgetProgress(
        budget: b,
        spent: spent,
        category: catMap[b.categoryId],
      ));
    }
    return result;
  }
}
