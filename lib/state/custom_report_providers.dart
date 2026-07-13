import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/db/daos/custom_reports_dao.dart';
import '../features/reports/custom/custom_report_executor.dart';
import '../features/reports/custom/custom_report_spec.dart';
import 'database_provider.dart';
import 'transactions_providers.dart';

/// Repository-style accessor for the `custom_reports` table. We talk to the DAO
/// directly (the table is a thin key/value spec store — no domain logic needs a
/// repository wrapper). Provided here so widgets can `ref.read` it.
final customReportsDaoProvider = Provider<CustomReportsDao>(
    (ref) => ref.watch(appDatabaseProvider).customReportsDao);

/// All saved custom reports, newest-first (reactive — re-emits on save/delete).
final customReportsStreamProvider = StreamProvider<List<CustomReport>>(
    (ref) => ref.watch(customReportsDaoProvider).watchAll());

/// Active tags (for the tag filter picker in the builder). Tags have no
/// existing top-level stream provider, so we expose one here scoped to the
/// custom-report feature.
final tagsForCustomReportProvider = StreamProvider<List<Tag>>(
    (ref) => ref.watch(appDatabaseProvider).tagsDao.watchAll());

/// A single saved spec by id, or null. Future-based (used by the view screen).
final customReportByIdProvider =
    FutureProvider.family<CustomReport?, String>((ref, id) {
  return ref.watch(customReportsDaoProvider).getById(id);
});

/// The in-flight spec being edited in the builder. Stateful so the live preview
/// re-runs as the user toggles groupBy / metric / filters / chart type. Kept
/// separate from the persisted row — committing writes it to the DAO.
final customReportSpecProvider =
    StateProvider<CustomReportSpec>((_) => CustomReportSpec(
          name: 'Untitled report',
          groupBy: CustomGroupBy.category,
          metric: CustomMetric.sum,
          kind: CustomKind.expense,
          dateRange: CustomDateRange.thisMonth,
          chartType: CustomChartType.bar,
        ));

/// The on-device executor. Bound to the database; reused by the preview and the
/// view screen.
final customReportExecutorProvider = Provider<CustomReportExecutor>(
    (ref) => CustomReportExecutor(ref.watch(appDatabaseProvider)));

/// Executes a spec on-device and returns the normalized row list. Family so the
/// builder's live preview and the view screen's saved spec both subscribe. The
/// spec identity is by reference (StateProvider) / by the loaded row's spec —
/// callers pass the spec object as the family arg.
final customReportDataProvider =
    FutureProvider.family<List<CustomReportRow>, CustomReportSpec>((ref, spec) {
  ref.watch(allTransactionsStreamProvider); // re-run on tx changes
  return ref.watch(customReportExecutorProvider).execute(spec);
});