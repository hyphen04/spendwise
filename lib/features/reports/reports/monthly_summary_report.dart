import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/report_models.dart';
import '../../../state/reports_providers.dart';
import '../widgets/insight_card.dart';
import '../widgets/report_period_app_bar.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

class MonthlySummaryReport extends ConsumerStatefulWidget {
  const MonthlySummaryReport({super.key, required this.year, required this.month});
  final int year;
  final int month;

  @override
  ConsumerState<MonthlySummaryReport> createState() => _MonthlySummaryReportState();
}

class _MonthlySummaryReportState extends ConsumerState<MonthlySummaryReport> {
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
    final asyncSummary = ref.watch(monthlySummaryProvider((_currentYear, _currentMonth)));
    final asyncDaily = ref.watch(dailyTotalsProvider((_currentYear, _currentMonth)));

    final fromIso = DateTime(_currentYear, _currentMonth).toIso8601String();
    final toIso = DateTime(_currentYear, _currentMonth + 1).toIso8601String();

    final now = DateTime.now();
    final isCurrentOrFuture = _currentYear > now.year || (_currentYear == now.year && _currentMonth >= now.month);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ReportPeriodAppBar(
        title: 'Monthly Overview',
        subtitle: '${_months[_currentMonth - 1]} $_currentYear',
        onPrevious: _previousMonth,
        onNext: _nextMonth,
        disableNext: isCurrentOrFuture,
      ),
      body: asyncSummary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (summary) {
          final isEmpty = summary.income == 0 && summary.expense == 0;

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _BalanceFlowCard(
                      opening: summary.openingBalance,
                      closing: summary.closingBalance,
                      income: summary.income,
                      expense: summary.expense,
                    ),
                    const SizedBox(height: 12),
                    _NetGainCard(net: summary.net),
                    const SizedBox(height: 48),

                    if (isEmpty)
                      Center(
                        child: Text(
                          'No financial activity in ${_months[_currentMonth - 1]}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                        ),
                      )
                    else ...[
                      asyncDaily.when(
                        loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                        error: (_, __) => const SizedBox(),
                        data: (days) => Column(
                          children: [
                            _SectionHeader('DAILY INCOME VS EXPENSE', cs),
                            _DailyIncomeExpenseBars(days: days, currentMonth: _currentMonth),
                            const SizedBox(height: 48),

                            _SectionHeader('CUMULATIVE WEALTH GROWTH', cs),
                            _DailyWealthGrowthArea(days: days, currentMonth: _currentMonth),
                            const SizedBox(height: 48),
                          ],
                        ),
                      ),
                      
                      _SectionHeader('EXPENSES BY CATEGORY', cs),
                      _MonthCategoryChart(fromIso: fromIso, toIso: toIso),
                      const SizedBox(height: 48),

                      _SectionHeader('TOP SPENDS THIS MONTH', cs),
                      _MonthTopSpends(fromIso: fromIso, toIso: toIso),
                      const SizedBox(height: 48),
                    ],
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.cs);
  final String title;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NetGainCard extends StatelessWidget {
  const _NetGainCard({required this.net});
  final double net;

  @override
  Widget build(BuildContext context) {
    final isPositive = net >= 0;
    final color = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final prefix = net > 0 ? '+' : (net < 0 ? '−' : '');
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded, 
               size: 20, 
               color: color),
          const SizedBox(width: 8),
          Text(
            'Net Savings: $prefix₹${_fmtAmt(net.abs())}', 
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, 
              fontSize: 15, 
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceFlowCard extends StatelessWidget {
  const _BalanceFlowCard({
    required this.opening,
    required this.closing,
    required this.income,
    required this.expense,
  });
  final double opening;
  final double closing;
  final double income;
  final double expense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _FlowRow(label: 'Opening Balance', amount: opening, color: cs.onSurfaceVariant),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          _FlowRow(label: 'Income', amount: income, color: const Color(0xFF16A34A), prefix: '+ '),
          const SizedBox(height: 12),
          _FlowRow(label: 'Expense', amount: expense, color: const Color(0xFFDC2626), prefix: '- '),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          _FlowRow(label: 'Closing Balance', amount: closing, color: cs.onSurface, isBold: true),
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.label, 
    required this.amount, 
    required this.color,
    this.prefix = '',
    this.isBold = false,
  });
  final String label;
  final double amount;
  final Color color;
  final String prefix;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: color,
            fontSize: isBold ? 15 : 14,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        Text(
          '$prefix₹${_fmtAmt(amount)}',
          style: GoogleFonts.plusJakartaSans(
            color: color,
            fontSize: isBold ? 16 : 15,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _DailyIncomeExpenseBars extends StatelessWidget {
  const _DailyIncomeExpenseBars({required this.days, required this.currentMonth});
  final List<DayTotal> days;
  final int currentMonth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxY = days.expand((m) => [m.income, m.expense]).fold<double>(0, (a, b) => a > b ? a : b);
    final yMax = maxY > 0 ? maxY * 1.15 : 1000.0;
    
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              maxY: yMax,
              barGroups: days.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barsSpace: 1,
                  barRods: [
                    BarChartRodData(toY: e.value.income, color: const Color(0xFF16A34A), width: 3, borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
                    BarChartRodData(toY: e.value.expense, color: const Color(0xFFDC2626), width: 3, borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
                  ],
                );
              }).toList(),
              titlesData: _flTitlesDays(days, cs, showLeft: true),
              gridData: FlGridData(
                horizontalInterval: yMax / 4,
                getDrawingHorizontalLine: (v) => FlLine(color: cs.outlineVariant.withAlpha(60), strokeWidth: 1),
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        if (days.isNotEmpty) ...[
          () {
            DayTotal? bestDay;
            DayTotal? worstDay;
            int positiveDays = 0;
            for (final d in days) {
              if (d.income > d.expense) positiveDays++;
              if (bestDay == null || d.income > bestDay.income) bestDay = d;
              if (worstDay == null || d.expense > worstDay.expense) worstDay = d;
            }
            if (bestDay?.income == 0 && worstDay?.expense == 0) return const SizedBox();
            
            String insight = '';
            if (bestDay != null && bestDay.income > 0) insight += 'You had the highest income on ${_months[currentMonth - 1]} ${bestDay.day} (₹${_fmtAmt(bestDay.income)}). ';
            if (worstDay != null && worstDay.expense > 0) insight += 'Your expenses peaked on ${_months[currentMonth - 1]} ${worstDay.day} (₹${_fmtAmt(worstDay.expense)}). ';
            insight += 'You had $positiveDays days where income exceeded expenses.';
            return InsightCard(text: insight.trim());
          }(),
        ],
      ],
    );
  }
}

class _DailyWealthGrowthArea extends StatelessWidget {
  const _DailyWealthGrowthArea({required this.days, required this.currentMonth});
  final List<DayTotal> days;
  final int currentMonth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    double runningTotal = 0;
    final spots = days.asMap().entries.map((e) {
      runningTotal += (e.value.income - e.value.expense);
      return FlSpot(e.key.toDouble(), runningTotal);
    }).toList();

    final maxVal = spots.map((s) => s.y).fold<double>(0, (a, b) => a > b ? a : b);
    final minVal = spots.map((s) => s.y).fold<double>(0, (a, b) => a < b ? a : b);
    final yMax = maxVal > 0 ? maxVal * 1.2 : 1000.0;
    final yRange = (yMax - minVal).abs() > 0 ? (yMax - minVal).abs() : 1000.0;
    final yMin = minVal - (yRange * 0.1);

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              clipData: const FlClipData.all(),
              minY: yMin,
              maxY: yMax,
              titlesData: _flTitlesDays(days, cs, showLeft: true),
              gridData: FlGridData(
                getDrawingHorizontalLine: (v) => FlLine(color: v == 0 ? cs.onSurface.withAlpha(100) : cs.outlineVariant.withAlpha(60), strokeWidth: 1),
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  color: const Color(0xFF10B981),
                  barWidth: 3,
                  isCurved: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (days.isNotEmpty) ...[
          () {
            final totalGain = runningTotal;
            double maxJump = 0;
            int maxJumpIdx = -1;
            for (int i = 0; i < days.length; i++) {
              final diff = days[i].income - days[i].expense;
              if (diff > maxJump) {
                maxJump = diff;
                maxJumpIdx = i;
              }
            }
            if (totalGain == 0 && maxJump == 0) return const SizedBox();
            
            String insight = 'Your net wealth ${totalGain >= 0 ? 'grew' : 'decreased'} by a total of ₹${_fmtAmt(totalGain.abs())} over this month. ';
            if (maxJumpIdx >= 0 && maxJump > 0) {
              final dDay = days[maxJumpIdx].day;
              insight += 'The sharpest increase occurred on ${_months[currentMonth - 1]} $dDay, adding ₹${_fmtAmt(maxJump)} to your wealth in a single day.';
            }
            return InsightCard(text: insight);
          }(),
        ],
      ],
    );
  }
}

