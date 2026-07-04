import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/manage_providers.dart';
import '../../../state/reports_providers.dart';
import '../widgets/insight_card.dart';
import '../widgets/report_period_app_bar.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

class TopSpendsReport extends ConsumerStatefulWidget {
  const TopSpendsReport({super.key, required this.year, required this.month});
  final int year;
  final int month;

  @override
  ConsumerState<TopSpendsReport> createState() => _TopSpendsReportState();
}

class _TopSpendsReportState extends ConsumerState<TopSpendsReport> {
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
    
    final async = ref.watch(topSpendsProvider((fromIso, toIso)));
    final catMap = {
      for (final c in ref.watch(categoriesStreamProvider).valueOrNull ?? [])
        c.id: c.name
    };

    return Scaffold(
      appBar: ReportPeriodAppBar(
        title: 'Top Spends',
        subtitle: monthLabel,
        onPrevious: _previousMonth,
        onNext: _nextMonth,
        disableNext: isCurrentOrFuture,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (txs) {
          if (txs.isEmpty) {
            return Center(
              child: Text('No expenses in $monthLabel',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
            );
          }
          final maxAmt = txs.first.amount;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: InsightCard(
                  text: 'Your largest expense this month was ₹${_fmt(txs.first.amount)} on ${catMap[txs.first.categoryId] ?? 'Expense'}. Tracking large expenses helps you stick to your budget.',
                ),
              ),
              ...txs.asMap().entries.map((e) {
                final i = e.key;
                final tx = e.value;
                final fraction =
                    maxAmt > 0 ? (tx.amount / maxAmt).clamp(0.0, 1.0) : 0.0;
                return Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.errorContainer,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                              color: cs.onErrorContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                      title: Text(
                          catMap[tx.categoryId] ?? 'Expense',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tx.note.isNotEmpty)
                            Text(
                              tx.note,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            tx.transactionDate.substring(0, 10),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: fraction,
                            minHeight: 3,
                            color: cs.error,
                            backgroundColor: cs.error.withAlpha(20),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                      trailing: Text(
                        '₹${_fmt(tx.amount)}',
                        style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      isThreeLine: true,
                    ),
                    if (i < txs.length - 1)
                      const Divider(height: 1, indent: 56),
                  ],
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
