import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/widgets/screen_header.dart';

import '../../state/period_providers.dart';
import '../../state/reports_providers.dart';
import '../home/widgets/month_nav.dart';

import 'reports/account_statement_report.dart';
import 'reports/budget_performance_report.dart';
import 'reports/cashflow_trend_report.dart';
import 'reports/category_drilldown_report.dart';
import 'reports/mode_breakdown_report.dart';
import 'reports/monthly_summary_report.dart';
import 'reports/top_spends_report.dart';
import 'reports/yearly_summary_report.dart';

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

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────
          const ScreenHeader(
            title: 'reports',
            subtitle: 'Insights & summaries',
            actions: [
              MonthNav(),
            ],
          ),

          // ── Period hero (At a Glance) ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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

          // ── Categorized List ─────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _SectionHeader('OVERVIEWS', cs),
                _ReportListItem(
                  emoji: '📊',
                  title: 'Monthly Summary',
                  description: 'Income, expenses & top categories',
                  color: const Color(0xFF3B82F6),
                  onTap: () => _push(context, MonthlySummaryReport(year: year, month: month)),
                ),
                _ReportListItem(
                  emoji: '📅',
                  title: 'Yearly Overview',
                  description: '12-month income vs. expense trend',
                  color: const Color(0xFF0284C7),
                  onTap: () => _push(context, YearlySummaryReport(year: year)),
                ),
                _ReportListItem(
                  emoji: '📈',
                  title: 'Cash Flow Trend',
                  description: 'Rolling 6-month visual analysis',
                  color: const Color(0xFF10B981),
                  onTap: () => _push(context, const CashflowTrendReport()),
                ),

                const SizedBox(height: 24),
                _SectionHeader('DEEP DIVES', cs),
                _ReportListItem(
                  emoji: '🔍',
                  title: 'Category Drilldown',
                  description: 'Detailed spending by category',
                  color: const Color(0xFF7C3AED),
                  onTap: () => _push(context, CategoryDrilldownReport(from: fromIso, to: toIso, monthLabel: monthLabel)),
                ),
                _ReportListItem(
                  emoji: '💳',
                  title: 'Mode Breakdown',
                  description: 'Payment method utilization',
                  color: const Color(0xFFDB2777),
                  onTap: () => _push(context, ModeBreakdownReport(from: fromIso, to: toIso, monthLabel: monthLabel)),
                ),
                _ReportListItem(
                  emoji: '🔝',
                  title: 'Top Spends',
                  description: 'Largest transactions this period',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _push(context, TopSpendsReport(from: fromIso, to: toIso, monthLabel: monthLabel)),
                ),

                const SizedBox(height: 24),
                _SectionHeader('STATEMENTS', cs),
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
