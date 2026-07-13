import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/utils/money_format.dart';
import '../../../utils/color_utils.dart';
import 'custom_report_executor.dart';
import 'custom_report_spec.dart';

/// Renders a [CustomReportSpec] + its executed [CustomReportRow] list with
/// fl_chart. Mirrors the dynamic-report `SpecChart` styling (donut + wrapped
/// legend, single-series bars, line over time, ranked list, big-number stat) so
/// the custom report feels native to the rest of the Reports hub.
///
/// Pure presentation: it never queries anything and never touches the network.
/// The rows it receives are on-device aggregates only (no notes / PII).
class CustomReportChart extends StatelessWidget {
  const CustomReportChart({
    super.key,
    required this.spec,
    required this.rows,
    this.height = 200,
  });

  final CustomReportSpec spec;
  final List<CustomReportRow> rows;
  final double height;

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) {
      return _empty(context, cs, 'No data for this combination yet.');
    }
    return switch (spec.chartType) {
      CustomChartType.bar => _bar(context, cs),
      CustomChartType.pie => _pie(context, cs),
      CustomChartType.line => _line(context, cs),
      CustomChartType.list => _list(context, cs),
      CustomChartType.stat => _stat(context, cs),
    };
  }

  // ── bar ───────────────────────────────────────────────────────────────────
  Widget _bar(BuildContext context, ColorScheme cs) {
    final maxY = rows.fold<double>(0, (m, r) => max(m, r.value));
    final yMax = maxY > 0 ? maxY * 1.15 : 1000.0;
    final colors = _rowColors(cs);
    // For day/month groupings, keep every bar but thin them; otherwise cap at
    // the top 12 so the axis stays readable.
    final shown = rows.length > 12 && spec.groupBy != CustomGroupBy.day
        ? rows.sublist(0, 12)
        : rows;
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: yMax,
          barGroups: shown.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.value,
                  color: colors[rows.indexOf(e.value)],
                  width: 14,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= shown.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _shortLabel(shown[i].label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            horizontalInterval: yMax / 4,
            getDrawingHorizontalLine: (v) => FlLine(
                color: cs.outlineVariant.withAlpha(50), strokeWidth: 1),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  // ── pie ───────────────────────────────────────────────────────────────────
  Widget _pie(BuildContext context, ColorScheme cs) {
    final sliceRows = rows.where((r) => r.value > 0).toList();
    if (sliceRows.isEmpty) {
      return _empty(context, cs, 'No positive values to chart.');
    }
    final total = sliceRows.fold<double>(0, (s, r) => s + r.value);
    final colors = _rowColors(cs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: PieChart(
            PieChartData(
              sections: sliceRows.asMap().entries.map((e) {
                final pct = total > 0 ? e.value.value / total : 0.0;
                return PieChartSectionData(
                  value: e.value.value,
                  color: colors[rows.indexOf(e.value)],
                  radius: 48,
                  title:
                      pct > 0.08 ? '${(pct * 100).toStringAsFixed(0)}%' : '',
                  titleStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.surface),
                );
              }).toList(),
              sectionsSpace: 2,
              centerSpaceRadius: 48,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final r in sliceRows.take(5))
              _legendChip(cs,
                  color: colors[rows.indexOf(r)],
                  icon: r.icon,
                  name: r.label,
                  amount: _formatValue(r.value)),
            if (sliceRows.length > 5)
              _legendChip(cs,
                  color: cs.outline,
                  icon: '⋯',
                  name: 'Other',
                  amount: _formatValue(
                      sliceRows.skip(5).fold<double>(0, (s, r) => s + r.value))),
          ],
        ),
      ],
    );
  }

  // ── line ──────────────────────────────────────────────────────────────────
  Widget _line(BuildContext context, ColorScheme cs) {
    final maxY = rows.fold<double>(0, (m, r) => max(m, r.value));
    final yMax = maxY > 0 ? maxY * 1.15 : 1000.0;
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: yMax,
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              color: cs.primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
              spots: rows
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value.value))
                  .toList(),
            ),
          ],
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: max(1, rows.length ~/ 6).toDouble(),
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= rows.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _shortLabel(rows[i].label),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            horizontalInterval: yMax / 4,
            getDrawingHorizontalLine: (v) => FlLine(
                color: cs.outlineVariant.withAlpha(50), strokeWidth: 1),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  // ── list ──────────────────────────────────────────────────────────────────
  Widget _list(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                if (r.icon.isNotEmpty) ...[
                  Text(r.icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                ],
                if (r.color.isNotEmpty) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: hexToColor(r.color, fallback: cs.primary),
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(r.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                ),
                Text(_formatValue(r.value),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
      ],
    );
  }

  // ── stat ──────────────────────────────────────────────────────────────────
  Widget _stat(BuildContext context, ColorScheme cs) {
    final value = rows.fold<double>(0, (s, r) => s + r.value);
    final color = value < 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_formatValue(value),
            style: GoogleFonts.plusJakartaSans(
                fontSize: 28, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(
          '${_metricLabel(spec.metric)} of ${spec.kind.name} • ${_groupByLabel(spec.groupBy)}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// One color per source row (index-aligned with `rows`), so the bar/pie/line
  /// palettes stay consistent across chart-type switches in the live preview.
  List<Color> _rowColors(ColorScheme cs) {
    final palette = [
      cs.primary,
      const Color(0xFF16A34A),
      const Color(0xFFDC2626),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFF0284C7),
      const Color(0xFFEC4899),
      const Color(0xFF14B8A6),
      const Color(0xFFD97706),
      const Color(0xFF6366F1),
    ];
    return rows
        .asMap()
        .entries
        .map((e) => hexToColor(e.value.color,
            fallback: palette[e.key % palette.length]))
        .toList();
  }

  String _formatValue(double v) {
    if (spec.metric == CustomMetric.count) {
      return v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    }
    return fmtMoney(v);
  }

  /// Shorten a label for a chart axis: day → "dd", month → "Mon", else first 6
  /// chars.
  String _shortLabel(String label) {
    if (spec.groupBy == CustomGroupBy.day && label.length >= 10) {
      return label.substring(8, 10);
    }
    if (spec.groupBy == CustomGroupBy.month && label.length >= 7) {
      final m = int.tryParse(label.substring(5, 7));
      if (m != null && m >= 1 && m <= 12) return _monthNames[m - 1];
    }
    return label.length > 6 ? label.substring(0, 6) : label;
  }

  Widget _legendChip(ColorScheme cs,
      {required Color color,
      required String icon,
      required String name,
      required String amount}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        if (icon.isNotEmpty) ...[
          Text(icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
        ],
        Text(name,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Text(amount,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _empty(BuildContext context, ColorScheme cs, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: cs.onSurfaceVariant)),
      ),
    );
  }
}

String _metricLabel(CustomMetric m) => switch (m) {
      CustomMetric.sum => 'Total',
      CustomMetric.count => 'Count',
      CustomMetric.avg => 'Average',
    };

String _groupByLabel(CustomGroupBy g) => switch (g) {
      CustomGroupBy.category => 'by category',
      CustomGroupBy.account => 'by account',
      CustomGroupBy.mode => 'by mode',
      CustomGroupBy.tag => 'by tag',
      CustomGroupBy.day => 'by day',
      CustomGroupBy.month => 'by month',
    };