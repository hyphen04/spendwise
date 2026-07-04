import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/home_providers.dart';
import '../widgets/report_period_app_bar.dart';

class BudgetPerformanceReport extends ConsumerStatefulWidget {
  const BudgetPerformanceReport({
    super.key,
  });

  @override
  ConsumerState<BudgetPerformanceReport> createState() => _BudgetPerformanceReportState();
}

class _BudgetPerformanceReportState extends ConsumerState<BudgetPerformanceReport> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year--;
      } else {
        _month--;
      }
    });
  }

  void _nextMonth() {
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year++;
      } else {
        _month++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(budgetProgressProvider((_year, _month)));
    final monthLabel = '${_months[_month - 1]} $_year';

    return Scaffold(
      appBar: ReportPeriodAppBar(
        title: 'Budget Performance',
        subtitle: monthLabel,
        onPrevious: _prevMonth,
        onNext: _nextMonth,
      ),
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🎯', style: TextStyle(fontSize: 56)),
                        const SizedBox(height: 12),
                        Text('No budgets active for this month',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  );
                }

                final overCount = items.where((i) => i.isOver).length;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Summary banner
                    if (overCount > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_outlined,
                                color: cs.onErrorContainer, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              '$overCount budget${overCount > 1 ? 's' : ''} exceeded',
                              style: TextStyle(
                                  color: cs.onErrorContainer,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ...items.map((p) {
                      final isOver = p.isOver;
                      final color = isOver ? cs.error : cs.primary;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(p.categoryIcon,
                                    style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    p.categoryName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  '₹${_fmt(p.spent)} / ₹${_fmt(p.effectiveAmount)}',
                                  style: TextStyle(
                                      color: isOver ? cs.error : cs.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight: isOver ? FontWeight.w600 : null),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: p.fraction,
                              color: color,
                              backgroundColor: color.withAlpha(24),
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                isOver
                                  ? 'Over by ₹${_fmt(p.spent - p.effectiveAmount)}'
                                  : '₹${_fmt(p.effectiveAmount - p.spent)} remaining',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: color),
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
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
