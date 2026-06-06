import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state/database_provider.dart';
import '../../state/reports_providers.dart';
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

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  String get _fromIso => DateTime(_year, _month).toIso8601String();
  String get _toIso => DateTime(_year, _month + 1).toIso8601String();
  String get _monthLabel => '${_months[_month - 1]} $_year';

  void _prevMonth() => setState(() {
        if (_month == 1) {
          _month = 12;
          _year--;
        } else {
          _month--;
        }
      });

  void _nextMonth() {
    if (!_canGoNext) return;
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year++;
      } else {
        _month++;
      }
    });
  }

  bool get _canGoNext {
    final now = DateTime.now();
    return _year < now.year || (_year == now.year && _month < now.month);
  }

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final db = ref.read(appDatabaseProvider);

    final summary =
        ref.watch(monthlySummaryProvider((_year, _month))).valueOrNull;
    final cashFlow = ref.watch(cashFlowProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Export',
            onPressed: () => ExportService.showExportSheet(
              context,
              db,
              from: _fromIso,
              to: _toIso,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Period hero
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                // Period chip with nav
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _prevMonth,
                      child: Icon(Icons.chevron_left,
                          size: 20, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _monthLabel,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: _canGoNext ? _nextMonth : null,
                      child: Icon(Icons.chevron_right,
                          size: 20,
                          color: _canGoNext
                              ? cs.onSurfaceVariant
                              : cs.onSurfaceVariant.withValues(alpha: 0.3)),
                    ),
                  ],
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
                  onTap: () => _push(
                      MonthlySummaryReport(year: _year, month: _month)),
                ),
                ReportCard(
                  emoji: '📅',
                  title: 'Yearly Overview',
                  description: '12-month income vs. expense',
                  color: const Color(0xFF0284C7),
                  onTap: () => _push(YearlySummaryReport(year: _year)),
                ),
                ReportCard(
                  emoji: '🔍',
                  title: 'Category Drilldown',
                  description: 'Spending breakdown by category',
                  color: const Color(0xFF7C3AED),
                  onTap: () => _push(CategoryDrilldownReport(
                      from: _fromIso,
                      to: _toIso,
                      monthLabel: _monthLabel)),
                ),
                ReportCard(
                  emoji: '💳',
                  title: 'Mode Breakdown',
                  description: 'Payment method analysis',
                  color: const Color(0xFFDB2777),
                  onTap: () => _push(ModeBreakdownReport(
                      from: _fromIso,
                      to: _toIso,
                      monthLabel: _monthLabel)),
                ),
                ReportCard(
                  emoji: '🏦',
                  title: 'Account Statement',
                  description: 'Transaction ledger by account',
                  color: const Color(0xFF0891B2),
                  onTap: () => _push(
                      AccountStatementReport(year: _year, month: _month)),
                ),
                ReportCard(
                  emoji: '📈',
                  title: 'Cash Flow',
                  description: 'Rolling 6-month income & expense',
                  color: cs.onSurface,
                  onTap: () => _push(const CashflowTrendReport()),
                ),
                ReportCard(
                  emoji: '🔝',
                  title: 'Top Spends',
                  description: 'Biggest transactions this period',
                  color: cs.onSurfaceVariant,
                  onTap: () => _push(TopSpendsReport(
                      from: _fromIso,
                      to: _toIso,
                      monthLabel: _monthLabel)),
                ),
                ReportCard(
                  emoji: '🎯',
                  title: 'Budget Performance',
                  description: 'Planned vs. actual spending',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _push(
                      BudgetPerformanceReport(year: _year, month: _month)),
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
