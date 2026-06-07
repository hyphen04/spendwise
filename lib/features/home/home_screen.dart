import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/widgets/screen_header.dart';
import '../../app/widgets/smooth_line_chart.dart';
import '../../data/models/transaction_row.dart';
import '../../state/home_providers.dart';
import '../../state/period_providers.dart';
import '../../state/reports_providers.dart';
import '../../state/transactions_providers.dart';
import '../../services/update_service.dart';
import '../../state/update_provider.dart';
import '../search/search_sheet.dart';
import '../settings/update_check_dialog.dart';
import '../transactions/sheets/add_edit_transaction_sheet.dart';
import '../transactions/sheets/transaction_detail_sheet.dart';
import '../transactions/widgets/transaction_tile.dart';
import 'widgets/month_nav.dart';

const _kRecentLimit = 10;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final period = ref.watch(selectedPeriodProvider);
    final summary =
        ref.watch(homeSummaryProvider((period.year, period.month)));
    final monthRows =
        ref.watch(monthTransactionRowsProvider((period.year, period.month)));
    final cashflow = ref.watch(cashFlowProvider);

    final topPad = MediaQuery.paddingOf(context).top;
    final botPad = MediaQuery.paddingOf(context).bottom;

    final cashflowData = cashflow.valueOrNull ?? [];
    final chartIncomeValues = cashflowData.map((m) => m.income).toList();
    final chartExpenseValues = cashflowData.map((m) => m.expense).toList();
    final recentRows = monthRows.take(_kRecentLimit).toList();
    final hasMore = monthRows.length > _kRecentLimit;

    // Month label for the caption
    final captionMonth = _monthCaption(period.month, period.year);

    final pendingUpdate = ref.watch(pendingUpdateProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Fixed header: wordmark + month nav + search ────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPad + 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'spendwise',
                  style: GoogleFonts.manrope(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    height: 1.0,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                const MonthNav(),
                const SizedBox(width: 8),
                HeaderIconButton(
                  icon: Icons.search_rounded,
                  onTap: () => showSearchSheet(context),
                  tooltip: 'Search',
                ),
              ],
            ).animate().fadeIn(duration: 250.ms),
          ),

          // ── Scrollable content ─────────────────────────────────────────────
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Update banner (scrolls with content) ──────────────────
                if (pendingUpdate != null)
                  SliverToBoxAdapter(child: _UpdateBanner(pendingUpdate)),

          // ── Balance number + caption ───────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Caption: "Jun 2026 · 23 transactions"
                  Text(
                    '$captionMonth · ${monthRows.length} transaction${monthRows.length == 1 ? '' : 's'}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurfaceVariant,
                    ),
                  ).animate().fadeIn(delay: 40.ms),
                  const SizedBox(height: 6),
                  Text(
                    '${summary.net >= 0 ? '' : '−'}₹${_fmt(summary.net.abs())}',
                    style: GoogleFonts.manrope(
                      fontSize: 52,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.0,
                    ),
                  ).animate().fadeIn(delay: 60.ms).slideY(
                      begin: 0.08, end: 0, duration: 300.ms),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'net balance',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '↑ ₹${_fmt(summary.income)}  ↓ ₹${_fmt(summary.expense)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 100.ms),
                ],
              ),
            ),
          ),

          // ── Smooth line chart ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
              child: chartIncomeValues.length >= 2
                  ? SmoothLineChart(
                      incomeValues: chartIncomeValues,
                      expenseValues: chartExpenseValues,
                      height: 110,
                      highlightIndex: chartIncomeValues.length - 1,
                    ).animate().fadeIn(delay: 120.ms, duration: 400.ms)
                  : const SizedBox(height: 110),
            ),
          ),

          // ── Divider ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Divider(height: 1, thickness: 0.8, color: cs.outline),
          ),

          // ── "Recent transactions" header with totals ───────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'recent transactions',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${monthRows.length} this month',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Transaction list (capped at 10) ────────────────────────────────
          if (monthRows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No transactions',
                      style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap + to add one',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._buildDateGroups(recentRows, cs, ref),

          // ── "View all" button ──────────────────────────────────────────────
          if (hasMore || monthRows.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: TextButton(
                  onPressed: () {
                    final p = ref.read(selectedPeriodProvider);
                    final from = DateTime(p.year, p.month, 1);
                    final to = DateTime(p.year, p.month + 1, 0);
                    ref
                        .read(pendingTransactionsFilterProvider.notifier)
                        .state = (from: from, to: to);
                    context.go('/transactions');
                  },
                  child: Text(
                    hasMore
                        ? 'View all ${monthRows.length} transactions →'
                        : 'View transactions →',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
            ),

          SliverToBoxAdapter(child: SizedBox(height: botPad + 100)),
        ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDateGroups(
    List<TransactionRow> rows,
    ColorScheme cs,
    WidgetRef ref,
  ) {
    final groups = <String, List<TransactionRow>>{};
    for (final row in rows) {
      final key = row.transaction.transactionDate.substring(0, 10);
      groups.putIfAbsent(key, () => []).add(row);
    }
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final slivers = <Widget>[];
    for (final dateKey in sortedKeys) {
      final list = groups[dateKey]!;
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(
            _humanDate(dateKey),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ));
      slivers.add(SliverList.builder(
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final row = list[i];
          return Column(
            children: [
              TransactionTile(
                row: row,
                onTap: () => showTransactionDetailSheet(ctx, row: row),
                onEdit: () =>
                    showAddEditTransactionSheet(ctx, editing: row.transaction),
                onDuplicate: () => ref
                    .read(transactionsRepositoryProvider)
                    .duplicate(row.transaction),
                onDelete: () => ref
                    .read(transactionsRepositoryProvider)
                    .delete(row.transaction.id),
              ).animate(delay: Duration(milliseconds: i * 25)).fadeIn(duration: 180.ms),
              if (i < list.length - 1)
                Divider(
                    height: 1,
                    thickness: 0.5,
                    color: cs.outline,
                    indent: 20,
                    endIndent: 20),
            ],
          );
        },
      ));
    }
    return slivers;
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

String _monthCaption(int month, int year) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${names[month - 1]} $year';
}

String _humanDate(String iso) {
  try {
    final dt = DateTime.parse(iso);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'TODAY';
    if (d == yesterday) return 'YESTERDAY';
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
  } catch (_) {
    return iso;
  }
}

String _fmt(double v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

// ── Update banner ─────────────────────────────────────────────────────────────

class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner(this.info);
  final UpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update_outlined,
              size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'SpendWise v${info.version} available',
              style: tt.bodySmall?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: cs.onPrimaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  UpdateCheckDialog(currentVersion: info.version),
            ),
            child: const Text('Update'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: cs.onPrimaryContainer,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () =>
                ref.read(pendingUpdateProvider.notifier).state = null,
          ),
        ],
      ),
    );
  }
}