FlTitlesData _flTitlesDays(List<DayTotal> days, ColorScheme cs, {bool showLeft = false}) {
  return FlTitlesData(
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: 5, // Show label every 5 days
        getTitlesWidget: (v, meta) {
          final idx = v.toInt();
          if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
          
          final isFirst = idx == 0;
          final isLast = idx == days.length - 1;
          final isDiv5 = days[idx].day % 5 == 0;

          // Always show first and last
          if (isFirst || isLast) {
            return Text('${days[idx].day}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant));
          }
          
          // Show every 5th day, but skip if it's too close to the last day (like 30 right next to 31)
          if (isDiv5) {
            final daysUntilEnd = days.length - 1 - idx;
            if (daysUntilEnd <= 2) return const SizedBox.shrink();
            
            return Text('${days[idx].day}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant));
          }
          
          return const SizedBox.shrink();
        },
      ),
    ),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: showLeft,
        reservedSize: 36,
        getTitlesWidget: (v, meta) {
          String s = '';
          if (v.abs() >= 1000000) {
            s = '${(v / 1000000).toStringAsFixed(1)}M';
          } else if (v.abs() >= 1000) {
            s = '${(v / 1000).toStringAsFixed(0)}K';
          } else {
            s = v.toInt().toString();
          }
          return Text(s, style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant));
        },
      ),
    ),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );
}

