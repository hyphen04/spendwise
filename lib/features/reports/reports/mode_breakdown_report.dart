import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/reports_providers.dart';
import '../widgets/insight_card.dart';
import '../widgets/report_period_app_bar.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

class ModeBreakdownReport extends ConsumerStatefulWidget {
  const ModeBreakdownReport({super.key, required this.year, required this.month});
  final int year;
  final int month;

  @override
  ConsumerState<ModeBreakdownReport> createState() => _ModeBreakdownReportState();
}

class _ModeBreakdownReportState extends ConsumerState<ModeBreakdownReport> {
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
    
    final async = ref.watch(modeBreakdownProvider((fromIso, toIso)));

    return Scaffold(
      appBar: ReportPeriodAppBar(
        title: 'Payment Modes',
        subtitle: monthLabel,
        onPrevious: _previousMonth,
        onNext: _nextMonth,
        disableNext: isCurrentOrFuture,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (modes) {
          if (modes.isEmpty) {
            return Center(
              child: Text('No transactions in $monthLabel',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
            );
          }
          final total = modes.fold<double>(0, (s, m) => s + m.total);
          final maxAmt = modes.first.total;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total transactions',
                        style: Theme.of(context).textTheme.bodyMedium),
                    Text('₹${_fmt(total)}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              () {
                final top = modes.first;
                final pct = (top.total / total * 100).toStringAsFixed(0);
                return InsightCard(text: 'You primarily use ${top.name} for your transactions, accounting for $pct% of your total spending. Make sure all your ${top.name} expenses are accurately recorded.');
              }(),
              const SizedBox(height: 20),
              ...modes.map((m) {
                final fraction = maxAmt > 0
                    ? (m.total / maxAmt).clamp(0.0, 1.0)
                    : 0.0;
                final pct = total > 0 ? (m.total / total * 100) : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Text(m.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(m.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                Text(
                                  '₹${_fmt(m.total)}  ${pct.toStringAsFixed(1)}%',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: fraction,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(3),
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
