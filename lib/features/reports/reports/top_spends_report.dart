import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/reports_providers.dart';
import '../../../utils/color_utils.dart';
import '../widgets/insight_card.dart';
import '../widgets/report_period_app_bar.dart';

// Expenses-only report — the accent color for rank avatars, progress bars and
// amounts is the explicit red (0xFFDC2626). cs.error is monochrome in this app
// (black in light mode), so using it here rendered the amounts as plain text.
const _expenseColor = Color(0xFFDC2626);

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

    return Scaffold(
      appBar: ReportPeriodAppBar(
        title: 'Top Categories',
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
              child: Text('No expenses in $monthLabel',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
            );
          }
          final maxTotal = cats.first.total;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: InsightCard(
                  text: 'Your top expense category this month is ${cats.first.name} (₹${_fmt(cats.first.total)}). Reviewing top categories helps you identify spending patterns and adjust your budget.',
                ),
              ),
              ...cats.asMap().entries.map((e) {
                final i = e.key;
                final cat = e.value;
                final fraction =
                    maxTotal > 0 ? (cat.total / maxTotal).clamp(0.0, 1.0) : 0.0;
                final catColor = hexToColor(cat.color);
                // For the progress bar, use the category's color to show which
                // category contributes most; for rank avatar, use the expense
                // color so all rows have a consistent "expense" visual language.
                final rankAvatarColor = i < 3
                    ? const Color(0xFFDC2626)
                    : catColor;
                return Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: rankAvatarColor.withValues(alpha: 0.15),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                              color: rankAvatarColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                      title: Text(
                          cat.name,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_fmt(cat.total)} total',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: fraction,
                            minHeight: 3,
                            color: catColor,
                            backgroundColor: catColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                      trailing: Text(
                        '₹${_fmt(cat.total)}',
                        style: const TextStyle(
                            color: _expenseColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      isThreeLine: true,
                    ),
                    if (i < cats.length - 1)
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
