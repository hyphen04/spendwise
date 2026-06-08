import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/themes/app_colors.dart';
import '../../app/widgets/screen_header.dart';
import '../../data/db/app_database.dart';
import '../../data/models/transaction_row.dart';
import '../../state/manage_providers.dart';
import '../../state/period_providers.dart';
import '../../state/transactions_providers.dart';
import 'sheets/add_edit_transaction_sheet.dart';
import 'sheets/transaction_detail_sheet.dart';
import 'widgets/transaction_tile.dart';

// ── Filter state ───────────────────────────────────────────────────────────────

enum _DateRange { all, today, week, month, quarter, year, lastMonth, lastQuarter, custom }

class _Filters {
  const _Filters({
    this.kind = 'all',
    this.dateRange = _DateRange.all,
    this.customFrom,
    this.customTo,
    this.categoryIds = const {},
    this.accountIds = const {},
    this.minAmount,
    this.maxAmount,
  });

  final String kind;
  final _DateRange dateRange;
  final DateTime? customFrom;
  final DateTime? customTo;
  final Set<String> categoryIds;
  final Set<String> accountIds;
  final double? minAmount;
  final double? maxAmount;

  bool get hasActiveFilters =>
      kind != 'all' ||
      dateRange != _DateRange.all ||
      categoryIds.isNotEmpty ||
      accountIds.isNotEmpty ||
      minAmount != null ||
      maxAmount != null;

  int get activeCount {
    var n = 0;
    if (kind != 'all') n++;
    if (dateRange != _DateRange.all) n++;
    if (categoryIds.isNotEmpty) n++;
    if (accountIds.isNotEmpty) n++;
    if (minAmount != null || maxAmount != null) n++;
    return n;
  }

  _Filters copyWith({
    String? kind,
    _DateRange? dateRange,
    DateTime? customFrom,
    DateTime? customTo,
    bool clearCustom = false,
    Set<String>? categoryIds,
    Set<String>? accountIds,
    double? minAmount,
    double? maxAmount,
    bool clearMin = false,
    bool clearMax = false,
  }) =>
      _Filters(
        kind: kind ?? this.kind,
        dateRange: dateRange ?? this.dateRange,
        customFrom: clearCustom ? null : (customFrom ?? this.customFrom),
        customTo: clearCustom ? null : (customTo ?? this.customTo),
        categoryIds: categoryIds ?? this.categoryIds,
        accountIds: accountIds ?? this.accountIds,
        minAmount: clearMin ? null : (minAmount ?? this.minAmount),
        maxAmount: clearMax ? null : (maxAmount ?? this.maxAmount),
      );
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  _Filters _filters = const _Filters();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _visibleCount = 20;

  static const _pageSize = 20;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<TransactionRow> _apply(List<TransactionRow> rows) {
    var out = rows;

    if (_filters.kind != 'all') {
      out = out.where((r) => r.transaction.kind == _filters.kind).toList();
    }

    if (_filters.dateRange != _DateRange.all) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      DateTime from = DateTime(2000);
      DateTime? to;
      switch (_filters.dateRange) {
        case _DateRange.today:
          from = today;
          break;
        case _DateRange.week:
          from = today.subtract(Duration(days: today.weekday - 1));
          break;
        case _DateRange.month:
          from = DateTime(now.year, now.month, 1);
          break;
        case _DateRange.quarter:
          from = DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
          break;
        case _DateRange.year:
          from = DateTime(now.year, 1, 1);
          break;
        case _DateRange.lastMonth:
          final lastM = DateTime(now.year, now.month - 1);
          from = DateTime(lastM.year, lastM.month, 1);
          to = DateTime(now.year, now.month, 1);
          break;
        case _DateRange.lastQuarter:
          final qStart = ((now.month - 1) ~/ 3) * 3 + 1;
          final prevQFirst = DateTime(now.year, qStart - 3, 1);
          from = prevQFirst;
          to = DateTime(now.year, qStart, 1);
          break;
        case _DateRange.custom:
          from = _filters.customFrom ?? DateTime(2000);
          final customEnd = _filters.customTo;
          to = customEnd != null
              ? DateTime(customEnd.year, customEnd.month, customEnd.day + 1)
              : null;
          break;
        default:
          from = DateTime(2000);
      }
      out = out.where((r) {
        final d = DateTime.tryParse(r.transaction.transactionDate);
        if (d == null) return false;
        if (d.isBefore(from)) return false;
        if (to != null && !d.isBefore(to)) return false;
        return true;
      }).toList();
    }

