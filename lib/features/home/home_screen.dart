import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../app/utils/infinite_scroll.dart';
import '../../app/widgets/load_more_button.dart';
import '../../app/widgets/smooth_line_chart.dart';
import '../../data/models/transaction_row.dart';
import '../../state/home_providers.dart';
import '../../state/reports_providers.dart';
import '../../state/transactions_providers.dart';

import '../../services/update_service.dart';
import '../../state/update_provider.dart';
import '../../state/prefs_providers.dart';
import '../../app/utils/feedback.dart';
import '../search/search_sheet.dart';
import '../settings/update_sheet.dart';
import '../transactions/sheets/add_edit_transaction_sheet.dart';
import '../transactions/sheets/amount_entry_sheet.dart';
import '../transactions/transaction_actions.dart';
import '../transactions/widgets/transaction_tile.dart';
import 'widgets/home_dues_widget.dart';


class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _paging = PagingState(pageSize: 20);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final now = DateTime.now();
    // This month's summary
    final summary = ref.watch(homeSummaryProvider((now.year, now.month)));
    final cashflow = ref.watch(cashFlowProvider);

    // Global data
    final netWorthAsync = ref.watch(globalNetWorthProvider);
    // Full recent feed (all months, newest-first). The home "recent activity"
    // section is scoped to the CURRENT MONTH only — the "View all history →"
    // button navigates to the transactions screen for older months.
    final allRecentAsync = ref.watch(transactionRowsProvider);
    final fullRows = allRecentAsync.valueOrNull ?? <TransactionRow>[];
    final monthPrefix =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final allRecentRows =
        fullRows.where((r) => r.transaction.transactionDate.startsWith(monthPrefix)).toList();

    final topPad = MediaQuery.paddingOf(context).top;
    final botPad = MediaQuery.paddingOf(context).bottom;

    final cashflowData = cashflow.valueOrNull ?? [];
    final chartIncomeValues = cashflowData.map((m) => m.income).toList();
    final chartExpenseValues = cashflowData.map((m) => m.expense).toList();

    // Month label for the caption
    final captionMonth = _monthCaption(now.month, now.year);

    final pendingUpdate = ref.watch(pendingUpdateProvider);
    final totalNetWorth = netWorthAsync.valueOrNull ?? 0.0;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Fixed header: wordmark + month nav + search ────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPad + 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Brand wordmark: "spendwise" set in Space Grotesk — the same
                // geometric typeface the app uses for the net-worth number —
                // so the brand ties itself to the money/numeric identity with
                // no ornament. "wise" in the brand color.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'spend',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface,
                              height: 1.0,
                              letterSpacing: -0.5,
                            ),
                          ),
                          TextSpan(
                            text: 'wise',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                              height: 1.0,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _greeting(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
            const Spacer(),
            // Search Button in Header
            IconButton(
              icon: const Icon(Icons.search_rounded),
              color: cs.onSurfaceVariant,
              onPressed: () => showSearchSheet(context),
            ),
          ],
            ).animate().fadeIn(duration: 250.ms),
          ),

          // ── Scrollable content ─────────────────────────────────────────────
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                maybeLoadMore(
                  n,
                  hasMore: _paging.visibleCount < allRecentRows.length,
                  onLoadMore: () => setState(_paging.loadMore),
                );
                return false;
              },
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
                  // Caption: "Total Net Worth" + Visibility Toggle
                  Row(
                    children: [
                      Text(
                        'total net worth',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ).animate().fadeIn(delay: 40.ms),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          final current = ref.read(hideNetWorthProvider);
                          ref.read(hideNetWorthProvider.notifier).set(!current);
                        },
                        child: Icon(
                          ref.watch(hideNetWorthProvider) ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      ref.watch(hideNetWorthProvider)
                          ? '••••••••'
                          : '${totalNetWorth >= 0 ? '' : '−'}₹${NumberFormat('#,##,##0.00', 'en_IN').format(totalNetWorth.abs())}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        letterSpacing: -1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ).animate().fadeIn(delay: 60.ms).slideY(
                      begin: 0.08, end: 0, duration: 300.ms),
                  const SizedBox(height: 24),
                  
                  // This month's summary
                  Row(
                    children: [
                      Text(
                        'THIS MONTH ($captionMonth)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      if (summary.income > 0 || summary.expense > 0)
                        Text(
                          '↑ ₹${_fmt(summary.income)}   ↓ ₹${_fmt(summary.expense)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        )
                      else
                        Text(
                          'No activity yet',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
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

          // ── Quick Dues Widget ─────────────────────────────────────────────
          if (ref.watch(showQuickDuesProvider))
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: HomeDuesWidget(),
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
                    'recent activity',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),

          // ── Transaction list ───────────────────────────────────────────────
          if (allRecentRows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fullRows.isEmpty
                          ? 'Welcome to SpendWise!'
                          : 'No activity this month',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fullRows.isEmpty
                          ? 'Tap + to add your first transaction.'
                          : 'Tap + to add one, or view all history →',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ..._buildDateGroups(_visibleRecent(allRecentRows), cs, ref),
            if (_paging.hasMore(allRecentRows.length))
              SliverToBoxAdapter(
                child: LoadMoreButton(
                  showing: _paging.visibleCount,
                  total: allRecentRows.length,
                  pageSize: _paging.pageSize,
                  onTap: () => setState(_paging.loadMore),
                ),
              ),
          ],

          // ── "View all" button ──────────────────────────────────────────────
          // Always offered when there is any data so the user can reach older
          // months from the home page (recent activity is scoped to this month).
          if (fullRows.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: TextButton(
                  onPressed: () {
                    context.go('/transactions');
                  },
                  child: Text(
                    'View all history →',
                    style: GoogleFonts.plusJakartaSans(
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
    ),
  ],
),
floatingActionButton: FloatingActionButton(
        heroTag: 'fab_home',
        onPressed: () => showAmountEntrySheet(context),
        tooltip: 'Add Transaction',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  List<TransactionRow> _visibleRecent(List<TransactionRow> rows) =>
      rows.take(_paging.visibleCount).toList();

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
            style: GoogleFonts.plusJakartaSans(
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
                onTap: () => showAddEditTransactionSheet(ctx,
                    editing: row.transaction,
                    toAccountId: row.transferPairAccount?.id),
                onEdit: () => showAddEditTransactionSheet(ctx,
                    editing: row.transaction,
                    toAccountId: row.transferPairAccount?.id),
                onDuplicate: () async {
                  await ref
                      .read(transactionsRepositoryProvider)
                      .duplicate(row.transaction);
                  if (!ctx.mounted) return;
                  showFeedbackSnackBar(ctx, 'Transaction duplicated');
                },
                onDelete: () => confirmAndDeleteTransaction(ctx, ref, row),
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

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

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
            onPressed: () => showUpdateSheet(
              context: context,
              currentVersion: info.version,
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
