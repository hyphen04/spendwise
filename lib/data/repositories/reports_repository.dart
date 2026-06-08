import 'package:drift/drift.dart';
import '../db/app_database.dart';
import '../models/report_models.dart';

class ReportsRepository {
  ReportsRepository(this._db);
  final AppDatabase _db;

  Future<MonthlySummary> monthlySummary(int year, int month) async {
    final from = DateTime(year, month).toIso8601String();
    final to = DateTime(year, month + 1).toIso8601String();

    final totals = await _db.customSelect(
      'SELECT kind, COALESCE(SUM(amount),0) AS total FROM transactions '
      'WHERE kind IN (\'income\',\'expense\') '
      'AND transaction_date >= ? AND transaction_date < ? GROUP BY kind',
      variables: [Variable.withString(from), Variable.withString(to)],
    ).get();

    double income = 0, expense = 0;
    for (final r in totals) {
      if (r.data['kind'] == 'income') {
        income = (r.data['total'] as num).toDouble();
      } else if (r.data['kind'] == 'expense') {
        expense = (r.data['total'] as num).toDouble();
      }
    }

    final catRows = await _db.customSelect(
      'SELECT t.category_id, c.name, c.icon, c.color, SUM(t.amount) AS total '
      'FROM transactions t LEFT JOIN categories c ON t.category_id = c.id '
      'WHERE t.kind = \'expense\' '
      'AND t.transaction_date >= ? AND t.transaction_date < ? '
      'GROUP BY t.category_id ORDER BY total DESC LIMIT 5',
      variables: [Variable.withString(from), Variable.withString(to)],
    ).get();

    final topCategories = catRows
        .map((r) => CategoryTotal(
              categoryId: r.data['category_id'] as String? ?? '',
              name: r.data['name'] as String? ?? 'Unknown',
              icon: r.data['icon'] as String? ?? '📦',
              color: r.data['color'] as String? ?? '#475569',
              total: (r.data['total'] as num).toDouble(),
            ))
        .toList();

    final topSpend = await _db.customSelect(
      'SELECT t.amount, t.note, c.name AS category_name '
      'FROM transactions t '
      'LEFT JOIN categories c ON t.category_id = c.id '
      'WHERE t.kind = \'expense\' '
      'AND t.transaction_date >= ? AND t.transaction_date < ? '
      'ORDER BY t.amount DESC LIMIT 1',
      variables: [Variable.withString(from), Variable.withString(to)],
    ).get();

    String? biggestTitle;
    double? biggestAmount;
    String? biggestNote;
    if (topSpend.isNotEmpty) {
      final row = topSpend.first.data;
      biggestTitle = row['category_name'] as String? ?? 'Expense';
      biggestAmount = (row['amount'] as num?)?.toDouble();
      final rawNote = row['note'] as String? ?? '';
      biggestNote = rawNote.isNotEmpty ? rawNote : null;
    }

    return MonthlySummary(
      income: income,
      expense: expense,
      topExpenseCategories: topCategories,
      biggestSpendTitle: biggestTitle,
      biggestSpendAmount: biggestAmount,
      biggestSpendNote: biggestNote,
    );
  }

  Future<List<CategoryTotal>> categoryBreakdown({
    required String from,
    required String to,
    String? kind,
    String? accountId,
  }) async {
    final kindClause =
        kind != null ? 'AND t.kind = \'${kind.replaceAll("'", "''")}\'' : '';
    final acctClause = accountId != null ? 'AND t.account_id = ?' : '';
    final vars = <Variable>[
      Variable.withString(from),
      Variable.withString(to),
    ];
    if (accountId != null) vars.add(Variable.withString(accountId));

    final rows = await _db.customSelect(
      'SELECT t.category_id, c.name, c.icon, c.color, SUM(t.amount) AS total '
      'FROM transactions t LEFT JOIN categories c ON t.category_id = c.id '
      'WHERE t.transaction_date >= ? AND t.transaction_date < ? '
      '$kindClause $acctClause '
      'GROUP BY t.category_id ORDER BY total DESC',
      variables: vars,
    ).get();

    return rows
        .map((r) => CategoryTotal(
              categoryId: r.data['category_id'] as String? ?? '',
              name: r.data['name'] as String? ?? 'Unknown',
              icon: r.data['icon'] as String? ?? '📦',
              color: r.data['color'] as String? ?? '#475569',
              total: (r.data['total'] as num).toDouble(),
            ))
        .toList();
  }

  Future<List<ModeTotal>> modeBreakdown({
    required String from,
    required String to,
    String? kind,
  }) async {
    final kindClause =
        kind != null ? 'AND t.kind = \'${kind.replaceAll("'", "''")}\'' : '';
    final rows = await _db.customSelect(
      'SELECT t.mode_id, m.name, m.icon, SUM(t.amount) AS total '
      'FROM transactions t LEFT JOIN modes m ON t.mode_id = m.id '
      'WHERE t.transaction_date >= ? AND t.transaction_date < ? $kindClause '
      'GROUP BY t.mode_id ORDER BY total DESC',
      variables: [Variable.withString(from), Variable.withString(to)],
    ).get();

    return rows
        .map((r) => ModeTotal(
              modeId: r.data['mode_id'] as String? ?? '',
              name: r.data['name'] as String? ?? 'Unknown',
              icon: r.data['icon'] as String? ?? '💳',
              total: (r.data['total'] as num).toDouble(),
            ))
        .toList();
  }