    if (_filters.categoryIds.isNotEmpty) {
      out = out
          .where((r) => _filters.categoryIds.contains(r.transaction.categoryId))
          .toList();
    }

    if (_filters.accountIds.isNotEmpty) {
      out = out
          .where((r) => _filters.accountIds.contains(r.transaction.accountId))
          .toList();
    }

    if (_filters.minAmount != null) {
      out = out.where((r) => r.transaction.amount >= _filters.minAmount!).toList();
    }
    if (_filters.maxAmount != null) {
      out = out.where((r) => r.transaction.amount <= _filters.maxAmount!).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      out = out
          .where((r) =>
              r.transaction.note.toLowerCase().contains(q) ||
              r.categoryName.toLowerCase().contains(q) ||
              r.accountName.toLowerCase().contains(q))
          .toList();
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<({DateTime from, DateTime to})?>(
      pendingTransactionsFilterProvider,
      (_, next) {
        if (next != null) {
          ref.read(pendingTransactionsFilterProvider.notifier).state = null;
          setState(() {
            _filters = _Filters(
              dateRange: _DateRange.custom,
              customFrom: next.from,
              customTo: next.to,
            );
            _visibleCount = _pageSize;
          });
        }
      },
    );

    final rowsAsync = ref.watch(transactionRowsProvider);
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: cs.surface,
      body: rowsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          final filtered = _apply(rows);
          final totals = _totals(filtered);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Fixed header: title + count + filter + search ────────
              _Header(
                count: filtered.length,
                filterCount: _filters.activeCount,
                onFilter: () => _showFilterSheet(context, rows),
                searchCtrl: _searchCtrl,
                onQueryChanged: (v) => setState(() {
                  _searchQuery = v;
                  _visibleCount = _pageSize;
                }),
              ).animate().fadeIn(duration: 220.ms),

              // ── Scrollable content ───────────────────────────────────
              Expanded(child: CustomScrollView(
            slivers: [

              // ── Inline stats ─────────────────────────────────────────
              if (filtered.isNotEmpty)
                SliverToBoxAdapter(
                  child: _StatsRow(totals: totals, appColors: appColors),
                ),

              // ── Active filter chips ──────────────────────────────────
              if (_filters.hasActiveFilters)
                SliverToBoxAdapter(
                  child: _ActiveFilterChips(
                    filters: _filters,
                    onClear: () => setState(() {
                      _filters = const _Filters();
                      _visibleCount = _pageSize;
                    }),
                  ),
                ),

              // ── List / empty state ───────────────────────────────────
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    hasFilter: _filters.hasActiveFilters || _searchQuery.isNotEmpty,
                    onAdd: () => showAddEditTransactionSheet(context),
                    onClear: () => setState(() => _filters = const _Filters()),
                  ),
                )
              else
                ..._groupedSlivers(filtered, cs),

              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 96),
              ),
            ],
          )),
          ],
        );
        },
      ),
    );
  }

  List<Widget> _groupedSlivers(List<TransactionRow> rows, ColorScheme cs) {
    // Paginate first, then group — so groups are never split across pages.
    final visible = rows.take(_visibleCount).toList();
    final hasMore = _visibleCount < rows.length;

    final groups = <String, List<TransactionRow>>{};
    for (final row in visible) {
      final key = row.transaction.transactionDate.substring(0, 10);
      groups.putIfAbsent(key, () => []).add(row);
    }

    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final slivers = <Widget>[];
    for (final dateKey in sortedKeys) {
      final list = groups[dateKey]!;
      final dt = _totals(list);
      slivers.add(SliverToBoxAdapter(
        child: _GroupHeader(
          label: _humanDate(dateKey),
          expense: dt.expense,
          income: dt.income,
        ),
      ));
      slivers.add(
        SliverList.builder(
          itemCount: list.length,
          itemBuilder: (ctx, i) {
            final row = list[i];
            return TransactionTile(
              row: row,
              onTap: () => showTransactionDetailSheet(ctx, row: row),
              onEdit: () =>
                  showAddEditTransactionSheet(ctx, editing: row.transaction),
              onDuplicate: () => ref
                  .read(transactionsRepositoryProvider)
                  .duplicate(row.transaction),
              onDelete: () => _confirmDelete(ctx, row),
            )
                .animate(delay: Duration(milliseconds: i * 18))
                .fadeIn(duration: 180.ms)
                .slideX(begin: -0.015, end: 0);
          },
        ),
      );
    }

    if (hasMore) {
      slivers.add(SliverToBoxAdapter(
        child: _LoadMoreButton(
          showing: _visibleCount,
          total: rows.length,
          onTap: () => setState(() => _visibleCount += _pageSize),
        ),
      ));
    }

    return slivers;
  }

  Future<void> _showFilterSheet(
      BuildContext context, List<TransactionRow> rows) async {
    final cats = ref.read(categoriesStreamProvider).valueOrNull ?? [];
    final accs = ref.read(accountsStreamProvider).valueOrNull ?? [];

    final result = await showModalBottomSheet<_Filters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        initial: _filters,
        categories: cats,
        accounts: accs,
      ),
    );
    if (result != null) {
      setState(() {
        _filters = result;
        _visibleCount = _pageSize;
      });
    }
  }

  Future<void> _confirmDelete(BuildContext ctx, TransactionRow row) async {
    final cs = Theme.of(ctx).colorScheme;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: Text(row.transaction.kind == 'transfer'
            ? 'Delete both legs of this transfer?'
            : 'Permanently delete this transaction?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(transactionsRepositoryProvider)
          .delete(row.transaction.id);
    }
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.filterCount,
    required this.onFilter,
    required this.searchCtrl,
    required this.onQueryChanged,
  });

  final int count;
  final int filterCount;
  final VoidCallback onFilter;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ScreenHeader(
      title: 'transactions',
      subtitle: count == 0
          ? 'No transactions'
          : '$count transaction${count == 1 ? '' : 's'}',
      bottom: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: searchCtrl,
                onChanged: onQueryChanged,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search transactions…',
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: cs.onSurfaceVariant),
                  prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          HeaderIconButton(
            icon: Icons.tune_rounded,
            onTap: onFilter,
            tooltip: 'Filters',
            badge: filterCount,
          ),
        ],
      ),
    );
  }
}

