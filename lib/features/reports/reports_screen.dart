import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/themes/app_fonts.dart';
import '../../app/widgets/screen_header.dart';
import '../../data/db/app_database.dart';
import '../../state/ai_providers.dart';
import '../../state/app_mode_providers.dart';
import '../../state/custom_report_providers.dart';
import '../../state/period_providers.dart';
import 'widgets/report_card.dart';

import 'reports/account_statement_report.dart';
import 'reports/budget_performance_report.dart';
import 'reports/cashflow_forecast_report.dart';
import 'reports/cashflow_trend_report.dart';
import 'reports/category_drilldown_report.dart';
import 'reports/contact_statement_report.dart';
import 'reports/mode_breakdown_report.dart';
import 'reports/monthly_summary_report.dart';
import 'reports/top_spends_report.dart';
import 'reports/yearly_summary_report.dart';

/// The Reports hub. Regroups the 10 built-in reports into clear sections
/// (Overview / Spending / Accounts & Planning / Dues / AI) and adds the
/// "Your Reports" section for saved custom reports + a hero "New custom report"
/// card. All 10 built-ins are retained (per the redesign decision); the
/// grouping + section headers remove the "wall of cards" feel.
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
    final aiEnabled = ref.watch(aiEnabledProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final savedReports =
        ref.watch(customReportsStreamProvider).valueOrNull ??
            const <CustomReport>[];

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── Header ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'reports',
              subtitle: 'Insights, summaries & custom reports',
              actions: [], // Removed MonthNav as per redesign
            ),
          ),

          // ── AI Copilot (two compact side-by-side entry cards) ───────
          // Hidden in Offline mode (no AI features available).
          if (isOnline) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(child: _SectionHeader('AI COPILOT', cs)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _CompactAiCard(
                            kind: _AiKind.ask, enabled: aiEnabled),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CompactAiCard(
                            kind: _AiKind.report, enabled: aiEnabled),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],

          // ── Overview ──────────────────────────────────────────────────
          SliverToBoxAdapter(child: _SectionHeader('OVERVIEW', cs)),
          _reportGrid(context, [
            _Tile('📅', 'Monthly', 'Detailed analysis for a specific month',
                const Color(0xFF10B981),
                () => _push(context, MonthlySummaryReport(year: year, month: month))),
            _Tile('📆', 'Yearly', '12-month income vs. expense trend',
                const Color(0xFF0284C7),
                () => _push(context, YearlySummaryReport(year: year))),
            _Tile('📈', 'Cashflow', '6-month income and expense trajectory',
                const Color(0xFF3B82F6),
                () => _push(context, const CashflowTrendReport())),
            _Tile('🔮', 'Forecast', 'Run-rate month-end projection & pace nudges',
                const Color(0xFF14B8A6),
                () => _push(context, const CashflowForecastReport())),
          ]),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // ── Spending ──────────────────────────────────────────────────
          SliverToBoxAdapter(child: _SectionHeader('SPENDING', cs)),
          _reportGrid(context, [
            _Tile('📊', 'Categories', 'Distribution of expenses across categories',
                const Color(0xFFF59E0B),
                () => _push(context,
                    CategoryDrilldownReport(year: year, month: month))),
            _Tile('🔥', 'Top Categories',
                'Where you spent the most this month', const Color(0xFFEF4444),
                () => _push(context, TopSpendsReport(year: year, month: month))),
            _Tile('💳', 'Payment Modes', 'How you pay for your expenses',
                const Color(0xFF8B5CF6),
                () => _push(context, ModeBreakdownReport(year: year, month: month))),
          ]),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // ── Accounts & Planning ───────────────────────────────────────
          SliverToBoxAdapter(child: _SectionHeader('ACCOUNTS & PLANNING', cs)),
          _reportGrid(context, [
            _Tile('🏦', 'Account Stmt', 'Transaction ledger by account',
                const Color(0xFF0891B2),
                () => _push(context,
                    AccountStatementReport(year: year, month: month))),
            _Tile('🎯', 'Budget Perf', 'Planned vs. actual spending',
                const Color(0xFFD97706),
                () => _push(context, const BudgetPerformanceReport())),
          ]),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // ── Dues (on-device only) ─────────────────────────────────────
          SliverToBoxAdapter(
              child: _SectionHeader('DUES  ·  ON-DEVICE ONLY', cs)),
          _reportGrid(context, [
            _Tile('🤝', 'Contact Stmt',
                'Track dues and settlements by contact', const Color(0xFF6366F1),
                () => _push(context, const ContactStatementReport())),
          ]),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // ── Your Reports (custom, saved on-device) ───────────────────
          SliverToBoxAdapter(child: _SectionHeader('YOUR REPORTS', cs)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _NewCustomReportHero(onTap: () => context.push('/reports/custom-builder')),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (savedReports.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  for (final r in savedReports)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ReportCard(
                        compact: true,
                        emoji: '🧩',
                        title: r.name,
                        description: 'Saved custom report',
                        color: const Color(0xFF7C3AED),
                        onTap: () => context.push('/reports/custom/${r.id}'),
                      ),
                    ),
                ]),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }

  Widget _reportGrid(BuildContext context, List<_Tile> tiles) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 140,
        ),
        delegate: SliverChildListDelegate([
          for (final t in tiles)
            ReportCard(
              emoji: t.emoji,
              title: t.title,
              description: t.description,
              color: t.color,
              onTap: t.onTap,
            ),
        ]),
      ),
    );
  }
}

