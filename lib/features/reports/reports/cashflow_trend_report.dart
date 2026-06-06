import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/report_models.dart';
import '../../../state/reports_providers.dart';

class CashflowTrendReport extends ConsumerWidget {
  const CashflowTrendReport({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(cashFlowProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cash Flow Trend')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (months) {
          if (months.isEmpty) {
            return Center(
              child: Text('No data available',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
            );
          }

          final maxY = months
              .expand((m) => [m.income, m.expense])
              .fold<double>(0, (a, b) => a > b ? a : b);
          final yMax = maxY > 0 ? maxY * 1.2 : 1000.0;

          final incomeColor = cs.onSurface;
          final expenseColor = cs.onSurfaceVariant;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Chart
              SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: yMax,
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, meta) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= months.length) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              _monthShort(months[idx].month),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 48,
                          getTitlesWidget: (v, meta) => Text(
                            _shortAmt(v),
                            style: TextStyle(
                                fontSize: 9, color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      horizontalInterval: yMax / 4,
                      getDrawingHorizontalLine: (v) => FlLine(
                          color: cs.outlineVariant.withAlpha(60),
                          strokeWidth: 1),
                      drawVerticalLine: false,
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: months
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key.toDouble(), e.value.income))
                            .toList(),
                        color: incomeColor,
                        barWidth: 2.5,
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: incomeColor.withAlpha(30),
                        ),
                      ),
                      LineChartBarData(
                        spots: months
                            .asMap()
                            .entries
                            .map((e) =>
                                FlSpot(e.key.toDouble(), e.value.expense))
                            .toList(),
                        color: expenseColor,
                        barWidth: 2.5,
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: expenseColor.withAlpha(20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendDot(color: incomeColor, label: 'Income'),
                  const SizedBox(width: 20),
                  _LegendDot(color: expenseColor, label: 'Expense'),
                ],
              ),
              const SizedBox(height: 20),
              // Monthly table
              ...months.map((m) => _MonthRow(month: m)),
            ],
          );
        },
      ),
    );
  }

  static String _monthShort(int m) => const [
        'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'
      ][m - 1];

  static String _shortAmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toInt().toString();
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({required this.month});
  final MonthTotal month;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(months[month.month - 1],
                style: TextStyle(
                    color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('+₹${_fmt(month.income)}',
                    style: TextStyle(color: cs.onSurface, fontSize: 13)),
                Text('−₹${_fmt(month.expense)}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                Text(
                  '${month.net >= 0 ? '+' : '−'}₹${_fmt(month.net.abs())}',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