// ── Inline stats row ───────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.totals, required this.appColors});
  final _Totals totals;
  final AppColors appColors;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final netColor = totals.net >= 0 ? appColors.income : appColors.expense;
    final netPrefix = totals.net > 0 ? '+' : (totals.net < 0 ? '−' : '');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Row(
        children: [
          _InlineStat(
            arrow: '↑',
            value: totals.income,
            color: appColors.income,
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            width: 1,
            height: 14,
            color: cs.outlineVariant,
          ),
          _InlineStat(
            arrow: '↓',
            value: totals.expense,
            color: appColors.expense,
          ),
          const Spacer(),
          Text(
            '$netPrefix₹${_fmt(totals.net.abs())}',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: netColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'net',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({
    required this.arrow,
    required this.value,
    required this.color,
  });
  final String arrow;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          arrow,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '₹${_fmt(value)}',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ── Active filter chips ────────────────────────────────────────────────────────

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.filters, required this.onClear});
  final _Filters filters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <String>[];
    if (filters.kind != 'all') chips.add(_kindLabel(filters.kind));
    if (filters.dateRange != _DateRange.all) {
      if (filters.dateRange == _DateRange.custom && filters.customFrom != null) {
        chips.add(
            '${_shortDate(filters.customFrom!)} – ${_shortDate(filters.customTo ?? filters.customFrom!)}');
      } else {
        chips.add(_dateRangeLabel(filters.dateRange));
      }
    }
    if (filters.categoryIds.isNotEmpty) {
      chips.add(
          '${filters.categoryIds.length} categor${filters.categoryIds.length == 1 ? 'y' : 'ies'}');
    }
    if (filters.accountIds.isNotEmpty) {
      chips.add(
          '${filters.accountIds.length} account${filters.accountIds.length == 1 ? '' : 's'}');
    }
    if (filters.minAmount != null || filters.maxAmount != null) {
      chips.add('Amount range');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: chips.map((label) {
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: Text(
              'Clear',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Group header ───────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.expense,
    required this.income,
  });
  final String label;
  final double expense;
  final double income;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (income > 0)
            Text(
              '+₹${_fmt(income)}',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: appColors.income,
              ),
            ),
          if (income > 0 && expense > 0)
            Text('  ·  ',
                style: TextStyle(color: cs.outlineVariant, fontSize: 12)),
          if (expense > 0)
            Text(
              '−₹${_fmt(expense)}',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: appColors.expense,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Load more button ───────────────────────────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.showing,
    required this.total,
    required this.onTap,
  });
  final int showing;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining = total - showing;
    final loadNext = remaining > 20 ? 20 : remaining;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outlineVariant),
          minimumSize: const Size(double.infinity, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        child: Text('Load $loadNext more  ·  $remaining remaining'),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasFilter,
    required this.onAdd,
    required this.onClear,
  });
  final bool hasFilter;
  final VoidCallback onAdd;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilter
                  ? Icons.filter_list_off_rounded
                  : Icons.receipt_long_rounded,
              size: 48,
              color: cs.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter ? 'No results' : 'No transactions yet',
              style: GoogleFonts.manrope(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilter
                  ? 'Nothing matches your current filters.'
                  : 'Your transactions will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (hasFilter)
              OutlinedButton(
                onPressed: onClear,
                child: const Text('Clear filters'),
              )
            else
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add transaction'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Filter sheet ───────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.categories,
    required this.accounts,
  });

  final _Filters initial;
  final List<Category> categories;
  final List<Account> accounts;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _Filters _f;
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _f = widget.initial;
    if (_f.minAmount != null) _minCtrl.text = _f.minAmount!.toStringAsFixed(0);
    if (_f.maxAmount != null) _maxCtrl.text = _f.maxAmount!.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _f.customFrom != null && _f.customTo != null
          ? DateTimeRange(start: _f.customFrom!, end: _f.customTo!)
          : null,
    );
    if (!mounted || range == null) return;
    setState(() => _f = _f.copyWith(
          dateRange: _DateRange.custom,
          customFrom: range.start,
          customTo: range.end,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      'Filters',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (_f.hasActiveFilters)
                      TextButton(
                        onPressed: () => setState(() {
                          _f = const _Filters();
                          _minCtrl.clear();
                          _maxCtrl.clear();
                        }),
                        child: const Text('Reset all'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _Section(label: 'Type'),
                    const SizedBox(height: 10),
                    _KindRow(
                      selected: _f.kind,
                      onChanged: (v) =>
                          setState(() => _f = _f.copyWith(kind: v)),
                    ),
                    const SizedBox(height: 20),
                    _Section(label: 'Date range'),
                    const SizedBox(height: 10),
                    _DateRangeGrid(
                      selected: _f.dateRange,
                      onChanged: (v) =>
                          setState(() => _f = _f.copyWith(dateRange: v)),
                      onCustomTap: _pickCustomRange,
                      customLabel: _f.dateRange == _DateRange.custom &&
                              _f.customFrom != null
                          ? '${_shortDate(_f.customFrom!)} – ${_shortDate(_f.customTo ?? _f.customFrom!)}'
                          : null,
                    ),
                    if (widget.categories.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _Section(label: 'Categories'),
                      const SizedBox(height: 10),
                      _MultiSelect<Category>(
                        items: widget.categories,
                        selected: _f.categoryIds,
                        labelOf: (c) => c.name,
                        iconOf: (c) => c.icon,
                        idOf: (c) => c.id,
                        onChanged: (ids) =>
                            setState(() => _f = _f.copyWith(categoryIds: ids)),
                      ),
                    ],
                    if (widget.accounts.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _Section(label: 'Accounts'),
                      const SizedBox(height: 10),
                      _MultiSelect<Account>(
                        items: widget.accounts,
                        selected: _f.accountIds,
                        labelOf: (a) => a.name,
                        iconOf: (a) => a.icon,
                        idOf: (a) => a.id,
                        onChanged: (ids) =>
                            setState(() => _f = _f.copyWith(accountIds: ids)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _Section(label: 'Amount range'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _AmountField(
                            ctrl: _minCtrl,
                            hint: 'Min (₹)',
                            onChanged: (v) => setState(() => _f = v == null
                                ? _f.copyWith(clearMin: true)
                                : _f.copyWith(minAmount: v)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AmountField(
                            ctrl: _maxCtrl,
                            hint: 'Max (₹)',
                            onChanged: (v) => setState(() => _f = v == null
                                ? _f.copyWith(clearMax: true)
                                : _f.copyWith(maxAmount: v)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, MediaQuery.paddingOf(context).bottom + 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _f),
                    child: const Text('Apply filters'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Filter sheet sub-widgets ───────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('all', 'All', Icons.all_inclusive_rounded),
      ('expense', 'Expense', Icons.arrow_downward_rounded),
      ('income', 'Income', Icons.arrow_upward_rounded),
      ('transfer', 'Transfer', Icons.swap_horiz_rounded),
    ];
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: options.map((opt) {
        final (value, label, icon) = opt;
        final active = value == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? cs.primary : cs.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 18,
                      color: active ? cs.onPrimary : cs.onSurfaceVariant),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: active ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DateRangeGrid extends StatelessWidget {
  const _DateRangeGrid({
    required this.selected,
    required this.onChanged,
    required this.onCustomTap,
    this.customLabel,
  });
  final _DateRange selected;
  final ValueChanged<_DateRange> onChanged;
  final VoidCallback onCustomTap;
  final String? customLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final opts = [
      (_DateRange.today, 'Today'),
      (_DateRange.week, 'This week'),
      (_DateRange.month, 'This month'),
      (_DateRange.lastMonth, 'Last month'),
      (_DateRange.quarter, 'This quarter'),
      (_DateRange.lastQuarter, 'Last quarter'),
      (_DateRange.year, 'This year'),
      (_DateRange.all, 'All time'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...opts.map((opt) {
          final (value, label) = opt;
          final active = value == selected;
          return GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? cs.primary : cs.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ),
          );
        }),
        GestureDetector(
          onTap: onCustomTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected == _DateRange.custom
                  ? cs.primary
                  : cs.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              customLabel ?? 'Custom…',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected == _DateRange.custom
                    ? cs.onPrimary
                    : cs.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MultiSelect<T> extends StatelessWidget {
  const _MultiSelect({
    required this.items,
    required this.selected,
    required this.labelOf,
    required this.iconOf,
    required this.idOf,
    required this.onChanged,
  });

  final List<T> items;
  final Set<String> selected;
  final String Function(T) labelOf;
  final String Function(T) iconOf;
  final String Function(T) idOf;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final id = idOf(item);
        final active = selected.contains(id);
        return GestureDetector(
          onTap: () {
            final next = Set<String>.from(selected);
            if (active) {
              next.remove(id);
            } else {
              next.add(id);
            }
            onChanged(next);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: active ? cs.primary : cs.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: active
                  ? null
                  : Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(iconOf(item), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  labelOf(item),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: active ? cs.onPrimary : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.ctrl,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController ctrl;
  final String hint;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        filled: true,
        fillColor: cs.surfaceContainer,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      style: GoogleFonts.inter(fontSize: 13),
      onChanged: (v) => onChanged(v.isEmpty ? null : double.tryParse(v)),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _Totals {
  const _Totals(this.income, this.expense);
  final double income;
  final double expense;
  double get net => income - expense;
}

_Totals _totals(List<TransactionRow> rows) {
  double inc = 0, exp = 0;
  for (final r in rows) {
    switch (r.transaction.kind) {
      case 'income':
        inc += r.transaction.amount;
        break;
      case 'expense':
        exp += r.transaction.amount;
        break;
    }
  }
  return _Totals(inc, exp);
}

String _kindLabel(String kind) => switch (kind) {
      'expense' => 'Expense',
      'income' => 'Income',
      'transfer' => 'Transfer',
      _ => 'All',
    };

String _dateRangeLabel(_DateRange r) => switch (r) {
      _DateRange.today => 'Today',
      _DateRange.week => 'This week',
      _DateRange.month => 'This month',
      _DateRange.quarter => 'This quarter',
      _DateRange.year => 'This year',
      _DateRange.lastMonth => 'Last month',
      _DateRange.lastQuarter => 'Last quarter',
      _DateRange.custom => 'Custom range',
      _ => 'All time',
    };

String _shortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _humanDate(String dateKey) {
  try {
    final dt = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return '${dt.day} ${_months[dt.month - 1]}, ${dt.year}';
  } catch (_) {
    return dateKey;
  }
}

String _fmt(double v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
