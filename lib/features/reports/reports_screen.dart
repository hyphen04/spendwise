import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/widgets/screen_header.dart';
import '../../state/period_providers.dart';
import '../../state/reports_providers.dart';
import '../home/widgets/month_nav.dart';

import '../../data/models/report_models.dart';
import 'reports/account_statement_report.dart';
import 'reports/budget_performance_report.dart';
import 'reports/yearly_summary_report.dart';
import 'widgets/insight_card.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    final period = ref.watch(selectedPeriodProvider);
    final year = period.year;
    final month = period.month;

    final summary =
        ref.watch(monthlySummaryProvider((year, month))).valueOrNull;

    final fromIso = DateTime(year, month).toIso8601String();
    final toIso = DateTime(year, month + 1).toIso8601String();
    final monthLabel = '${_months[month - 1]} $year';

    final isEmpty = summary == null || (summary.income == 0 && summary.expense == 0);

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── Header ───────────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'reports',
              subtitle: 'Insights & summaries',
              actions: [
                MonthNav(),
              ],
            ),
          ),



          // ── Period hero (At a Glance) ────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Row(
                children: [
                  Expanded(
                    child: _FlatStatCard(
                      label: 'Income',
                      amount: summary?.income ?? 0,
                      color: const Color(0xFF16A34A),
                      icon: Icons.arrow_downward_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FlatStatCard(
                      label: 'Expense',
                      amount: summary?.expense ?? 0,
                      color: const Color(0xFFDC2626),
                      icon: Icons.arrow_upward_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 48, bottom: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No financial activity',
                      style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'There are no transactions recorded in $monthLabel.',
                      style: GoogleFonts.inter(
                          fontSize: 14, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),
                    FilledButton.tonalIcon(
                      onPressed: () => _push(context, YearlySummaryReport(year: year)),
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: const Text('View Yearly Overview'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // ── Inline Charts ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _SectionHeader('EXPENSES BY CATEGORY', cs),
                  _InlineCategoryChart(from: fromIso, to: toIso),
                  const SizedBox(height: 32),

                  _SectionHeader('CASH FLOW TREND (6 MONTHS)', cs),
                  const _InlineCashflowTrend(),
                  const SizedBox(height: 32),

                  _SectionHeader('TOP SPENDS THIS MONTH', cs),
                  _InlineTopSpends(from: fromIso, to: toIso),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],

          // ── Detailed Statements ──────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              children: [
                _SectionHeader('DETAILED STATEMENTS', cs),
                _ReportListItem(
                  emoji: '🏦',
                  title: 'Account Statement',
                  description: 'Transaction ledger by account',
                  color: const Color(0xFF0891B2),
                  onTap: () => _push(context, AccountStatementReport(year: year, month: month)),
                ),
                _ReportListItem(
                  emoji: '🎯',
                  title: 'Budget Performance',
                  description: 'Planned vs. actual spending',
                  color: const Color(0xFFD97706),
                  onTap: () => _push(context, BudgetPerformanceReport(year: year, month: month)),
                ),
                _ReportListItem(
                  emoji: '📅',
                  title: 'Yearly Overview',
                  description: '12-month income vs. expense trend',
                  color: const Color(0xFF0284C7),
                  onTap: () => _push(context, YearlySummaryReport(year: year)),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

String _fmtAmt(double v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.cs);
  final String title;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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

class _FlatStatCard extends StatelessWidget {
  const _FlatStatCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₹${_fmtAmt(amount)}',
              style: GoogleFonts.manrope(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportListItem extends StatelessWidget {
  const _ReportListItem({
    required this.emoji,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

// ── Inline Chart Helpers ──────────────────────────────────────────────────

class _InlineCategoryChart extends ConsumerWidget {
  const _InlineCategoryChart({required this.from, required this.to});
  final String from;
  final String to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(categoryBreakdownProvider((from, to)));
    
    return async.when(
      loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox(),
      data: (cats) {
        if (cats.isEmpty) return const SizedBox();
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
                      titleStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: cs.surface),
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: InsightCard(text: 'Your entire spending this month went to ${top1.name} (100%).'),
                  );
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
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: InsightCard(text: insight),
                );
              }(),
            ],
          ],
        );
      },
    );
  }
}

class _InlineCashflowTrend extends ConsumerWidget {
  const _InlineCashflowTrend();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(cashFlowProvider);

    return async.when(
      loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox(),
      data: (months) {
        if (months.isEmpty) return const SizedBox();
        final maxY = months.expand((m) => [m.income, m.expense]).fold<double>(0, (a, b) => a > b ? a : b);
        final yMax = maxY > 0 ? maxY * 1.2 : 1000.0;
        const incomeColor = Color(0xFF16A34A);
        const expenseColor = Color(0xFFDC2626);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: yMax,
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: 1,
                          getTitlesWidget: (val, meta) {
                            final i = val.toInt();
                            if (i < 0 || i >= months.length) return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                ReportsScreen._months[months[i].month - 1],
                                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant, strokeWidth: 1),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: months.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.income)).toList(),
                        color: incomeColor,
                        barWidth: 3,
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: months.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.expense)).toList(),
                        color: expenseColor,
                        barWidth: 3,
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: incomeColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('Income', style: TextStyle(fontSize: 12, color: cs.onSurface)),
                  const SizedBox(width: 20),
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: expenseColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('Expense', style: TextStyle(fontSize: 12, color: cs.onSurface)),
                ],
              ),
              if (months.isNotEmpty) ...[
                () {
                  final posCount = months.where((m) => m.income > m.expense).length;
                  final totalGain = months.fold<double>(0, (s, m) => s + (m.income - m.expense));
                  
                  MonthTotal? bestMonth;
                  MonthTotal? worstMonth;
                  for (final m in months) {
                    if (bestMonth == null || (m.income - m.expense) > (bestMonth.income - bestMonth.expense)) bestMonth = m;
                    if (worstMonth == null || (m.income - m.expense) < (worstMonth.income - worstMonth.expense)) worstMonth = m;
                  }
                  
                  String insight = 'Over the last ${months.length} months, you maintained a positive cash flow in $posCount months. ';
                  
                  if (bestMonth != null && worstMonth != null) {
                    final bestName = ReportsScreen._months[bestMonth.month - 1];
                    final worstName = ReportsScreen._months[worstMonth.month - 1];
                    final bestAmt = bestMonth.income - bestMonth.expense;
                    final worstAmt = worstMonth.income - worstMonth.expense;
                    
                    if (bestAmt > 0) insight += 'Your most profitable month was $bestName (+₹${_fmtAmt(bestAmt)}). ';
                    if (worstAmt < 0) insight += 'Your heaviest loss was in $worstName (-₹${_fmtAmt(worstAmt.abs())}). ';
                  }
                  
                  insight += 'Overall, this period resulted in a net ${totalGain >= 0 ? 'gain' : 'loss'} of ₹${_fmtAmt(totalGain.abs())}.';
                  return InsightCard(text: insight);
                }(),
              ],
            ],
          ),
        );
      },
    );
  }
}
class _InlineTopSpends extends ConsumerWidget {
  const _InlineTopSpends({required this.from, required this.to});
  final String from;
  final String to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(topSpendsProvider((from, to)));

    return async.when(
      loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox(),
      data: (txs) {
        if (txs.isEmpty) return const SizedBox();
        final maxAmt = txs.first.amount;
        
        return Column(
          children: txs.take(3).map((tx) {
            final fraction = maxAmt > 0 ? (tx.amount / maxAmt).clamp(0.0, 1.0) : 0.0;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(
                tx.note.isEmpty ? 'Expense' : tx.note,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: cs.outlineVariant,
                    color: cs.primary,
                    minHeight: 4,
                  ),
                ),
              ),
              trailing: Text(
                '₹${_fmtAmt(tx.amount)}',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

List<Color> _palette(int count) {
  const base = [
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFF84CC16),
  ];
  return List.generate(count, (i) => base[i % base.length]);
}

