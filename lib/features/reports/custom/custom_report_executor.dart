import 'package:drift/drift.dart';

import '../../../data/db/app_database.dart';
import 'custom_report_spec.dart';

/// One normalized result row from executing a [CustomReportSpec].
///
/// `value` is the metric (sum / count / avg of `amount`). `key` is the stable
/// group identifier (a UUID for category/account/mode/tag, or a `yyyy-MM-dd` /
/// `yyyy-MM` string for day/month). `label` is the human label shown on the
/// chart axis / legend. `icon`/`color` are present when the group dimension
/// carries them (category/account/mode/tag).
class CustomReportRow {
  const CustomReportRow({
    required this.key,
    required this.label,
    required this.value,
    this.icon = '',
    this.color = '',
  });

  final String key;
  final String label;
  final double value;
  final String icon;
  final String color;

  Map<String, Object?> toMap() => {
        'key': key,
        'label': label,
        'value': value,
        'icon': icon,
        'color': color,
      };
}

/// Executes a [CustomReportSpec] on-device and returns a normalized row list
/// suitable for fl_chart.
///
/// **Privacy (the primary invariant):** the executor is hard-constrained to the
/// safe table subset — `transactions` joined to `accounts` / `categories` /
/// `modes` / `tags` / `transaction_tags` only. It NEVER reads `note` or
/// `receipt_path`, and NEVER touches `due_*` / `ai_*` / `recurring_items` /
/// `goals`. This mirrors `SqlGuard`'s allow/deny philosophy, but unlike
/// `customSql` the SQL is built from a fixed enum vocabulary + UUID filter ids
/// (no user-authored SQL, no injection surface). Results stay on-device and are
/// never sent to the LLM — the spec itself never leaves the device either.
class CustomReportExecutor {
  CustomReportExecutor(this._db);

  final AppDatabase _db;

  /// Tables the executor may reference. Anything not here is unreachable.
  static const allowedTables = {
    'transactions',
    'accounts',
    'categories',
    'modes',
    'tags',
    'transaction_tags',
  };

  /// Columns the executor never selects (PII). Enforced by construction — the
  /// queries below simply do not reference them — but listed here as the
  /// explicit contract, mirroring `SqlGuard._deniedColumns`.
  static const deniedColumns = {
    'note',
    'receipt_path',
    'phone',
    'photo_path',
    'device_contact_id',
    'phones',
  };

  Future<List<CustomReportRow>> execute(CustomReportSpec spec) async {
    final (from, to) = _resolveRange(spec);
    final rows = await _db.customSelect(
      _buildSql(spec),
      variables: _bindArgs(spec, from, to),
    ).get();

    return rows.map((r) {
      final data = r.data;
      return CustomReportRow(
        key: (data['k'] ?? '').toString(),
        label: (data['label'] ?? 'Unknown').toString(),
        value: (data['v'] as num?)?.toDouble() ?? 0.0,
        icon: (data['icon'] ?? '').toString(),
        color: (data['color'] ?? '').toString(),
      );
    }).toList();
  }

  // ── Date range ────────────────────────────────────────────────────────────

  /// Returns `(fromIso, toIso)` for the spec's [CustomDateRange].
  (String, String) _resolveRange(CustomReportSpec spec) {
    final now = DateTime.now();
    switch (spec.dateRange) {
      case CustomDateRange.thisMonth:
        return (
          DateTime(now.year, now.month).toIso8601String(),
          DateTime(now.year, now.month + 1).toIso8601String(),
        );
      case CustomDateRange.last3:
        return (
          DateTime(now.year, now.month - 2).toIso8601String(),
          DateTime(now.year, now.month + 1).toIso8601String(),
        );
      case CustomDateRange.thisYear:
        return (
          DateTime(now.year, 1).toIso8601String(),
          DateTime(now.year + 1, 1).toIso8601String(),
        );
      case CustomDateRange.custom:
        final from = spec.customFrom ?? DateTime(now.year, now.month).toIso8601String();
        final to = spec.customTo ?? DateTime(now.year, now.month + 1).toIso8601String();
        return (from, to);
    }
  }

  // ── SQL builder (fixed vocabulary — no user-authored SQL) ──────────────────

  String _buildSql(CustomReportSpec spec) {
    final kindClause = _kindClause(spec.kind);
    final where = <String>[
      "t.transaction_date >= ?",
      "t.transaction_date < ?",
      kindClause,
      if (spec.accountId != null) 't.account_id = ?',
      if (spec.categoryId != null) 't.category_id = ?',
      if (spec.modeId != null) 't.mode_id = ?',
      if (spec.tagId != null && spec.groupBy != CustomGroupBy.tag)
        't.id IN (SELECT transaction_id FROM transaction_tags WHERE tag_id = ?)',
    ];

    final aggregate = _aggregate(spec.metric);
    final groupDim = _groupDimension(spec.groupBy);
    final labelExpr = _labelExpression(spec.groupBy);
    final iconExpr = _iconExpression(spec.groupBy);
    final colorExpr = _colorExpression(spec.groupBy);
    final joins = _joins(spec.groupBy);

    // Group key + label + icon + color + metric value. Only safe columns are
    // ever selected (never note / receipt_path / any PII column).
    final selectCols = [
      '$groupDim AS k',
      '$labelExpr AS label',
      if (iconExpr != null) '$iconExpr AS icon',
      if (colorExpr != null) '$colorExpr AS color',
      '$aggregate AS v',
    ];

    // day / month groupings are chronological; the rest rank by value desc.
    final orderBy = (spec.groupBy == CustomGroupBy.day ||
            spec.groupBy == CustomGroupBy.month)
        ? 'ORDER BY k ASC'
        : 'ORDER BY v DESC';

    return 'SELECT ${selectCols.join(', ')} '
        'FROM transactions t $joins '
        'WHERE ${where.where((c) => c.isNotEmpty).join(' AND ')} '
        'GROUP BY $groupDim '
        '$orderBy';
  }

