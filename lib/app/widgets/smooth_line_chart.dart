import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A minimal, monochrome single-line chart: one smooth curved black line with
/// a single highlighted node dot and no axes/grid — matching the reference
/// "mibu" home chart. Used on Home and as the reports mini chart.
class SmoothLineChart extends StatelessWidget {
  const SmoothLineChart({
    super.key,
    required this.values,
    this.height = 120,
    this.highlightIndex,
    this.showFill = true,
  });

  /// Y values, evenly spaced along X. Needs at least 2 points to draw.
  final List<double> values;
  final double height;

  /// Which point gets the visible node dot. Defaults to the last point.
  final int? highlightIndex;
  final bool showFill;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final line = cs.onSurface;

    if (values.length < 2) {
      return SizedBox(height: height);
    }

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final span = (maxV - minV).abs();
    // Pad the range so the curve doesn't touch the top/bottom edges.
    final pad = span == 0 ? (maxV.abs() == 0 ? 1.0 : maxV.abs() * 0.2) : span * 0.25;
    final hi = highlightIndex ?? values.length - 1;

    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
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
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: line,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, _) => spot.x.toInt() == hi,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
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
        ),
      ),
    );
  }
}
