import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/reports_providers.dart';
import '../../../utils/color_utils.dart';
import '../widgets/insight_card.dart';
import '../widgets/report_period_app_bar.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

class CategoryDrilldownReport extends ConsumerStatefulWidget {
  const CategoryDrilldownReport({super.key, required this.year, required this.month});
  final int year;
  final int month;

  @override
  ConsumerState<CategoryDrilldownReport> createState() => _CategoryDrilldownReportState();
}

class _CategoryDrilldownReportState extends ConsumerState<CategoryDrilldownReport> {
  late int _currentYear;
  late int _currentMonth;

  @override
  void initState() {
    super.initState();
    _currentYear = widget.year;
    _currentMonth = widget.month;
  }

  void _previousMonth() {
    setState(() {
      if (_currentMonth == 1) {
        _currentMonth = 12;
        _currentYear--;
      } else {
        _currentMonth--;
      }
    });
  }

  void _nextMonth() {
    setState(() {
      if (_currentMonth == 12) {
        _currentMonth = 1;
        _currentYear++;
      } else {
        _currentMonth++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    final fromIso = DateTime(_currentYear, _currentMonth).toIso8601String();
    final toIso = DateTime(_currentYear, _currentMonth + 1).toIso8601String();
    final monthLabel = '${_months[_currentMonth - 1]} $_currentYear';
    
    final now = DateTime.now();
    final isCurrentOrFuture = _currentYear > now.year || (_currentYear == now.year && _currentMonth >= now.month);
    
    final async = ref.watch(categoryBreakdownProvider((fromIso, toIso)));

    return Scaffold(
      appBar: ReportPeriodAppBar(
        title: 'Category Breakdown',
        subtitle: monthLabel,
        onPrevious: _previousMonth,
        onNext: _nextMonth,
        disableNext: isCurrentOrFuture,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cats) {
          if (cats.isEmpty) {
            return Center(
              child: Text('No expense categories in $monthLabel',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
            );
          }
          final total = cats.fold<double>(0, (s, c) => s + c.total);
          // Resolve each category's stored color (#RRGGBB) into a Flutter
          // Color once; reused by the pie, the legend swatches and the
          // progress bars so they all agree. Falls back to a neutral slate
          // when a category has no color set.
          final colors = cats.map((c) => hexToColor(c.color)).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Pie chart
              SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(
                    sections: cats.asMap().entries.map((e) {
                      final pct = total > 0 ? e.value.total / total : 0.0;
                      return PieChartSectionData(
                        value: e.value.total,
                        color: colors[e.key],
                        radius: 60,
                        title: pct > 0.05
                            ? '${(pct * 100).toStringAsFixed(0)}%'
                            : '',
                        titleStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.surface),
                      );
                    }).toList(),
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              () {
                final top1 = cats[0];
                final top1Pct = ((top1.total / total) * 100).toStringAsFixed(0);
                if (cats.length == 1) {
                  return InsightCard(text: 'Your entire spending this month went to ${top1.name} (100%).');
                }
                final top2 = cats[1];
                final top2Pct = ((top2.total / total) * 100).toStringAsFixed(0);
                final top3Total = cats.take(3).fold<double>(0, (s, c) => s + c.total);
                final top3Pct = ((top3Total / total) * 100).toStringAsFixed(0);
                
                String insight = 'Your top spending category is ${top1.name} ($top1Pct%). It was followed by ${top2.name} ($top2Pct%). ';
                if (cats.length >= 3) {
                  insight += 'Together, your top 3 categories account for $top3Pct% of all your expenses this month. Consider setting a budget for ${top1.name} if you want to save more.';
                } else {
                  insight += 'Together, they account for $top3Pct% of your expenses.';
                }
                return InsightCard(text: insight);
              }(),
              const SizedBox(height: 24),
              // Ranked list
              ...cats.asMap().entries.map((e) {
                final cat = e.value;
                final pct = total > 0 ? cat.total / total : 0.0;
                final color = colors[e.key];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(cat.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(cat.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                Text(
                                  '₹${_fmt(cat.total)}  ${(pct * 100).toStringAsFixed(1)}%',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: pct,
                              minHeight: 4,
                              color: color,
                              backgroundColor: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
