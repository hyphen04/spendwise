import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/ai/dynamic_report/chart_spec.dart';
import '../features/ai/dynamic_report/default_report_spec.dart';
import '../features/ai/dynamic_report/spec_executor.dart';
import '../features/ai/dynamic_report/sql_guard.dart';
import 'ai_providers.dart'; // aiCustomSqlProvider
import 'database_provider.dart';
import 'home_providers.dart'; // budgetsRepositoryProvider
import 'reports_providers.dart'; // reportsRepositoryProvider
import 'transactions_providers.dart'; // allTransactionsStreamProvider

/// The current report spec. Defaults to [defaultReportSpec]; Phase 2's
/// [AiReportNotifier] replaces this with the LLM-authored spec (validated) when
/// `aiSpecEnabled` is on, and falls back to the default on failure.
final reportSpecProvider =
    StateProvider<DynamicReportSpec>((_) => defaultReportSpec);

/// Builds the [SpecExecutor] from the live repositories + a [SqlGuard] bound to
/// the database. `customSqlEnabled` follows the user's opt-in `aiCustomSql`
/// setting — a stray `customSql` spec can never run before the user opts in.
final specExecutorProvider = Provider<SpecExecutor>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SpecExecutor(
    reports: ref.watch(reportsRepositoryProvider),
    budgets: ref.watch(budgetsRepositoryProvider),
    sqlGuard: SqlGuard(db),
    customSqlEnabled: ref.watch(aiCustomSqlProvider),
  );
});

/// Executes the current [reportSpecProvider] for the given month and returns one
/// [ChartDataset] per chart (same order as the spec). Reacts to transaction
/// changes (via the repositories' underlying streams) and to spec changes.
final dynamicReportDatasetsProvider =
    FutureProvider.family<List<ChartDataset>, (int, int)>((ref, args) async {
  ref.watch(allTransactionsStreamProvider); // re-run on tx changes
  final spec = ref.watch(reportSpecProvider);
  final executor = ref.watch(specExecutorProvider);
  final month = DateTime(args.$1, args.$2);
  return [
    for (final chart in spec.charts) await executor.execute(chart, month),
  ];
});