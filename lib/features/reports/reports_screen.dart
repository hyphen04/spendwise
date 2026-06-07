import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/widgets/screen_header.dart';
import '../../state/database_provider.dart';
import '../../state/period_providers.dart';
import '../../state/reports_providers.dart';
import '../home/widgets/month_nav.dart';
import 'export/export_service.dart';
import 'reports/account_statement_report.dart';
import 'reports/budget_performance_report.dart';
import 'reports/cashflow_trend_report.dart';
import 'reports/category_drilldown_report.dart';
import 'reports/mode_breakdown_report.dart';
import 'reports/monthly_summary_report.dart';
import 'reports/top_spends_report.dart';
import 'reports/yearly_summary_report.dart';
import 'widgets/report_card.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final db = ref.read(appDatabaseProvider);

    final period = ref.watch(selectedPeriodProvider);
    final year = period.year;
    final month = period.month;

    final summary =
        ref.watch(monthlySummaryProvider((year, month))).valueOrNull;
    final cashFlow = ref.watch(cashFlowProvider).valueOrNull ?? [];

    final fromIso = DateTime(year, month).toIso8601String();
    final toIso = DateTime(year, month + 1).toIso8601String();
    final monthLabel = '${_months[month - 1]} $year';

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────
          ScreenHeader(
            title: 'reports',
            actions: [
              const MonthNav(),
              const SizedBox(width: 4),
              HeaderIconButton(
                icon: Icons.ios_share_outlined,
                onTap: () => ExportService.showExportSheet(
                  context,
                  db,
                  defaultFrom: fromIso,
                  defaultTo: toIso,
                ),
                tooltip: 'Export',
              ),
            ],
          ),

          // ── Period hero ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary != null
                            ? '₹${_fmtAmt(summary.expense)}'
                            : '₹—',
                        style: GoogleFonts.manrope(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total spending',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Mini cashflow line chart
          if (cashFlow.length >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: SizedBox(
                height: 80,
                child: _MiniLineChart(data: cashFlow),
              ),
            ),

          const SizedBox(height: 4),
          const Divider(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
              children: [
                ReportCard(
                  emoji: '📊',
                  title: 'Monthly Summary',
                  description: 'Income, expenses & top categories',
                  color: cs.onSurface,
                  onTap: () => _push(context,
                      MonthlySummaryReport(year: year, month: month)),
                ),
                ReportCard(
                  emoji: '📅',
                  title: 'Yearly Overview',
                  description: '12-month income vs. expense',
                  color: const Color(0xFF0284C7),
                  onTap: () => _push(context,YearlySummaryReport(year: year)),
                ),
                ReportCard(
                  emoji: '🔍',
                  title: 'Category Drilldown',
                  description: 'Spending breakdown by category',
                  color: const Color(0xFF7C3AED),
                  onTap: () => _push(context,CategoryDrilldownReport(
                      from: fromIso,
                      to: toIso,
                      monthLabel: monthLabel)),
                ),
                ReportCard(
                  emoji: '💳',
                  title: 'Mode Breakdown',
                  description: 'Payment method analysis',
                  color: const Color(0xFFDB2777),
                  onTap: () => _push(context,ModeBreakdownReport(
                      from: fromIso,
                      to: toIso,
                      monthLabel: monthLabel)),
                ),
                ReportCard(
                  emoji: '🏦',
                  title: 'Account Statement',
                  description: 'Transaction ledger by account',
                  color: const Color(0xFF0891B2),
                  onTap: () => _push(context,
                      AccountStatementReport(year: year, month: month)),
                ),
                ReportCard(
                  emoji: '📈',
                  title: 'Cash Flow',
                  description: 'Rolling 6-month income & expense',
                  color: cs.onSurface,
                  onTap: () => _push(context,const CashflowTrendReport()),
                ),
                ReportCard(
                  emoji: '🔝',
                  title: 'Top Spends',
                  description: 'Biggest transactions this period',
                  color: cs.onSurfaceVariant,
                  onTap: () => _push(context,TopSpendsReport(
                      from: fromIso,
                      to: toIso,
                      monthLabel: monthLabel)),
                ),
                ReportCard(
                  emoji: '🎯',
                  title: 'Budget Performance',
                  description: 'Planned vs. actual spending',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _push(context,
                      BudgetPerformanceReport(year: year, month: month)),
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

class _MiniLineChart extends StatelessWidget {
  const _MiniLineChart({required this.data});
  final List<dynamic> data; // List<MonthTotal>

  static const _green = Color(0xFF16A34A);
  static const _red = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    final incomeSpots = <FlSpot>[];
    final expenseSpots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      incomeSpots.add(FlSpot(i.toDouble(), data[i].income));
      expenseSpots.add(FlSpot(i.toDouble(), data[i].expense));
    }
    final allValues = data
        .expand((d) => [d.income as double, d.expense as double])
        .toList();
    final maxY = allValues.isEmpty
        ? 1.0
        : (allValues.reduce((a, b) => a > b ? a : b) * 1.1).clamp(1.0, double.infinity);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: incomeSpots,
            isCurved: true,
            color: _green,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: _green.withValues(alpha: 0.08),
            ),
          ),
          LineChartBarData(
            spots: expenseSpots,
            isCurved: true,
            color: _red,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: _red.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}
