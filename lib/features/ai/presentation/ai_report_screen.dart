import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/utils/feedback.dart';
import '../../../state/ai_providers.dart';
import '../../../state/dynamic_report_providers.dart';
import '../../../state/period_providers.dart';
import '../dynamic_report/chart_spec.dart';
import '../dynamic_report/spec_executor.dart';
import '../dynamic_report/spec_renderer.dart';
import '../services/ai_pdf_exporter.dart';
import '../services/ai_report_controller.dart';
import '../widgets/ai_markdown.dart';
import 'widgets/checked_on_device_note.dart';

/// On-demand narrative AI report, with always-on on-device charts.
///
/// The screen always shows accurate charts (category donut, 6-month cashflow
/// bars, budget progress) built from the user's real aggregations via
/// [aiReportDataProvider] — these render even when AI is off, so the report is
/// useful and visual without a key. When AI is enabled + a key is set, tapping
/// Generate streams a narrative (rendered with [AiMarkdown]) below the
/// charts. The [AiGatekeeper] restores opaque labels → real names on-device and
/// validates the reply before it is shown; a "Checked on-device" note marks it.
class AiReportScreen extends ConsumerStatefulWidget {
  const AiReportScreen({super.key});

  @override
  ConsumerState<AiReportScreen> createState() => _AiReportScreenState();
}

