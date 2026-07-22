import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/themes/app_fonts.dart';

import '../../../app/utils/feedback.dart';
import '../../../app/widgets/confirm_delete_dialog.dart';
import '../../../state/custom_report_providers.dart';
import 'custom_report_chart.dart';
import 'custom_report_spec.dart';

/// Renders a saved custom report: loads the spec by id, executes it on-device,
/// and draws it with fl_chart. Offers Edit (back to the builder prefilled) and
/// Delete (confirm dialog + snackbar per List Row Interaction Rules).
///
/// The spec is parsed from the stored JSON and executed locally — it never goes
/// to the LLM and never leaves the device.
class CustomReportViewScreen extends ConsumerWidget {
  const CustomReportViewScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final rowAsync = ref.watch(customReportByIdProvider(id));

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(rowAsync.maybeWhen(
              data: (r) => r?.name ?? 'Report',
              orElse: () => 'Report',
            ),
            style: plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: rowAsync.maybeWhen(
              data: (r) => r == null
                  ? null
                  : () => context.push('/reports/custom-builder?id=${r.id}'),
              orElse: () => null,
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: rowAsync.maybeWhen(
              data: (r) => r == null ? null : () => _confirmDelete(context, ref),
              orElse: () => null,
            ),
          ),
        ],
      ),
      body: rowAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('Could not load report: $e',
                style: TextStyle(color: cs.onSurfaceVariant))),
        data: (row) {
          if (row == null) {
            return Center(
              child: Text('This report no longer exists.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            );
          }
          final spec = CustomReportSpec.fromJsonString(row.specJson);
          final dataAsync = ref.watch(customReportDataProvider(spec));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _SummaryStrip(spec: spec),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: dataAsync.when(
                  loading: () => const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => SizedBox(
                    height: 160,
                    child: Center(
                        child: Text('Could not run: $e',
                            style: TextStyle(color: cs.onSurfaceVariant))),
                  ),
                  data: (rows) =>
                      CustomReportChart(spec: spec, rows: rows, height: 240),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final row = ref.read(customReportByIdProvider(id)).valueOrNull;
    final name = row?.name ?? 'report';
    final ok = await showConfirmDeleteDialog(
      context,
      title: 'Delete report',
      message: 'Delete "$name"? This cannot be undone.',
    );
    if (!ok || !context.mounted) return;
    await ref.read(customReportsDaoProvider).deleteById(id);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, 'Report deleted');
    context.pop();
  }
}

/// A compact one-line summary of the spec's selections, shown above the chart.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.spec});
  final CustomReportSpec spec;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <String>[
      _groupByLabel(spec.groupBy),
      _metricLabel(spec.metric),
      spec.kind.name,
      _rangeLabel(spec),
      if (spec.accountId != null ||
          spec.categoryId != null ||
          spec.modeId != null)
        'filtered',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(c,
                style: plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
          ),
      ],
    );
  }

  String _groupByLabel(CustomGroupBy g) => switch (g) {
        CustomGroupBy.category => 'By category',
        CustomGroupBy.account => 'By account',
        CustomGroupBy.mode => 'By mode',
        CustomGroupBy.day => 'By day',
        CustomGroupBy.month => 'By month',
      };

  String _metricLabel(CustomMetric m) => switch (m) {
        CustomMetric.sum => 'Sum',
        CustomMetric.count => 'Count',
        CustomMetric.avg => 'Average',
      };

  String _rangeLabel(CustomReportSpec s) => switch (s.dateRange) {
        CustomDateRange.thisMonth => 'This month',
        CustomDateRange.last3 => 'Last 3 months',
        CustomDateRange.thisYear => 'This year',
        CustomDateRange.custom => 'Custom range',
      };
}