import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/reports_providers.dart';

class YearlySummaryReport extends ConsumerWidget {
  const YearlySummaryReport({super.key, required this.year});
  final int year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(monthlyTotalsProvider(year));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Yearly Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text('$year', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (months) {
          final totalIncome =
              months.fold<double>(0, (s, m) => s + m.income);
          final totalExpense =
              months.fold<double>(0, (s, m) => s + m.expense);
          final maxY = months
              .expand((m) => [m.income, m.expense])
              .fold<double>(0, (a, b) => a > b ? a : b);
          final yMax = maxY > 0 ? maxY * 1.15 : 1000.0;

          final incomeColor = cs.onSurface;
          final expenseColor = cs.onSurfaceVariant;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Year totals
              Row(
                children: [
                  _YearCard(label: 'Income', amount: totalIncome),
                  const SizedBox(width: 12),
                  _YearCard(label: 'Expense', amount: totalExpense),
                ],
              ),
              const SizedBox(height: 20),
              // Bar chart
              SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    maxY: yMax,
                    barGroups: months.asMap().entries.map((e) {
                      final m = e.value;
                      return BarChartGroupData(
                        x: e.key,
                        barsSpace: 2,
                        barRods: [
                          BarChartRodData(
                              toY: m.income,
                              color: incomeColor,
                              width: 6,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3))),
                          BarChartRodData(
                              toY: m.expense,
                              color: expenseColor,
                              width: 6,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3))),
                        ],
                      );
                    }).toList(),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          getTitlesWidget: (v, meta) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= months.length) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              _monthAbbr[months[idx].month - 1],
                              style: TextStyle(
                                  fontSize: 9,
                                  color: cs.onSurfaceVariant),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          getTitlesWidget: (v, meta) => Text(
                            _short(v),
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
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Dot(color: incomeColor, label: 'Income'),
                  const SizedBox(width: 20),
                  _Dot(color: expenseColor, label: 'Expense'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static const _monthAbbr = [
    'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'
  ];

  static String _short(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toInt().toString();
  }
}

class _YearCard extends StatelessWidget {
  const _YearCard({required this.label, required this.amount});
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              '₹${_fmt(amount)}',
              style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.label});
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