  List<Variable> _bindArgs(CustomReportSpec spec, String from, String to) {
    final args = <Variable>[
      Variable.withString(from),
      Variable.withString(to),
    ];
    if (spec.accountId != null) args.add(Variable.withString(spec.accountId!));
    if (spec.categoryId != null) args.add(Variable.withString(spec.categoryId!));
    if (spec.modeId != null) args.add(Variable.withString(spec.modeId!));
    if (spec.tagId != null && spec.groupBy != CustomGroupBy.tag) {
      args.add(Variable.withString(spec.tagId!));
    }
    return args;
  }

  String _kindClause(CustomKind kind) {
    switch (kind) {
      case CustomKind.expense:
        return "t.kind = 'expense'";
      case CustomKind.income:
        return "t.kind = 'income'";
      case CustomKind.all:
        // Income + expense only — transfers are internal movement, not spend.
        return "t.kind IN ('income','expense')";
    }
  }

  String _aggregate(CustomMetric metric) {
    switch (metric) {
      case CustomMetric.sum:
        return 'COALESCE(SUM(t.amount),0)';
      case CustomMetric.count:
        return 'COUNT(*)';
      case CustomMetric.avg:
        return 'COALESCE(AVG(t.amount),0)';
    }
  }

  /// The GROUP BY expression — also used as the row key.
  String _groupDimension(CustomGroupBy group) {
    switch (group) {
      case CustomGroupBy.category:
        return 't.category_id';
      case CustomGroupBy.account:
        return 't.account_id';
      case CustomGroupBy.mode:
        return 't.mode_id';
      case CustomGroupBy.tag:
        return 'tt.tag_id';
      case CustomGroupBy.day:
        return 'substr(t.transaction_date,1,10)';
      case CustomGroupBy.month:
        return 'substr(t.transaction_date,1,7)';
    }
  }

  String _labelExpression(CustomGroupBy group) {
    switch (group) {
      case CustomGroupBy.category:
        return 'COALESCE(c.name,\'Uncategorized\')';
      case CustomGroupBy.account:
        return 'COALESCE(a.name,\'Unknown\')';
      case CustomGroupBy.mode:
        return 'COALESCE(m.name,\'Unknown\')';
      case CustomGroupBy.tag:
        return 'COALESCE(tg.name,\'Untagged\')';
      case CustomGroupBy.day:
        // "yyyy-MM-dd" is a fine axis label; the renderer can shorten it.
        return 'substr(t.transaction_date,1,10)';
      case CustomGroupBy.month:
        // "yyyy-MM" — the renderer maps it to a month name.
        return 'substr(t.transaction_date,1,7)';
    }
  }

  String? _iconExpression(CustomGroupBy group) {
    switch (group) {
      case CustomGroupBy.category:
        return "COALESCE(c.icon,'')";
      case CustomGroupBy.account:
        return "COALESCE(a.icon,'')";
      case CustomGroupBy.mode:
        return "COALESCE(m.icon,'')";
      case CustomGroupBy.tag:
      case CustomGroupBy.day:
      case CustomGroupBy.month:
        return null;
    }
  }

  String? _colorExpression(CustomGroupBy group) {
    switch (group) {
      case CustomGroupBy.category:
        return "COALESCE(c.color,'#475569')";
      case CustomGroupBy.account:
        return "COALESCE(a.color,'#475569')";
      case CustomGroupBy.tag:
        return "COALESCE(tg.color,'#475569')";
      case CustomGroupBy.mode:
      case CustomGroupBy.day:
      case CustomGroupBy.month:
        return null;
    }
  }

  String _joins(CustomGroupBy group) {
    switch (group) {
      case CustomGroupBy.category:
        return 'LEFT JOIN categories c ON t.category_id = c.id';
      case CustomGroupBy.account:
        return 'LEFT JOIN accounts a ON t.account_id = a.id';
      case CustomGroupBy.mode:
        return 'LEFT JOIN modes m ON t.mode_id = m.id';
      case CustomGroupBy.tag:
        // JOIN (not LEFT) so untagged transactions are excluded from a tag
        // breakdown — they don't belong to any tag group.
        return 'JOIN transaction_tags tt ON tt.transaction_id = t.id '
            'JOIN tags tg ON tt.tag_id = tg.id';
      case CustomGroupBy.day:
      case CustomGroupBy.month:
        return '';
    }
  }
}