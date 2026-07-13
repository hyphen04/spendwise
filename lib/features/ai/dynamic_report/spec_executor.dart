import '../../../data/repositories/budgets_repository.dart';
import '../../../data/repositories/reports_repository.dart';
import 'chart_spec.dart';
import 'sql_guard.dart';

/// A normalized, row-based dataset the [SpecRenderer] consumes. Named providers
/// are converted to a known row shape (see [SpecExecutor] docs); `customSql`
/// rows come straight from the query (private columns already blocked by
/// [SqlGuard]).
class ChartDataset {
  const ChartDataset(this.rows, this.provider, {this.error});
  final List<Map<String, Object?>> rows;
  final DataProvider provider;
  final String? error;
  bool get isEmpty => rows.isEmpty;
  bool get hasError => error != null;
}

/// Resolves a validated [ChartSpec] to real on-device data. **Privacy: results
/// never leave the device.** Named providers reuse existing repository methods
/// (no new SQL); `customSql` runs through [SqlGuard].
///
/// Row shapes produced per provider (the renderer reads these by convention,
/// overridable via [ChartSpec.series]):
/// - topCategories → {name, icon, color, total}
/// - cashflow6mo → {year, month, income, expense, net}
/// - budgets → {name, icon, color, spent, effective, fraction, isOver}
/// - modes → {name, icon, total}
/// - monthlySummary → {income, expense, net, opening, closing} (one row)
/// - customSql → raw rows (LLM-defined columns; PII columns blocked upstream)
class SpecExecutor {
  SpecExecutor({
    required ReportsRepository reports,
    required BudgetsRepository budgets,
    required SqlGuard sqlGuard,
    required this.customSqlEnabled,
  })  : _reports = reports,
        _budgets = budgets,
        _sqlGuard = sqlGuard;

  final ReportsRepository _reports;
  final BudgetsRepository _budgets;
  final SqlGuard _sqlGuard;
  final bool customSqlEnabled;

  Future<ChartDataset> execute(ChartSpec spec, DateTime month) async {
    final from = month.toIso8601String();
    final to = DateTime(month.year, month.month + 1).toIso8601String();

    switch (spec.provider) {
      case DataProvider.topCategories:
        final limit = _intParam(spec, 'limit', 10);
        final cats = await _reports.topSpends(from: from, to: to, limit: limit);
        return ChartDataset(
          cats
              .map((c) => <String, Object?>{
                    'name': c.name,
                    'icon': c.icon,
                    'color': c.color,
                    'total': c.total,
                  })
              .toList(),
          spec.provider,
        );

      case DataProvider.cashflow6mo:
        final count = _intParam(spec, 'count', 6);
        final cf = await _reports.cashFlowMonths(count: count);
        return ChartDataset(
          cf
              .map((m) => <String, Object?>{
                    'year': m.year,
                    'month': m.month,
                    'income': m.income,
                    'expense': m.expense,
                    'net': m.net,
                  })
              .toList(),
          spec.provider,
        );

      case DataProvider.budgets:
        final list = await _budgets.progressForMonth(month);
        return ChartDataset(
          list
              .map((b) => <String, Object?>{
                    'name': b.categoryName,
                    'icon': b.categoryIcon,
                    'color': b.categoryColor,
                    'spent': b.spent,
                    'effective': b.effectiveAmount,
                    'fraction': b.fraction,
                    'isOver': b.isOver,
                  })
              .toList(),
          spec.provider,
        );

      case DataProvider.modes:
        final kind = _stringParam(spec, 'kind', 'expense');
        final modes = await _reports.modeBreakdown(from: from, to: to, kind: kind);
        return ChartDataset(
          modes
              .map((m) => <String, Object?>{
                    'name': m.name,
                    'icon': m.icon,
                    'total': m.total,
                  })
              .toList(),
          spec.provider,
        );

      case DataProvider.monthlySummary:
        final s = await _reports.monthlySummary(month.year, month.month);
        return ChartDataset(
          [
            <String, Object?>{
              'income': s.income,
              'expense': s.expense,
              'net': s.net,
              'opening': s.openingBalance,
              'closing': s.closingBalance,
            }
          ],
          spec.provider,
        );

      case DataProvider.customSql:
        if (!customSqlEnabled) {
          return ChartDataset(const [], spec.provider,
              error: 'Custom SQL is not enabled in settings.');
        }
        final sql = _stringParam(spec, 'sql', '');
        if (sql.isEmpty) {
          return ChartDataset(const [], spec.provider,
              error: 'No SQL provided.');
        }
        final res = await _sqlGuard.run(sql);
        if (!res.ok) {
          return ChartDataset(const [], spec.provider, error: res.error);
        }
        return ChartDataset(res.rows, spec.provider);
    }
  }

  int _intParam(ChartSpec spec, String key, int fallback) {
    final v = spec.params[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  String _stringParam(ChartSpec spec, String key, String fallback) {
    final v = spec.params[key];
    return v is String ? v : fallback;
  }
}