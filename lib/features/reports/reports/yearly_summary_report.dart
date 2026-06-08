import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/report_models.dart';
import '../../../state/reports_providers.dart';
import '../widgets/insight_card.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class YearlySummaryReport extends ConsumerStatefulWidget {
  const YearlySummaryReport({super.key, required this.year});
  final int year;

  @override
  ConsumerState<YearlySummaryReport> createState() => _YearlySummaryReportState();
}

class _YearlySummaryReportState extends ConsumerState<YearlySummaryReport> {
  late int _currentYear;

  @override
  void initState() {
    super.initState();
    _currentYear = widget.year;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(monthlyTotalsProvider(_currentYear));
    
    final fromIso = DateTime(_currentYear, 1, 1).toIso8601String();
    final toIso = DateTime(_currentYear + 1, 1, 1).toIso8601String();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => setState(() => _currentYear--),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Yearly Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text('$_currentYear', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _currentYear < DateTime.now().year
                  ? () => setState(() => _currentYear++)
                  : null,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (months) {
          final totalIncome = months.fold<double>(0, (s, m) => s + m.income);
          final totalExpense = months.fold<double>(0, (s, m) => s + m.expense);

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Year totals hero
                    Row(
                      children: [
                        _YearCard(label: 'Total Income', amount: totalIncome, color: const Color(0xFF16A34A)),
                        const SizedBox(width: 12),
                        _YearCard(label: 'Total Expense', amount: totalExpense, color: const Color(0xFFDC2626)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _NetGainCard(net: totalIncome - totalExpense),
                    const SizedBox(height: 48),

                    _SectionHeader('INCOME VS EXPENSE', cs),
                    _IncomeExpenseBars(months: months),
                    const SizedBox(height: 48),

                    _SectionHeader('NET SAVINGS TREND', cs),
                    _SavingsTrendBars(months: months),
                    const SizedBox(height: 48),

                    _SectionHeader('CUMULATIVE WEALTH GROWTH', cs),
                    _WealthGrowthArea(months: months),
                    const SizedBox(height: 48),

                    _SectionHeader('YEARLY CATEGORY BREAKDOWN', cs),
                    _YearCategoryChart(fromIso: fromIso, toIso: toIso),
                    const SizedBox(height: 48),

                    _SectionHeader('TOP SPENDS OF THE YEAR', cs),
                    _YearTopSpends(fromIso: fromIso, toIso: toIso),
                    const SizedBox(height: 48),
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
        style: GoogleFonts.inter(
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
            'Net Gain: $prefix₹${_fmt(net.abs())}', 
            style: GoogleFonts.manrope(
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

class _YearCard extends StatelessWidget {
  const _YearCard({required this.label, required this.amount, required this.color});
  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '₹${_fmt(amount)}',
                style: GoogleFonts.manrope(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Graphical Widgets ────────────────────────────────────────────────────────

class _IncomeExpenseBars extends StatelessWidget {
  const _IncomeExpenseBars({required this.months});
  final List<MonthTotal> months;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxY = months.expand((m) => [m.income, m.expense]).fold<double>(0, (a, b) => a > b ? a : b);
    final yMax = maxY > 0 ? maxY * 1.15 : 1000.0;
    
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              maxY: yMax,
              barGroups: months.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barsSpace: 2,
                  barRods: [
                    BarChartRodData(toY: e.value.income, color: const Color(0xFF16A34A), width: 6, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                    BarChartRodData(toY: e.value.expense, color: const Color(0xFFDC2626), width: 6, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                  ],
                );
              }).toList(),
              titlesData: _flTitles(months, cs, showLeft: true),
              gridData: FlGridData(
                horizontalInterval: yMax / 4,
                getDrawingHorizontalLine: (v) => FlLine(color: cs.outlineVariant.withAlpha(60), strokeWidth: 1),
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        if (months.isNotEmpty) ...[
          () {
            MonthTotal? bestMonth;
            MonthTotal? worstMonth;
            int positiveMonths = 0;
            for (final m in months) {
              if (m.income > m.expense) positiveMonths++;
              if (bestMonth == null || m.income > bestMonth.income) bestMonth = m;
              if (worstMonth == null || m.expense > worstMonth.expense) worstMonth = m;
            }
            String insight = 'Your highest income was recorded in ${_months[bestMonth!.month - 1]} (₹${_fmt(bestMonth.income)}), while your expenses peaked in ${_months[worstMonth!.month - 1]} (₹${_fmt(worstMonth.expense)}). ';
            insight += 'You had $positiveMonths months where income exceeded expenses, indicating a ${positiveMonths >= 6 ? 'stable' : 'volatile'} financial year.';
            return InsightCard(text: insight);
          }(),
        ],
      ],
    );
  }
}

class _SavingsTrendBars extends StatelessWidget {
  const _SavingsTrendBars({required this.months});
  final List<MonthTotal> months;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    final rates = months.map((m) => m.income > 0 ? ((m.income - m.expense) / m.income * 100) : 0.0).toList();
    double minRate = rates.isEmpty ? 0 : rates.reduce((a, b) => a < b ? a : b);
    double maxRate = rates.isEmpty ? 100 : rates.reduce((a, b) => a > b ? a : b);
    
    // Add visual headroom
    if (minRate > -20) minRate = -20;
    if (maxRate < 100) maxRate = 100;
    
    // Round to nearest 50
    minRate = (minRate / 50).floor() * 50.0;
    maxRate = (maxRate / 50).ceil() * 50.0;

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              minY: minRate,
              maxY: maxRate,
              barGroups: rates.asMap().entries.map((e) {
                final rate = e.value;
                final isPositive = rate >= 0;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: rate,
                      color: isPositive ? const Color(0xFF3B82F6) : const Color(0xFFDC2626),
                      width: 8,
                      borderRadius: isPositive 
                          ? const BorderRadius.vertical(top: Radius.circular(3))
                          : const BorderRadius.vertical(bottom: Radius.circular(3)),
                    ),
                  ],
                );
              }).toList(),
              titlesData: _flTitles(months, cs, showLeft: true, leftSuffix: '%'),
              gridData: FlGridData(
                horizontalInterval: 50,
                getDrawingHorizontalLine: (v) => FlLine(color: v == 0 ? cs.onSurface.withAlpha(100) : cs.outlineVariant.withAlpha(60), strokeWidth: 1),
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        if (months.isNotEmpty) ...[
          () {
            final totalInc = months.fold<double>(0, (s, m) => s + m.income);
            final totalExp = months.fold<double>(0, (s, m) => s + m.expense);
            final avgRate = totalInc > 0 ? ((totalInc - totalExp) / totalInc) * 100 : 0.0;
            
            double bestRate = -double.infinity;
            int bestIndex = -1;
            for (int i = 0; i < rates.length; i++) {
              if (rates[i] > bestRate) {
                bestRate = rates[i];
                bestIndex = i;
              }
            }
            
            String insight = 'You saved an overall average of ${avgRate.toStringAsFixed(0)}% of your income this year. ';
            if (bestIndex >= 0 && bestRate > 0) {
              final bestName = _months[months[bestIndex].month - 1];
              insight += 'You were exceptionally frugal in $bestName, achieving a peak savings rate of ${bestRate.toStringAsFixed(0)}%.';
            } else if (avgRate < 0) {
              insight = 'You overspent by an overall average of ${avgRate.abs().toStringAsFixed(0)}% compared to your income this year.';
            }
            return InsightCard(text: insight);
          }(),
        ],
      ],
    );
  }
}

class _WealthGrowthArea extends StatelessWidget {
  const _WealthGrowthArea({required this.months});
  final List<MonthTotal> months;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    double runningTotal = 0;
    final spots = months.asMap().entries.map((e) {
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
              titlesData: _flTitles(months, cs, showLeft: true),
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
        if (months.isNotEmpty) ...[
          () {
            final totalGain = runningTotal;
            double maxJump = 0;
            int maxJumpIdx = -1;
            for (int i = 0; i < months.length; i++) {
              final diff = months[i].income - months[i].expense;
              if (diff > maxJump) {
                maxJump = diff;
                maxJumpIdx = i;
              }
            }
            
            String insight = 'Your net wealth ${totalGain >= 0 ? 'grew' : 'decreased'} by a total of ₹${_fmt(totalGain.abs())} over the course of the year. ';
            if (maxJumpIdx >= 0 && maxJump > 0) {
              final mName = _months[months[maxJumpIdx].month - 1];
              insight += 'The sharpest increase occurred during $mName, adding ₹${_fmt(maxJump)} to your wealth in a single month.';
            }
            return InsightCard(text: insight);
          }(),
        ],
      ],
    );
  }
}

class _YearCategoryChart extends ConsumerWidget {
  const _YearCategoryChart({required this.fromIso, required this.toIso});
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
              () {
                final top1 = cats[0];
                final top1Pct = ((top1.total / total) * 100).toStringAsFixed(0);
                if (cats.length == 1) {
                  return InsightCard(text: 'Your entire spending this year went to ${top1.name} (100%).');
                }
                final top2 = cats[1];
                final top2Pct = ((top2.total / total) * 100).toStringAsFixed(0);
                final top3Total = cats.take(3).fold<double>(0, (s, c) => s + c.total);
                final top3Pct = ((top3Total / total) * 100).toStringAsFixed(0);
                
                String insight = 'Over the entire year, your biggest expense was ${top1.name} ($top1Pct%), followed closely by ${top2.name} ($top2Pct%). ';
                if (cats.length >= 3) {
                  insight += 'Your top 3 categories consumed $top3Pct% of your annual budget.';
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

class _YearTopSpends extends ConsumerWidget {
  const _YearTopSpends({required this.fromIso, required this.toIso});
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
                        Text(tx.note.isEmpty ? 'Expense' : tx.note, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(value: fraction, backgroundColor: cs.outlineVariant, color: cs.primary, minHeight: 4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('₹${_fmt(tx.amount)}', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

FlTitlesData _flTitles(List<MonthTotal> months, ColorScheme cs, {bool showLeft = false, String leftSuffix = ''}) {
  const abbr = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
  return FlTitlesData(
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        getTitlesWidget: (v, meta) {
          final idx = v.toInt();
          if (idx < 0 || idx >= months.length) return const SizedBox.shrink();
          return Text(abbr[months[idx].month - 1], style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant));
        },
      ),
    ),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: showLeft,
        reservedSize: 36,
        getTitlesWidget: (v, meta) => Text('${_short(v)}$leftSuffix', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
      ),
    ),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );
}

String _short(double v) {
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
  return v.toInt().toString();
}

String _fmt(double v) {
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
