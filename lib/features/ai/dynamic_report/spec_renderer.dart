import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/utils/money_format.dart';
import '../../../utils/color_utils.dart';
import 'chart_spec.dart';
import 'spec_executor.dart';

/// The spec→widget dispatcher the codebase previously lacked. Maps a
/// [ChartSpec] + its executed [ChartDataset] to an fl_chart / list widget.
///
/// This is pure presentation: it reads the normalized row shapes documented on
/// [SpecExecutor] and renders. It never queries anything, never touches the
/// network, and never renders raw PII — `customSql` rows are already filtered
/// by [SqlGuard] upstream, and named providers only ever carry aggregate
/// totals + category/mode names (the user's own data, shown back to the user).
///
/// Empty / error datasets degrade to a quiet empty-state card rather than
/// crashing, so a single bad chart never blanks the whole report.
class SpecChart extends StatelessWidget {
  const SpecChart({super.key, required this.spec, required this.dataset});
  final ChartSpec spec;
  final ChartDataset dataset;

  static const _incomeColor = Color(0xFF16A34A);
  static const _expenseColor = Color(0xFFDC2626);

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    if (dataset.hasError) {
      return _ChartCard(
        title: spec.title,
        child: _empty(context, dataset.error ?? 'Could not build this chart.'),
      );
    }
    if (dataset.isEmpty) {
      return _ChartCard(
        title: spec.title,
        child: _empty(context, _emptyMessage(spec)),
      );
    }
    final widget = switch (spec.type) {
      ChartType.pie => _pie(context),
      ChartType.bar => _bar(context),
      ChartType.line => _line(context),
      ChartType.progress => _progress(context),
      ChartType.list => _list(context),
      ChartType.stat => _stat(context),
    };
    return _ChartCard(title: spec.title, child: widget);
  }

  String _emptyMessage(ChartSpec spec) => switch (spec.provider) {
        DataProvider.topCategories => 'No spending recorded for this month.',
        DataProvider.cashflow6mo => 'No cashflow data yet.',
        DataProvider.budgets => 'No budgets set for this month.',
        DataProvider.modes => 'No payment-mode activity this month.',
        DataProvider.monthlySummary => 'No activity this month.',
        DataProvider.customSql => 'This query returned no rows.',
      };

  // ── pie ──────────────────────────────────────────────────────────────────
  //
  // Donut centered on top, wrapped legend below. The previous side-by-side
  // layout (pie left / legend right inside a 180pt Row) squeezed both halves
  // and crowded the slice-% labels against the center hole. Stacking vertically
  // gives the donut the full width (larger hole, fewer overlapping labels) and
  // lets long category names wrap instead of ellipsing into the chart.
  Widget _pie(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = dataset.rows.where((r) => _d(r, 'total') > 0).toList();
    if (rows.isEmpty) {
      return _empty(context, 'No spending recorded for this month.');
    }
    final total = rows.fold<double>(0, (s, r) => s + _d(r, 'total'));
    final colors = rows
        .map((r) => hexToColor(_s(r, 'color'), fallback: cs.primary))
        .toList();

    // Cap the legend at the top 5 slices and roll the rest into "Other" so the
    // wrap stays short; the donut still draws every slice.
    const legendCount = 5;
    final legendRows = rows.take(legendCount).toList();
    final otherRows = rows.skip(legendCount).toList();
    final otherTotal =
        otherRows.fold<double>(0, (s, r) => s + _d(r, 'total'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 180,
          width: double.infinity,
          child: PieChart(
            PieChartData(
              sections: rows.asMap().entries.map((e) {
                final pct = total > 0 ? _d(e.value, 'total') / total : 0.0;
                return PieChartSectionData(
                  value: _d(e.value, 'total'),
                  color: colors[e.key],
                  radius: 48,
                  // Only label slices big enough to read; tighter threshold +
                  // bigger center hole keeps labels from piling up.
                  title: pct > 0.08
                      ? '${(pct * 100).toStringAsFixed(0)}%'
                      : '',
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
            for (final e in legendRows.asMap().entries)
              _legendChip(
                cs,
                color: colors[e.key],
                icon: _s(e.value, 'icon'),
                name: _s(e.value, 'name'),
                amount: fmtMoney(_d(e.value, 'total')),
              ),
            if (otherTotal > 0)
              _legendChip(
                cs,
                color: cs.outline,
                icon: '⋯',
                name: 'Other',
                amount: fmtMoney(otherTotal),
              ),
          ],
        ),
      ],
    );
  }

  Widget _legendChip(
    ColorScheme cs, {
    required Color color,
    required String icon,
    required String name,
    required String amount,
  }) {
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

  // ── bar ──────────────────────────────────────────────────────────────────
  Widget _bar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Special case: cashflow6mo renders grouped income/expense bars.
    if (spec.provider == DataProvider.cashflow6mo) {
      return _cashflowBars(context, cs);
    }
    // Generic single-series bar.
    final field = spec.series.isNotEmpty ? spec.series.first.field : 'total';
    final labelField =
        spec.series.isNotEmpty ? (spec.series.first.labelField ?? 'name') : 'name';
    final colorField =
        spec.series.isNotEmpty ? spec.series.first.colorField : null;
    final maxY = dataset.rows.fold<double>(0, (m, r) => max(m, _d(r, field)));
    final yMax = maxY > 0 ? maxY * 1.15 : 1000.0;
    final colors = dataset.rows
        .map((r) => colorField != null
            ? hexToColor(_s(r, colorField), fallback: cs.primary)
            : cs.primary)
        .toList();
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: yMax,
          barGroups: dataset.rows.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: _d(e.value, field),
                  color: colors[e.key],
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3)),
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
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= dataset.rows.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_s(dataset.rows[i], labelField),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10, color: cs.onSurfaceVariant)),
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

  Widget _cashflowBars(BuildContext context, ColorScheme cs) {
    final maxY = dataset.rows
        .expand((m) => [_d(m, 'income'), _d(m, 'expense')])
        .fold<double>(0, max);
    final yMax = maxY > 0 ? maxY * 1.15 : 1000.0;
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: yMax,
              barGroups: dataset.rows.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barsSpace: 2,
                  barRods: [
                    BarChartRodData(
                        toY: _d(e.value, 'income'),
                        color: _incomeColor,
                        width: 8,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3))),
                    BarChartRodData(
                        toY: _d(e.value, 'expense'),
                        color: _expenseColor,
                        width: 8,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3))),
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
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (value, _) {
                      final i = value.toInt();
                      if (i < 0 || i >= dataset.rows.length) {
                        return const SizedBox.shrink();
                      }
                      final m = dataset.rows[i];
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                            _monthNames[(_i(m, 'month') - 1) % 12],
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: cs.onSurfaceVariant)),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                horizontalInterval: yMax / 4,
                getDrawingHorizontalLine: (v) => FlLine(
                    color: cs.outlineVariant.withAlpha(50),
                    strokeWidth: 1),
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _legendDot(cs, _incomeColor, 'Income'),
            const SizedBox(width: 16),
            _legendDot(cs, _expenseColor, 'Expense'),
          ],
        ),
      ],
    );
  }

  // ── line ─────────────────────────────────────────────────────────────────
  Widget _line(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Default: cashflow6mo → plot net over months.
    final series = spec.series.isNotEmpty
        ? spec.series
        : [const ChartSeries(field: 'net', name: 'Net')];
    final palette = [
      cs.primary,
      _incomeColor,
      _expenseColor,
      Colors.amber,
      Colors.purple,
    ];
    final maxY = dataset.rows.fold<double>(0, (m, r) {
      return series.fold<double>(
          m, (acc, s) => max(acc, _d(r, s.field).abs()));
    });
    final yMax = maxY > 0 ? maxY * 1.15 : 1000.0;
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: yMax,
          lineBarsData: series.asMap().entries.map((se) {
            final color = palette[se.key % palette.length];
            return LineChartBarData(
              isCurved: true,
              color: color,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
              spots: dataset.rows.asMap().entries.map((re) {
                return FlSpot(
                    re.key.toDouble(), _d(re.value, se.value.field));
              }).toList(),
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
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= dataset.rows.length) {
                    return const SizedBox.shrink();
                  }
                  final m = dataset.rows[i];
                  final label = _i(m, 'month') > 0
                      ? _monthNames[(_i(m, 'month') - 1) % 12]
                      : (i + 1).toString();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(label,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10, color: cs.onSurfaceVariant)),
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

  // ── progress ─────────────────────────────────────────────────────────────
  Widget _progress(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final r in dataset.rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_s(r, 'name'),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          Text(
                            '${fmtMoney(_d(r, 'spent'))} / ${fmtMoney(_d(r, 'effective'))}'
                            '${_b(r, 'isOver') ? '  • over' : ''}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: _d(r, 'fraction').clamp(0.0, 1.0),
                        minHeight: 6,
                        color: _b(r, 'isOver') ? _expenseColor : cs.primary,
                        backgroundColor: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── list ─────────────────────────────────────────────────────────────────
  Widget _list(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final field = spec.series.isNotEmpty ? spec.series.first.field : 'total';
    final labelField = spec.series.isNotEmpty
        ? (spec.series.first.labelField ?? 'name')
        : 'name';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in dataset.rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                if (_s(r, 'icon').isNotEmpty) ...[
                  Text(_s(r, 'icon'), style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(_s(r, labelField),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                ),
                Text(fmtMoney(_d(r, field)),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
      ],
    );
  }

  // ── stat ─────────────────────────────────────────────────────────────────
  Widget _stat(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final field = spec.series.isNotEmpty ? spec.series.first.field : 'net';
    final row = dataset.rows.first;
    final value = _d(row, field);
    final color = value < 0 ? _expenseColor : _incomeColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fmtMoney(value),
            style: GoogleFonts.plusJakartaSans(
                fontSize: 28, fontWeight: FontWeight.w800, color: color)),
        if (spec.caption != null) ...[
          const SizedBox(height: 4),
          Text(spec.caption!,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ],
    );
  }

  // ── row accessors (tolerant of missing / wrong-typed cells) ──────────────
  double _d(Map<String, Object?> r, String key) {
    final v = r[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  int _i(Map<String, Object?> r, String key) {
    final v = r[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  String _s(Map<String, Object?> r, String key) {
    final v = r[key];
    return v?.toString() ?? '';
  }

  bool _b(Map<String, Object?> r, String key) {
    final v = r[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    return false;
  }

  Widget _legendDot(ColorScheme cs, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

Widget _empty(BuildContext context, String message) {
  final cs = Theme.of(context).colorScheme;
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