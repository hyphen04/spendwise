import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/themes/app_colors.dart';
import '../../app/themes/app_fonts.dart';
import '../../app/utils/infinite_scroll.dart';
import '../../app/utils/money_format.dart';
import '../../app/widgets/load_more_button.dart';
import '../../data/models/transaction_row.dart';
import '../../state/app_mode_providers.dart';
import '../../state/home_providers.dart';
import '../../state/period_providers.dart';
import '../../state/reports_providers.dart';
import '../../state/transactions_providers.dart';

import '../../services/update_service.dart';
import '../../state/update_provider.dart';
import '../../app/utils/feedback.dart';
import '../search/search_sheet.dart';
import '../settings/update_sheet.dart';
import '../transactions/sheets/add_edit_transaction_sheet.dart';
import '../transactions/sheets/amount_entry_sheet.dart';
import '../transactions/transaction_actions.dart';
import '../transactions/widgets/transaction_tile.dart';
import 'widgets/home_bills_card.dart';
import 'widgets/home_quick_add_rail.dart';
import 'widgets/home_quick_dues_card.dart';
import 'widgets/home_spent_hero_card.dart';
import 'widgets/home_where_it_went_card.dart';
import 'widgets/month_nav.dart';


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
    final appColors = Theme.of(context).extension<AppColors>()!;

    // The whole Home reflects the shared selected period (MonthNav writes it).
    final period = ref.watch(selectedPeriodProvider);

    // Month-scoped enriched rows for the selected period (recent activity).
    final monthRows =
        ref.watch(monthTransactionRowsProvider((period.year, period.month)));
    final visibleRows = monthRows.take(_paging.visibleCount).toList();

    // Any-history flag for the empty state (rolling 6-month series).
    final hasAnyHistory =
        ref.watch(cashFlowProvider).valueOrNull?.isNotEmpty ?? false;

    final topPad = MediaQuery.paddingOf(context).top;
    final botPad = MediaQuery.paddingOf(context).bottom;

    final pendingUpdate = ref.watch(pendingUpdateProvider);
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Fixed header: wordmark + greeting + month nav + search ──────
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPad + 16, 12, 8),
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
                            style: spaceGrotesk(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface,
                              height: 1.0,
                              letterSpacing: -0.5,
                            ),
                          ),
                          TextSpan(
                            text: 'wise',
                            style: spaceGrotesk(
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
                      style: plusJakartaSans(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                MonthNav(),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  color: cs.onSurfaceVariant,
                  onPressed: () => showSearchSheet(context),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 250.ms),

          // ── Scrollable content ─────────────────────────────────────────────
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                maybeLoadMore(
                  n,
                  hasMore: _paging.visibleCount < monthRows.length,
                  onLoadMore: () => setState(_paging.loadMore),
                );
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  // ── Update banner (scrolls with content) ──────────────────
                  // Hidden in Offline mode (update checks don't run offline).
                  if (pendingUpdate != null && isOnline)
                    SliverToBoxAdapter(child: _UpdateBanner(pendingUpdate)),

                  // ── 1. Spent hero (this month + budget bar + forecast + net worth) ──
                  const SliverToBoxAdapter(child: HomeSpentHeroCard()),

                  // ── 2. Quick-add rail (most-used category chips) ───────────
                  const SliverToBoxAdapter(child: HomeQuickAddRail()),

                  // ── 3. Quick dues (restored; hidden when no due contacts) ──
                  const SliverToBoxAdapter(child: HomeQuickDuesCard()),

                  // ── 4. Upcoming bills (hidden if none) ─────────────────────
                  const SliverToBoxAdapter(child: HomeBillsCard()),

                  // ── 5. Where it went (top categories; hidden if no spend) ──
                  const SliverToBoxAdapter(child: HomeWhereItWentCard()),

                  // ── 6. "Recent activity" header ───────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                      child: Text(
                        'recent activity',
                        style: plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),

                  // ── 7. Transaction list (date-grouped, with per-day totals) ─
                  if (monthRows.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                        child: _EmptyState(
                          hasAnyHistory: hasAnyHistory,
                          cs: cs,
                        ),
                      ),
                    )
                  else ...[
                    ..._buildDateGroups(visibleRows, cs, appColors, ref),
                    if (_paging.hasMore(monthRows.length))
                      SliverToBoxAdapter(
                        child: LoadMoreButton(
                          showing: _paging.visibleCount,
                          total: monthRows.length,
                          pageSize: _paging.pageSize,
                          onTap: () => setState(_paging.loadMore),
                        ),
                      ),
                  ],

                  // ── "View all" button ──────────────────────────────────────
                  if (monthRows.isNotEmpty || hasAnyHistory)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: TextButton(
                          onPressed: () => context.go('/transactions'),
                          child: Text(
                            'View all history →',
                            style: plusJakartaSans(
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

  List<Widget> _buildDateGroups(
    List<TransactionRow> rows,
    ColorScheme cs,
    AppColors appColors,
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
      // Per-day net (income − expense) shown beside the date header.
      double dayNet = 0;
      for (final r in list) {
        if (r.transaction.kind == 'income') {
          dayNet += r.transaction.amount;
        } else if (r.transaction.kind == 'expense' ||
            r.transaction.kind == 'transfer_out') {
          dayNet -= r.transaction.amount;
        }
      }

      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            children: [
              Text(
                _humanDate(dateKey),
                style: plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (dayNet != 0)
                Text(
                  '${dayNet > 0 ? '+' : '−'}₹${fmtGrouped(dayNet.abs())}',
                  style: plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: dayNet > 0 ? appColors.income : appColors.expense,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
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

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAnyHistory, required this.cs});
  final bool hasAnyHistory;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hasAnyHistory ? 'No activity this month' : 'Welcome to SpendWise!',
          style: plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasAnyHistory
              ? 'Tap + to add one, or view all history →'
              : 'Tap + to add your first transaction.',
          style: plusJakartaSans(fontSize: 14, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
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