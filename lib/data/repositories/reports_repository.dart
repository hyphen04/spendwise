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

    final baseBalRow = await _db.customSelect(
      'SELECT COALESCE(SUM(opening_balance), 0) AS total FROM accounts WHERE is_archived = 0',
    ).getSingle();
    final double baseBalance = (baseBalRow.data['total'] as num).toDouble();

    final prevTxRow = await _db.customSelect(
      'SELECT COALESCE(SUM(CASE WHEN kind IN (\'income\', \'transfer_in\') THEN amount WHEN kind IN (\'expense\', \'transfer_out\') THEN -amount ELSE 0 END), 0) AS net '
      'FROM transactions WHERE transaction_date < ? '
      'AND account_id IN (SELECT id FROM accounts WHERE is_archived = 0)',
      variables: [Variable.withString(from)],
    ).getSingle();
    final double prevNet = (prevTxRow.data['net'] as num).toDouble();

    final openingBalance = baseBalance + prevNet;
    final closingBalance = openingBalance + income - expense;

    return MonthlySummary(
      income: income,
      expense: expense,
      topExpenseCategories: topCategories,
      biggestSpendTitle: biggestTitle,
      biggestSpendAmount: biggestAmount,
      biggestSpendNote: biggestNote,
      openingBalance: openingBalance,
      closingBalance: closingBalance,
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

  Future<List<DayTotal>> dailyTotals(int year, int month) async {
    final result = <DayTotal>[];
    final numDays = DateTime(year, month + 1, 0).day;
    for (int d = 1; d <= numDays; d++) {
      final from = DateTime(year, month, d).toIso8601String();
      final to = DateTime(year, month, d + 1).toIso8601String();
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
      result.add(DayTotal(year: year, month: month, day: d, income: income, expense: expense));
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

  Future<List<CategoryTotal>> topSpends({
    required String from,
    required String to,
    int limit = 10,
  }) async {
    final rows = await _db.customSelect(
      'SELECT t.category_id, c.name, c.icon, c.color, SUM(t.amount) AS total '
      'FROM transactions t LEFT JOIN categories c ON t.category_id = c.id '
      'WHERE t.transaction_date >= ? AND t.transaction_date < ? '
      'AND t.kind = \'expense\' '
      'GROUP BY t.category_id ORDER BY total DESC LIMIT ?',
      variables: [
        Variable.withString(from),
        Variable.withString(to),
        Variable.withInt(limit),
      ],
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

  Future<(double, double)> accountStatementBalances(String accountId, String from, String to) async {
    final accRow = await _db.customSelect(
      'SELECT opening_balance FROM accounts WHERE id = ?',
      variables: [Variable.withString(accountId)]
    ).getSingleOrNull();
    final double baseBalance = (accRow?.data['opening_balance'] as num?)?.toDouble() ?? 0.0;

    final prevTxRow = await _db.customSelect(
      'SELECT COALESCE(SUM(CASE WHEN kind IN (\'income\', \'transfer_in\') THEN amount WHEN kind IN (\'expense\', \'transfer_out\') THEN -amount ELSE 0 END), 0) AS net '
      'FROM transactions WHERE account_id = ? AND transaction_date < ?',
      variables: [Variable.withString(accountId), Variable.withString(from)],
    ).getSingle();
    final double prevNet = (prevTxRow.data['net'] as num).toDouble();

    final openingBalance = baseBalance + prevNet;

    final currTxRow = await _db.customSelect(
      'SELECT COALESCE(SUM(CASE WHEN kind IN (\'income\', \'transfer_in\') THEN amount WHEN kind IN (\'expense\', \'transfer_out\') THEN -amount ELSE 0 END), 0) AS net '
      'FROM transactions WHERE account_id = ? AND transaction_date >= ? AND transaction_date < ?',
      variables: [Variable.withString(accountId), Variable.withString(from), Variable.withString(to)],
    ).getSingle();
    final double currNet = (currTxRow.data['net'] as num).toDouble();

    final closingBalance = openingBalance + currNet;

    return (openingBalance, closingBalance);
  }

  Future<(double, double)> yearlyBalances(int year) async {
    final from = DateTime(year, 1, 1).toIso8601String();
    final to = DateTime(year + 1, 1, 1).toIso8601String();

    final baseBalRow = await _db.customSelect(
      'SELECT COALESCE(SUM(opening_balance), 0) AS total FROM accounts WHERE is_archived = 0',
    ).getSingle();
    final double baseBalance = (baseBalRow.data['total'] as num).toDouble();

    final prevTxRow = await _db.customSelect(
      'SELECT COALESCE(SUM(CASE WHEN kind IN (\'income\', \'transfer_in\') THEN amount WHEN kind IN (\'expense\', \'transfer_out\') THEN -amount ELSE 0 END), 0) AS net '
      'FROM transactions WHERE transaction_date < ? '
      'AND account_id IN (SELECT id FROM accounts WHERE is_archived = 0)',
      variables: [Variable.withString(from)],
    ).getSingle();
    final double prevNet = (prevTxRow.data['net'] as num).toDouble();

    final openingBalance = baseBalance + prevNet;

    final currTxRow = await _db.customSelect(
      'SELECT COALESCE(SUM(CASE WHEN kind IN (\'income\', \'transfer_in\') THEN amount WHEN kind IN (\'expense\', \'transfer_out\') THEN -amount ELSE 0 END), 0) AS net '
      'FROM transactions WHERE transaction_date >= ? AND transaction_date < ? '
      'AND account_id IN (SELECT id FROM accounts WHERE is_archived = 0)',
      variables: [Variable.withString(from), Variable.withString(to)],
    ).getSingle();
    final double currNet = (currTxRow.data['net'] as num).toDouble();

    final closingBalance = openingBalance + currNet;

    return (openingBalance, closingBalance);
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

  /// Per-day expense totals over [from, to), keyed by ISO date "yyyy-MM-dd".
  /// One grouped query — used by the forecast day-grid (monthly + yearly)
  /// to color each cell by spend intensity. Income/transfer rows are excluded;
  /// only `expense` rows count toward the heatmap.
  Future<Map<String, double>> dailyExpenseByDay({
    required String from,
    required String to,
  }) async {
    final rows = await _db.customSelect(
      "SELECT substr(transaction_date,1,10) AS d, COALESCE(SUM(amount),0) AS total "
      "FROM transactions WHERE kind = 'expense' "
      "AND transaction_date >= ? AND transaction_date < ? GROUP BY d",
      variables: [Variable.withString(from), Variable.withString(to)],
    ).get();
    return {
      for (final r in rows)
        r.data['d'] as String: (r.data['total'] as num).toDouble(),
    };
  }

  /// Total income + expense over [from, to) in a single grouped query.
  Future<({double income, double expense})> incomeExpenseInRange({
    required String from,
    required String to,
  }) async {
    final rows = await _db.customSelect(
      "SELECT kind, COALESCE(SUM(amount),0) AS total FROM transactions "
      "WHERE kind IN ('income','expense') "
      "AND transaction_date >= ? AND transaction_date < ? GROUP BY kind",
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
    return (income: income, expense: expense);
  }

  /// Count of `expense` transactions over [from, to). Used for the AI payload's
  /// `tx_frequency` aggregate. Reads only `kind` + `transaction_date` — no
  /// notes, no contact data, no raw rows leave the device.
  Future<int> expenseCountInRange({
    required String from,
    required String to,
  }) async {
    final row = await _db.customSelect(
      "SELECT COUNT(*) AS cnt FROM transactions "
      "WHERE kind = 'expense' "
      "AND transaction_date >= ? AND transaction_date < ?",
      variables: [Variable.withString(from), Variable.withString(to)],
    ).getSingle();
    return (row.data['cnt'] as int?) ?? 0;
  }

  /// Current balance per active account (`opening_balance` + net of all
  /// transactions on the account). Used for the AI payload's
  /// `account_balances` aggregate — names are labelized on-device by the
  /// builder and never sent as raw names unless `shareNames` is on. No notes
  /// or contact data are read.
  Future<List<({String id, String name, double balance})>>
      accountBalances() async {
    final rows = await _db.customSelect(
      "SELECT a.id AS id, a.name AS name, "
      "a.opening_balance + COALESCE(SUM(CASE "
      "WHEN t.kind IN ('income','transfer_in') THEN t.amount "
      "WHEN t.kind IN ('expense','transfer_out') THEN -t.amount "
      "ELSE 0 END), 0) AS balance "
      "FROM accounts a "
      "LEFT JOIN transactions t ON t.account_id = a.id "
      "WHERE a.is_archived = 0 "
      "GROUP BY a.id, a.name, a.opening_balance "
      "ORDER BY a.name",
    ).get();
    return rows
        .map((r) => (
              id: r.data['id'] as String,
              name: r.data['name'] as String? ?? '',
              balance: (r.data['balance'] as num).toDouble(),
            ))
        .toList();
  }

  /// Per-month income/expense over `[from, to)` in a single grouped query.
  /// Used by the AI tool layer's `monthly_totals` tool. Reads only `kind`,
  /// `amount`, `transaction_date` — never `note` or `receipt_path`, never
  /// `due_*` / `ai_*` / `goals` / `recurring_items`.
  Future<List<MonthTotal>> monthlyTotalsInRange({
    required String from,
    required String to,
  }) async {
    final rows = await _db.customSelect(
      "SELECT substr(transaction_date,1,7) AS ym, "
      "COALESCE(SUM(CASE WHEN kind='income' THEN amount ELSE 0 END),0) AS income, "
      "COALESCE(SUM(CASE WHEN kind='expense' THEN amount ELSE 0 END),0) AS expense "
      "FROM transactions "
      "WHERE kind IN ('income','expense') "
      "AND transaction_date >= ? AND transaction_date < ? "
      "GROUP BY ym ORDER BY ym",
      variables: [Variable.withString(from), Variable.withString(to)],
    ).get();
    return rows.map((r) {
      final ym = r.data['ym'] as String;
      final parts = ym.split('-');
      return MonthTotal(
        year: int.parse(parts[0]),
        month: int.parse(parts[1]),
        income: (r.data['income'] as num).toDouble(),
        expense: (r.data['expense'] as num).toDouble(),
      );
    }).toList();
  }

  /// Aggregate count + total over `[from, to)` with optional filters, plus
  /// per-group breakdowns by category / mode / account / tag. Used by the AI
  /// tool layer's `filtered_totals` tool. Fixed, parameterized, read-only.
  /// Never selects `note` or `receipt_path`; never touches `due_*` / `ai_*` /
  /// `goals` / `recurring_items`. `name` fields are real names — the executor
  /// anonymizes them to labels (or keeps them when `shareNames` is on).
  Future<({
    int count,
    double total,
    List<({String id, String name, double amount, int count})> byCategory,
    List<({String id, String name, double amount, int count})> byMode,
    List<({String id, String name, double amount, int count})> byAccount,
    List<({String id, String name, double amount, int count})> byTag,
  })> filteredTotals({
    required String from,
    required String to,
    String? kind,
    String? accountId,
    String? categoryId,
    String? modeId,
    String? tagId,
    double? amountMin,
    double? amountMax,
  }) async {
    final vars = <Variable>[Variable.withString(from), Variable.withString(to)];
    final where = <String>[
      "t.transaction_date >= ?",
      "t.transaction_date < ?",
    ];
    if (kind != null) {
      where.add("t.kind = ?");
      vars.add(Variable.withString(kind));
    }
    if (accountId != null) {
      where.add("t.account_id = ?");
      vars.add(Variable.withString(accountId));
    }
    if (categoryId != null) {
      where.add("t.category_id = ?");
      vars.add(Variable.withString(categoryId));
    }
    if (modeId != null) {
      where.add("t.mode_id = ?");
      vars.add(Variable.withString(modeId));
    }
    if (amountMin != null) {
      where.add("t.amount >= ?");
      vars.add(Variable.withReal(amountMin));
    }
    if (amountMax != null) {
      where.add("t.amount <= ?");
      vars.add(Variable.withReal(amountMax));
    }
    final whereClause = where.join(' AND ');

    // tagId filter: for count/by_* we apply an IN subquery (appends one var).
    // For byTag we already join transaction_tags, so the tag filter is folded
    // into the join condition there (consuming the same trailing var) — see below.
    String tagFilterClause = '';
    if (tagId != null) {
      tagFilterClause = " AND t.id IN (SELECT transaction_id FROM transaction_tags WHERE tag_id = ?)";
      vars.add(Variable.withString(tagId));
    }
    // byTag joins transaction_tags directly; when tagId is set we add a
    // `tt.tag_id = ?` predicate that consumes the same trailing tagId var.
    final byTagTagClause = tagId != null ? ' AND tt.tag_id = ?' : '';

    final countRow = await _db.customSelect(
      "SELECT COUNT(*) AS cnt, COALESCE(SUM(t.amount),0) AS total "
      "FROM transactions t WHERE $whereClause $tagFilterClause",
      variables: vars,
    ).getSingle();
    final count = (countRow.data['cnt'] as int?) ?? 0;
    final total = (countRow.data['total'] as num).toDouble();

    final byCatRows = await _db.customSelect(
      "SELECT t.category_id AS id, COALESCE(c.name,'Unknown') AS name, "
      "COALESCE(SUM(t.amount),0) AS amount, COUNT(*) AS cnt "
      "FROM transactions t LEFT JOIN categories c ON t.category_id = c.id "
      "WHERE $whereClause $tagFilterClause "
      "GROUP BY t.category_id ORDER BY amount DESC",
      variables: vars,
    ).get();
    final byCategory = byCatRows
        .map((r) => (
              id: r.data['id'] as String? ?? '',
              name: r.data['name'] as String? ?? '',
              amount: (r.data['amount'] as num).toDouble(),
              count: (r.data['cnt'] as int?) ?? 0,
            ))
        .toList();

    final byModeRows = await _db.customSelect(
      "SELECT t.mode_id AS id, COALESCE(m.name,'Unknown') AS name, "
      "COALESCE(SUM(t.amount),0) AS amount, COUNT(*) AS cnt "
      "FROM transactions t LEFT JOIN modes m ON t.mode_id = m.id "
      "WHERE $whereClause $tagFilterClause "
      "GROUP BY t.mode_id ORDER BY amount DESC",
      variables: vars,
    ).get();
    final byMode = byModeRows
        .map((r) => (
              id: r.data['id'] as String? ?? '',
              name: r.data['name'] as String? ?? '',
              amount: (r.data['amount'] as num).toDouble(),
              count: (r.data['cnt'] as int?) ?? 0,
            ))
        .toList();

    final byAccRows = await _db.customSelect(
      "SELECT t.account_id AS id, COALESCE(a.name,'Unknown') AS name, "
      "COALESCE(SUM(t.amount),0) AS amount, COUNT(*) AS cnt "
      "FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id "
      "WHERE $whereClause $tagFilterClause "
      "GROUP BY t.account_id ORDER BY amount DESC",
      variables: vars,
    ).get();
    final byAccount = byAccRows
        .map((r) => (
              id: r.data['id'] as String? ?? '',
              name: r.data['name'] as String? ?? '',
              amount: (r.data['amount'] as num).toDouble(),
              count: (r.data['cnt'] as int?) ?? 0,
            ))
        .toList();

    final byTagRows = await _db.customSelect(
      "SELECT tt.tag_id AS id, COALESCE(tg.name,'Unknown') AS name, "
      "COALESCE(SUM(t.amount),0) AS amount, COUNT(*) AS cnt "
      "FROM transactions t "
      "JOIN transaction_tags tt ON tt.transaction_id = t.id "
      "JOIN tags tg ON tg.id = tt.tag_id "
      "WHERE $whereClause$byTagTagClause "
      "GROUP BY tt.tag_id ORDER BY amount DESC",
      variables: vars,
    ).get();
    final byTag = byTagRows
        .map((r) => (
              id: r.data['id'] as String? ?? '',
              name: r.data['name'] as String? ?? '',
              amount: (r.data['amount'] as num).toDouble(),
              count: (r.data['cnt'] as int?) ?? 0,
            ))
        .toList();

    return (
      count: count,
      total: total,
      byCategory: byCategory,
      byMode: byMode,
      byAccount: byAccount,
      byTag: byTag,
    );
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