class _AiReportScreenState extends ConsumerState<AiReportScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final p = ref.read(selectedPeriodProvider);
    _selectedMonth = DateTime(p.year, p.month);
  }

  void _stepMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  String _label(DateTime m) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'
    ];
    return '${names[m.month - 1]} ${m.year}';
  }

  /// Compact month-stepper chevron sized to fit inside the narrow AppBar title
  /// area (the title slot is constrained to ~170 px, so default 48 px IconButtons
  /// + the month label overflow it).
  Widget _compactChevron({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
    );
  }

  Future<void> _generate() async {
    await ref.read(aiReportProvider.notifier).generate(_selectedMonth);
  }

  Future<void> _exportPdf() async {
    final state = ref.read(aiReportProvider);
    if (!state.hasResult) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final path = await AiPdfExporter.export(
        markdown: state.markdown,
        periodLabel: _label(state.periodMonth ?? _selectedMonth),
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: 'SpendWise AI Report'),
      );
    } catch (e) {
      if (mounted) {
        showFeedbackSnackBar(context, 'Could not export PDF: $e');
      } else if (messenger != null) {
        messenger.showSnackBar(SnackBar(content: Text('Could not export PDF: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = ref.watch(aiEnabledProvider);
    final state = ref.watch(aiReportProvider);
    final matchesSelected = state.periodMonth != null &&
        state.periodMonth!.year == _selectedMonth.year &&
        state.periodMonth!.month == _selectedMonth.month;

    return Scaffold(
      appBar: AppBar(
        // Month stepper is always available (charts are month-specific even
        // with AI off). FittedBox scales the label to fit the narrow title
        // slot instead of clipping it to nothing (matches ReportPeriodAppBar).
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _compactChevron(
              tooltip: 'Previous month',
              icon: Icons.chevron_left_rounded,
              onTap: () => _stepMonth(-1),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _label(_selectedMonth),
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            _compactChevron(
              tooltip: 'Next month',
              icon: Icons.chevron_right_rounded,
              onTap: () => _stepMonth(1),
            ),
          ],
        ),
        actions: [
          if (enabled) ...[
            IconButton(
              tooltip: 'Regenerate',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: state.status == AiReportStatus.streaming ||
                      state.status == AiReportStatus.loading
                  ? null
                  : () => ref.read(aiReportProvider.notifier).regenerate(),
            ),
            IconButton(
              tooltip: 'Export as PDF',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: (state.hasResult && matchesSelected) ? _exportPdf : null,
            ),
            IconButton(
              tooltip: 'AI settings',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => context.push('/ai/settings'),
            ),
          ],
        ],
      ),
      floatingActionButton: (enabled &&
              matchesSelected &&
              state.status == AiReportStatus.done)
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.icon(
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Export PDF'),
                onPressed: _exportPdf,
              ),
            )
          : null,
      body: _body(cs, state, enabled, matchesSelected),
    );
  }

  Widget _body(
      ColorScheme cs, AiReportState state, bool enabled, bool matchesSelected) {
    // Once a report exists for the selected month, the on-device charts move
    // *inline* into the document (the LLM places them with {{chart:N}} markers,
    // unreferenced ones appended). Until then — AI off, CTA, loading, or error
    // with no partial result — the always-on charts block stays so the screen is
    // useful without a key.
    final hasResult = state.hasResult && matchesSelected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      children: [
        if (!hasResult) ...[
          _chartsSection(cs),
          const SizedBox(height: 16),
        ],

        // AI narrative / status. When a report exists this renders the
        // interleaved document (charts inline) instead of a separate block.
        if (!enabled)
          _aiOffBanner(cs)
        else if (!matchesSelected || (state.status == AiReportStatus.idle && !state.hasResult))
          _generateCta(cs)
        else if (state.status == AiReportStatus.loading && !state.hasResult)
          _loadingBlock(cs)
        else if (state.status == AiReportStatus.error && !state.hasResult)
          _errorBlock(cs, state.error ?? 'Something went wrong.')
        else ...[
          CheckedOnDeviceNote(flagged: state.flagged),
          ..._reportDocument(cs, state),
          if (state.status == AiReportStatus.streaming) _streamingIndicator(cs),
          if (state.status == AiReportStatus.error) ...[
            const SizedBox(height: 12),
            _inlineError(cs, state.error ?? 'Something went wrong.'),
          ],
        ],
      ],
    );
  }

  /// Builds the interleaved report document: the streamed markdown split on
  /// `{{chart:N}}` markers into text segments (rendered with [AiMarkdown]) and
  /// inline [SpecChart]s at the LLM-chosen positions. Charts the LLM didn't
  /// place are appended after the prose so none are lost. Datasets come from
  /// the same [dynamicReportDatasetsProvider] the charts block used, so inline
  /// charts share the always-accurate on-device data.
  List<Widget> _reportDocument(ColorScheme cs, AiReportState state) {
    final spec = ref.watch(reportSpecProvider);
    final datasetsAsync = ref.watch(dynamicReportDatasetsProvider(
        (_selectedMonth.year, _selectedMonth.month)));
    final chartCount = spec.charts.length;

    final segments = _splitMarkdown(state.markdown, chartCount);
    final referenced = <int>{};
    for (final s in segments) {
      if (s.isChart) referenced.add(s.chartIndex!);
    }
    final unreferenced = [
      for (var i = 0; i < chartCount; i++) if (!referenced.contains(i)) i,
    ];

    final widgets = <Widget>[];
    for (final seg in segments) {
      if (seg.isChart) {
        widgets.add(const SizedBox(height: 14));
        widgets.add(_inlineChart(cs, spec, datasetsAsync, seg.chartIndex!));
      } else {
        final t = seg.text ?? '';
        if (t.trim().isNotEmpty) widgets.add(AiMarkdown(source: t));
      }
    }
    for (final i in unreferenced) {
      widgets.add(const SizedBox(height: 14));
      widgets.add(_inlineChart(cs, spec, datasetsAsync, i));
    }
    return widgets;
  }

  /// One inline chart, with a quiet loading placeholder while its dataset is
  /// still being executed (the spec is resolved before streaming starts, so
  /// datasets are usually warm by the time a marker arrives).
  Widget _inlineChart(
    ColorScheme cs,
    DynamicReportSpec spec,
    AsyncValue<List<ChartDataset>> datasetsAsync,
    int index,
  ) {
    return datasetsAsync.when(
      loading: () => _inlineChartLoading(cs),
      error: (e, _) => _ChartSurface(
        child: _emptyBlock(cs, 'Could not load this chart.'),
      ),
      data: (datasets) {
        if (index >= datasets.length) return const SizedBox.shrink();
        return SpecChart(spec: spec.charts[index], dataset: datasets[index]);
      },
    );
  }

  Widget _inlineChartLoading(ColorScheme cs) {
    return _ChartSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: cs.primary),
          ),
        ),
      ),
    );
  }

  /// Splits the streamed markdown on complete `{{chart:N}}` markers into text
  /// and chart segments. Out-of-range indices are dropped (neither rendered as
  /// a chart nor left as literal text). Partial markers (e.g. `{{chart:1`
  /// without `}}`) don't match the regex, so while streaming they stay in the
  /// text segment and only resolve once the marker completes.
  List<_Segment> _splitMarkdown(String markdown, int chartCount) {
    if (chartCount == 0) {
      return markdown.trim().isEmpty
          ? const []
          : [_Segment.text(markdown)];
    }
    final re = RegExp(r'\{\{chart:(\d+)\}\}');
    final segments = <_Segment>[];
    var last = 0;
    for (final m in re.allMatches(markdown)) {
      if (m.start > last) {
        segments.add(_Segment.text(markdown.substring(last, m.start)));
      }
      final idx = int.tryParse(m.group(1)!) ?? -1;
      if (idx >= 0 && idx < chartCount) segments.add(_Segment.chart(idx));
      last = m.end;
    }
    if (last < markdown.length) {
      segments.add(_Segment.text(markdown.substring(last)));
    }
    return segments;
  }

  Widget _chartsSection(ColorScheme cs) {
    final spec = ref.watch(reportSpecProvider);
    final datasetsAsync = ref.watch(dynamicReportDatasetsProvider(
        (_selectedMonth.year, _selectedMonth.month)));

    return datasetsAsync.when(
      loading: () => _chartPlaceholder(cs),
      error: (e, _) => _ChartSurface(
        child: _emptyBlock(cs, 'Could not load data for this month.'),
      ),
      data: (datasets) => Column(
        children: [
          for (var i = 0; i < spec.charts.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: SpecChart(
                spec: spec.charts[i],
                dataset: datasets[i],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chartPlaceholder(ColorScheme cs) {
    return _ChartSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: cs.primary),
          ),
        ),
      ),
    );
  }

  Widget _aiOffBanner(ColorScheme cs) {
    return _ChartSurface(
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined,
              size: 32, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('AI Copilot is off',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'The charts above are on-device and always accurate. Bring your own '
            'API key to generate a written narrative about this month — only '
            'aggregated, anonymized numbers are sent to the AI you choose, and '
            'real names are restored on-device.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Configure AI'),
            onPressed: () => context.push('/ai/settings'),
          ),
        ],
      ),
    );
  }

  Widget _generateCta(ColorScheme cs) {
    return _ChartSurface(
      child: Column(
        children: [
          Icon(Icons.auto_awesome_rounded,
              size: 32, color: cs.primary.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text('Generate an AI narrative',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'A friendly written summary of this month — overview, spending, '
            'budgets, cashflow, and actionable takeaways. Real names are '
            'restored on-device; only anonymized numbers are sent.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Generate report'),
            onPressed: _generate,
          ),
        ],
      ),
    );
  }

  Widget _loadingBlock(ColorScheme cs) {
    return _ChartSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text('Generating your report…',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _errorBlock(ColorScheme cs, String message) {
    return _ChartSurface(
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, size: 36, color: cs.error),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
            onPressed: _generate,
          ),
        ],
      ),
    );
  }

  Widget _emptyBlock(ColorScheme cs, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
      ),
    );
  }

  Widget _inlineError(ColorScheme cs, String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: cs.onErrorContainer)),
          ),
        ],
      ),
    );
  }

  Widget _streamingIndicator(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Text('Writing…',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// The shared surface for every chart / status block on this screen.
class _ChartSurface extends StatelessWidget {
  const _ChartSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

/// One piece of the interleaved report document: either a markdown text segment
/// or an inline chart referenced by its 0-based index in the current spec.
class _Segment {
  const _Segment.text(this.text)
      : isChart = false,
        chartIndex = null;
  const _Segment.chart(this.chartIndex)
      : isChart = true,
        text = null;

  final bool isChart;
  final int? chartIndex;
  final String? text;
}