class _MonthCategoryChart extends ConsumerWidget {
  const _MonthCategoryChart({required this.fromIso, required this.toIso});
  final String fromIso;
  final String toIso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(categoryBreakdownProvider((fromIso, toIso)));

    return async.when(
      loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox(),
      data: (cats) {
        if (cats.isEmpty) return Center(child: Text('No categorized expenses', style: TextStyle(color: cs.onSurfaceVariant)));
        
        final total = cats.fold<double>(0, (s, c) => s + c.total);
        final palette = _palette(cats.length);

        return Column(
          children: [
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: cats.asMap().entries.map((e) {
                    final pct = total > 0 ? e.value.total / total : 0.0;
                    return PieChartSectionData(
                      value: e.value.total,
                      color: palette[e.key % palette.length],
                      radius: 60,
                      title: pct > 0.05 ? '${(pct * 100).toStringAsFixed(0)}%' : '',
                      titleStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.surface),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: cats.asMap().entries.map((e) {
                final pct = total > 0 ? e.value.total / total : 0.0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: palette[e.key % palette.length], shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${e.value.name} (${(pct * 100).toStringAsFixed(0)}%)', style: TextStyle(fontSize: 12, color: cs.onSurface)),
                  ],
                );
              }).toList(),
            ),
            if (cats.isNotEmpty) ...[
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
                
                String insight = 'Your top spending category was ${top1.name} ($top1Pct%). It was followed by ${top2.name} ($top2Pct%). ';
                if (cats.length >= 3) {
                  insight += 'Together, your top 3 categories accounted for $top3Pct% of all your expenses this month.';
                } else {
                  insight += 'Together, they accounted for $top3Pct% of your expenses.';
                }
                return InsightCard(text: insight);
              }(),
            ],
          ],
        );
      },
    );
  }
}

class _MonthTopSpends extends ConsumerWidget {
  const _MonthTopSpends({required this.fromIso, required this.toIso});
  final String fromIso;
  final String toIso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(topSpendsProvider((fromIso, toIso)));

    return async.when(
      loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox(),
      data: (txs) {
        if (txs.isEmpty) return Center(child: Text('No transactions recorded', style: TextStyle(color: cs.onSurfaceVariant)));
        
        final maxAmt = txs.first.amount;
        return Column(
          children: txs.take(5).map((tx) {
            final fraction = maxAmt > 0 ? (tx.amount / maxAmt).clamp(0.0, 1.0) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tx.note.isEmpty ? 'Expense' : tx.note, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(value: fraction, backgroundColor: cs.outlineVariant, color: cs.primary, minHeight: 4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('₹${_fmtAmt(tx.amount)}', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

String _fmtAmt(double v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

List<Color> _palette(int count) {
  const base = [
    Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444),
    Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF06B6D4), Color(0xFF84CC16),
  ];
  return List.generate(count, (i) => base[i % base.length]);
}