  Future<List<MonthTotal>> monthlyTotals(int year) async {
    final result = <MonthTotal>[];
    for (int m = 1; m <= 12; m++) {
      final from = DateTime(year, m).toIso8601String();
      final to = DateTime(year, m + 1).toIso8601String();
      final rows = await _db.customSelect(
        'SELECT kind, COALESCE(SUM(amount),0) AS total FROM transactions '
        'WHERE kind IN (\'income\',\'expense\') '
        'AND transaction_date >= ? AND transaction_date < ? GROUP BY kind',
        variables: [Variable.withString(from), Variable.withString(to)],
      ).get();
      double income = 0, expense = 0;
      for (final r in rows) {
        if (r.data['kind'] == 'income') {
          income = (r.data['total'] as num).toDouble();
        } else if (r.data['kind'] == 'expense') {
          expense = (r.data['total'] as num).toDouble();
        }
      }
      result.add(MonthTotal(year: year, month: m, income: income, expense: expense));
    }
    return result;
  }

  Future<List<MonthTotal>> cashFlowMonths({int count = 6}) async {
    final now = DateTime.now();
    final result = <MonthTotal>[];
    for (int i = count - 1; i >= 0; i--) {
      int y = now.year;
      int m = now.month - i;
      while (m <= 0) {
        m += 12;
        y--;
      }
      final from = DateTime(y, m).toIso8601String();
      final to = DateTime(y, m + 1).toIso8601String();
      final rows = await _db.customSelect(
        'SELECT kind, COALESCE(SUM(amount),0) AS total FROM transactions '
        'WHERE kind IN (\'income\',\'expense\') '
        'AND transaction_date >= ? AND transaction_date < ? GROUP BY kind',
        variables: [Variable.withString(from), Variable.withString(to)],
      ).get();
      double income = 0, expense = 0;
      for (final r in rows) {
        if (r.data['kind'] == 'income') {
          income = (r.data['total'] as num).toDouble();
        } else if (r.data['kind'] == 'expense') {
          expense = (r.data['total'] as num).toDouble();
        }
      }
      result.add(MonthTotal(year: y, month: m, income: income, expense: expense));
    }
    return result;
  }

  Future<List<Transaction>> topSpends({
    required String from,
    required String to,
    int limit = 10,
  }) {
    return (_db.select(_db.transactions)
          ..where((t) =>
              t.kind.equals('expense') &
              t.transactionDate.isBiggerOrEqualValue(from) &
              t.transactionDate.isSmallerThanValue(to))
          ..orderBy([(t) => OrderingTerm.desc(t.amount)])
          ..limit(limit))
        .get();
  }

  Future<List<Transaction>> accountStatement({
    required String accountId,
    required String from,
    required String to,
  }) {
    return (_db.select(_db.transactions)
          ..where((t) =>
              t.accountId.equals(accountId) &
              t.transactionDate.isBiggerOrEqualValue(from) &
              t.transactionDate.isSmallerThanValue(to))
          ..orderBy([(t) => OrderingTerm.asc(t.transactionDate)]))
        .get();
  }

  Future<List<TagTotal>> tagBreakdown({
    required String from,
    required String to,
  }) async {
    final rows = await _db.customSelect(
      'SELECT tt.tag_id, tg.name, tg.color, SUM(tx.amount) AS total '
      'FROM transaction_tags tt '
      'JOIN tags tg ON tt.tag_id = tg.id '
      'JOIN transactions tx ON tt.transaction_id = tx.id '
      'WHERE tx.kind = \'expense\' '
      'AND tx.transaction_date >= ? AND tx.transaction_date < ? '
      'GROUP BY tt.tag_id ORDER BY total DESC',
      variables: [Variable.withString(from), Variable.withString(to)],
    ).get();

    return rows
        .map((r) => TagTotal(
              tagId: r.data['tag_id'] as String? ?? '',
              name: r.data['name'] as String? ?? 'Unknown',
              color: r.data['color'] as String? ?? '#475569',
              total: (r.data['total'] as num).toDouble(),
            ))
        .toList();
  }

  Future<List<ExportRow>> transactionsForExport({
    required String from,
    required String to,
    String? kind,
    Set<String>? accountIds,
  }) async {
    final vars = <Variable>[Variable.withString(from), Variable.withString(to)];

    String kindClause = '';
    if (kind != null) {
      kindClause = "AND t.kind = '${kind.replaceAll("'", "''")}'";
    }

    String accountClause = '';
    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = accountIds.map((_) => '?').join(',');
      accountClause = 'AND t.account_id IN ($placeholders)';
      vars.addAll(accountIds.map(Variable.withString));
    }

    final rows = await _db.customSelect(
      'SELECT t.id, t.amount, t.transaction_date, t.kind, t.note, '
      't.created_at, '
      'a.name AS account_name, c.name AS category_name, m.name AS mode_name '
      'FROM transactions t '
      'LEFT JOIN accounts a ON t.account_id = a.id '
      'LEFT JOIN categories c ON t.category_id = c.id '
      'LEFT JOIN modes m ON t.mode_id = m.id '
      'WHERE t.transaction_date >= ? AND t.transaction_date < ? '
      '$kindClause $accountClause '
      'ORDER BY t.transaction_date ASC',
      variables: vars,
    ).get();

    return rows
        .map((r) => ExportRow(
              id: r.data['id'] as String,
              amount: (r.data['amount'] as num).toDouble(),
              date: r.data['transaction_date'] as String,
              kind: r.data['kind'] as String,
              accountName: r.data['account_name'] as String? ?? '',
              categoryName: r.data['category_name'] as String? ?? '',
              modeName: r.data['mode_name'] as String? ?? '',
              note: r.data['note'] as String?,
              createdAt: (r.data['created_at'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }
}