/// A small bundle of the props needed to build a [ReportCard] in a section.
class _Tile {
  const _Tile(this.emoji, this.title, this.description, this.color, this.onTap);
  final String emoji;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;
}

enum _AiKind { ask, report }

/// Compact half-width entry card for the two AI features, shown
/// side-by-side. Uses the matched M3 `primaryContainer`/`onPrimaryContainer`
/// pair (ask) or `secondaryContainer`/`onSecondaryContainer` pair (report)
/// at full opacity so text contrast is guaranteed in both themes.
class _CompactAiCard extends ConsumerWidget {
  const _CompactAiCard({required this.kind, required this.enabled});
  final _AiKind kind;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isAsk = kind == _AiKind.ask;
    final bg = isAsk ? cs.primaryContainer : cs.secondaryContainer;
    final fg = isAsk ? cs.onPrimaryContainer : cs.onSecondaryContainer;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // When AI is on: ask → create a fresh chat thread and open it (pruned
        // automatically if the user backs out without sending); report → open
        // the on-demand report. When AI is off, `go` (not push) to the
        // Settings *tab* — pushing a tab route from another tab can stack a
        // second /settings page and trip a duplicate page-key check.
        onTap: () async {
          if (!enabled) {
            context.go('/settings');
            return;
          }
          if (isAsk) {
            final thread =
                await ref.read(aiChatRepositoryProvider).createThread();
            if (!context.mounted) return;
            context.push('/ai/ask/${thread.id}');
          } else {
            context.push('/ai/report');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isAsk
                      ? Icons.auto_awesome_rounded
                      : Icons.description_outlined,
                  color: fg,
                  size: 20,
                ),
              ),
              const Spacer(),
              Text(
                isAsk ? 'Ask SpendWise AI' : 'AI Monthly Report',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                enabled
                    ? (isAsk
                        ? 'Ask anything — anonymized.'
                        : 'Narrative report + PDF.')
                    : 'Enable AI Copilot',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: plusJakartaSans(
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  color: fg.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hero card inviting the user to build a custom report. The custom report is
/// user-authored and fully on-device — the spec never leaves the device and is
/// never sent to the LLM (see `CustomReportExecutor`).
class _NewCustomReportHero extends StatelessWidget {
  const _NewCustomReportHero({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.onPrimaryContainer.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.tune_rounded,
                    color: cs.onPrimaryContainer, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Build a custom report',
                        style: plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cs.onPrimaryContainer)),
                    const SizedBox(height: 3),
                    Text(
                      'Group by category, account, mode or time — pick a metric, filter, and chart. Runs on-device.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: plusJakartaSans(
                          fontSize: 11,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: cs.onPrimaryContainer.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add_rounded, color: cs.onPrimaryContainer, size: 26),
            ],
          ),
        ),
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
          style: plusJakartaSans(
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