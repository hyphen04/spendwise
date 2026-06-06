import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A minimal single-line or dual-line chart used on Home and report mini charts.
///
/// Pass [incomeValues] + [expenseValues] together for the green/red dual-series
/// view. Omit both and pass [values] for the legacy monochrome net line.
class SmoothLineChart extends StatelessWidget {
  const SmoothLineChart({
    super.key,
    this.values = const [],
    this.incomeValues,
    this.expenseValues,
    this.height = 120,
    this.highlightIndex,
    this.showFill = true,
  });

  final List<double> values;
  final List<double>? incomeValues;
  final List<double>? expenseValues;
  final double height;
  final int? highlightIndex;
  final bool showFill;

  bool get _isDual =>
      incomeValues != null &&
      expenseValues != null &&
      incomeValues!.isNotEmpty &&
      expenseValues!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isDual) return _buildDual(context);
    return _buildMono(context);
  }

  Widget _buildMono(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final line = cs.onSurface;

    if (values.length < 2) return SizedBox(height: height);

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final span = (maxV - minV).abs();
    final pad = span == 0 ? (maxV.abs() == 0 ? 1.0 : maxV.abs() * 0.2) : span * 0.25;
    final hi = highlightIndex ?? values.length - 1;

    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        minY: minV - pad,
        maxY: maxV + pad,
        minX: 0,
        maxX: (values.length - 1).toDouble(),
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
            isCurved: true,
            curveSmoothness: 0.35,
            color: line,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, _) => spot.x.toInt() == hi,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 5,
                color: cs.surface,
                strokeWidth: 3,
                strokeColor: line,
              ),
            ),
            belowBarData: BarAreaData(
              show: showFill,
              color: line.withValues(alpha: 0.06),
            ),
          ),
        ],
      )),
    );
  }

  Widget _buildDual(BuildContext context) {
    final inc = incomeValues!;
    final exp = expenseValues!;
    final len = inc.length < exp.length ? inc.length : exp.length;
    if (len < 2) return SizedBox(height: height);

    const green = Color(0xFF34C759);
    const red = Color(0xFFFF3B30);

    final allVals = [...inc.take(len), ...exp.take(len)];
    final maxV = allVals.reduce((a, b) => a > b ? a : b);
    final minV = allVals.reduce((a, b) => a < b ? a : b);
    final span = (maxV - minV).abs();
    final pad = span == 0 ? (maxV.abs() == 0 ? 1.0 : maxV.abs() * 0.2) : span * 0.25;
    final hi = highlightIndex ?? len - 1;

    LineChartBarData series(List<double> vals, Color color) => LineChartBarData(
          spots: [for (var i = 0; i < len; i++) FlSpot(i.toDouble(), vals[i])],
          isCurved: true,
          curveSmoothness: 0.35,
          color: color,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, _) => spot.x.toInt() == hi,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 4,
              color: Theme.of(context).colorScheme.surface,
              strokeWidth: 2.5,
              strokeColor: color,
            ),
          ),
          belowBarData: BarAreaData(
            show: showFill,
            color: color.withValues(alpha: 0.08),
          ),
        );

    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        minY: minV - pad,
        maxY: maxV + pad,
        minX: 0,
        maxX: (len - 1).toDouble(),
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          series(inc.take(len).toList(), green),
          series(exp.take(len).toList(), red),
        ],
      )),
    );
  }
}
