import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/widgets/screen_header.dart';
import '../../state/period_providers.dart';

import 'reports/account_statement_report.dart';
import 'reports/budget_performance_report.dart';
import 'reports/cashflow_trend_report.dart';
import 'reports/category_drilldown_report.dart';
import 'reports/contact_statement_report.dart';
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

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── Header ───────────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'reports',
              subtitle: 'Insights & summaries',
              actions: [], // Removed MonthNav as per redesign
            ),
          ),

          // ── Summaries ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 16),
                _SectionHeader('SUMMARIES', cs),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 140,
              ),
              delegate: SliverChildListDelegate([
                _ReportCard(
                  emoji: '📅',
                  title: 'Monthly',
                  description: 'Detailed analysis for a specific month',
                  color: const Color(0xFF10B981),
                  onTap: () => _push(context, MonthlySummaryReport(year: year, month: month)),
                ),
                _ReportCard(
                  emoji: '📆',
                  title: 'Yearly',
                  description: '12-month income vs. expense trend',
                  color: const Color(0xFF0284C7),
                  onTap: () => _push(context, YearlySummaryReport(year: year)),
                ),
              ]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),

          // ── Insights ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader('INSIGHTS', cs),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 140,
              ),
              delegate: SliverChildListDelegate([
                _ReportCard(
                  emoji: '📊',
                  title: 'Categories',
                  description: 'Distribution of expenses across categories',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _push(context, CategoryDrilldownReport(year: year, month: month)),
                ),
                _ReportCard(
                  emoji: '📈',
                  title: 'Cashflow',
                  description: '6-month income and expense trajectory',
                  color: const Color(0xFF3B82F6),
                  onTap: () => _push(context, const CashflowTrendReport()),
                ),
                _ReportCard(
                  emoji: '💳',
                  title: 'Payment Modes',
                  description: 'How you pay for your expenses',
                  color: const Color(0xFF8B5CF6),
                  onTap: () => _push(context, ModeBreakdownReport(year: year, month: month)),
                ),
                _ReportCard(
                  emoji: '🔥',
                  title: 'Top Spends',
                  description: 'Your largest individual transactions',
                  color: const Color(0xFFEF4444),
                  onTap: () => _push(context, TopSpendsReport(year: year, month: month)),
                ),
              ]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),

          // ── Detailed Statements ──────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader('DETAILED STATEMENTS', cs),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 140,
              ),
              delegate: SliverChildListDelegate([
                _ReportCard(
                  emoji: '🏦',
                  title: 'Account Stmt',
                  description: 'Transaction ledger by account',
                  color: const Color(0xFF0891B2),
                  onTap: () => _push(context, AccountStatementReport(year: year, month: month)),
                ),
                _ReportCard(
                  emoji: '🎯',
                  title: 'Budget Perf',
                  description: 'Planned vs. actual spending',
                  color: const Color(0xFFD97706),
                  onTap: () => _push(context, const BudgetPerformanceReport()),
                ),
                _ReportCard(
                  emoji: '🤝',
                  title: 'Contact Stmt',
                  description: 'Track dues and settlements by contact',
                  color: const Color(0xFF6366F1),
                  onTap: () => _push(context, const ContactStatementReport()),
                ),
              ]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
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
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                ),
                const Spacer(),
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
