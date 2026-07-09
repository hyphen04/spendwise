import 'package:drift/drift.dart' as drift;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/db/app_database.dart';
import '../../../state/database_provider.dart';
import '../../../state/dues_providers.dart';
import '../../../app/utils/infinite_scroll.dart';
import '../../../app/widgets/load_more_button.dart';
import '../widgets/insight_card.dart';
import '../widgets/report_period_app_bar.dart';

enum Timeframe { month, year, all }

final contactStatementProvider = FutureProvider.family<List<DueEntry>, ({String contactId, String from, String to})>((ref, args) async {
  final db = ref.watch(appDatabaseProvider);
  // Watch entries/settlements so it updates
  ref.watch(unsettledEntriesProvider(args.contactId));
  ref.watch(settlementsProvider(args.contactId));

  final query = db.select(db.dueEntries)
    ..where((e) => e.contactId.equals(args.contactId));

  // Half-open range [from, to) — matches every other report in the app.
  // `isBetweenValues` would be inclusive on both ends and pull in entries
  // dated exactly on `to` (the first day of the next period).
  if (args.from.isNotEmpty && args.to.isNotEmpty) {
    query.where((e) =>
        e.entryDate.isBiggerOrEqualValue(args.from) &
        e.entryDate.isSmallerThanValue(args.to));
  }
  query.orderBy([(e) => drift.OrderingTerm.desc(e.entryDate)]);

  return query.get();
});

/// Carried-forward outstanding for a contact BEFORE the period starts.
/// `opening` = receivable(lent) − payable(borrowed) of all entries with
/// `entryDate < from`. For all-time (empty `from`) this is 0.
final contactStatementOpeningProvider =
    FutureProvider.family<double, ({String contactId, String from})>((ref, args) async {
  final db = ref.watch(appDatabaseProvider);
  ref.watch(unsettledEntriesProvider(args.contactId));
  ref.watch(settlementsProvider(args.contactId));

  final query = db.select(db.dueEntries)
    ..where((e) => e.contactId.equals(args.contactId));
  if (args.from.isNotEmpty) {
    query.where((e) => e.entryDate.isSmallerThanValue(args.from));
  }
  final prior = await query.get();
  double lent = 0, borrowed = 0;
  for (final e in prior) {
    if (e.direction == 'payable') {
      borrowed += e.amount;
    } else {
      lent += e.amount;
    }
  }
  return lent - borrowed;
});

class ContactStatementReport extends ConsumerStatefulWidget {
  const ContactStatementReport({super.key});

  @override
  ConsumerState<ContactStatementReport> createState() => _ContactStatementReportState();
}

class _ContactStatementReportState extends ConsumerState<ContactStatementReport> {
  String? _contactId;
  Timeframe _timeframe = Timeframe.month;
  late int _year;
  late int _month;
  final _paging = PagingState();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  void _prevPeriod() {
    setState(() {
      if (_timeframe == Timeframe.month) {
        if (_month == 1) {
          _month = 12;
          _year--;
        } else {
          _month--;
        }
      } else if (_timeframe == Timeframe.year) {
        _year--;
      }
      _paging.reset();
    });
  }

  void _nextPeriod() {
    setState(() {
      if (_timeframe == Timeframe.month) {
        if (_month == 12) {
          _month = 1;
          _year++;
        } else {
          _month++;
        }
      } else if (_timeframe == Timeframe.year) {
        _year++;
      }
      _paging.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contactsAsync = ref.watch(dueContactsStreamProvider);
    final contacts = (contactsAsync.valueOrNull ?? <DueContact>[])
        .where((c) => !c.isArchived)
        .toList();

    if (_contactId == null && contacts.isNotEmpty) {
      _contactId = contacts.first.id;
    }

    String periodLabel = '';
    String from = '';
    String to = '';

    if (_timeframe == Timeframe.month) {
      periodLabel = '${_months[_month - 1]} $_year';
      from = DateTime(_year, _month).toIso8601String();
      to = DateTime(_year, _month + 1).toIso8601String();
    } else if (_timeframe == Timeframe.year) {
      periodLabel = '$_year';
      from = DateTime(_year).toIso8601String();
      to = DateTime(_year + 1).toIso8601String();
    } else {
      periodLabel = 'All Time';
    }

    // Watch the entries here too so the parent can drive infinite scroll
    // (hasMore needs the total). Riverpod caches the family result, so the
    // body watching the same provider does not run a second query.
    final entriesTotal = _contactId == null
        ? 0
        : (ref.watch(contactStatementProvider(
                (contactId: _contactId!, from: from, to: to)))
            .valueOrNull
            ?.length ?? 0);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ReportPeriodAppBar(
        title: 'Contact Statement',
        subtitle: periodLabel,
        onPrevious: _prevPeriod,
        onNext: _nextPeriod,
        showNavigation: _timeframe != Timeframe.all,
      ),
      body: _contactId == null
          ? Center(
              child: Text(
                'No contacts',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                maybeLoadMore(
                  n,
                  hasMore: _paging.hasMore(entriesTotal),
                  onLoadMore: () => setState(_paging.loadMore),
                );
                return false;
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Period type selector
                  SegmentedButton<Timeframe>(
                    segments: const [
                      ButtonSegment(value: Timeframe.month, label: Text('Monthly')),
                      ButtonSegment(value: Timeframe.year, label: Text('Yearly')),
                      ButtonSegment(value: Timeframe.all, label: Text('All Time')),
                    ],
                    selected: {_timeframe},
                    onSelectionChanged: (s) => setState(() {
                      _timeframe = s.first;
                      _paging.reset();
                    }),
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),

                  // Contact picker
                  if (contacts.length > 1) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _contactId,
                      decoration: const InputDecoration(
                        labelText: 'Contact',
                        isDense: true,
                      ),
                      items: contacts
                          .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text('${c.icon} ${c.name}'),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _contactId = v;
                        _paging.reset();
                      }),
                    ),
                  ],

                  const SizedBox(height: 20),
                  _ContactStatementBody(
                    contactId: _contactId!,
                    from: from,
                    to: to,
                    timeframe: _timeframe,
                    paging: _paging,
                    entriesTotal: entriesTotal,
                    onLoadMore: () => setState(_paging.loadMore),
                  ),
                ],
              ),
            ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _ContactStatementBody extends ConsumerWidget {
  const _ContactStatementBody({
    required this.contactId,
    required this.from,
    required this.to,
    required this.timeframe,
    required this.paging,
    required this.entriesTotal,
    required this.onLoadMore,
  });
  final String contactId;
  final String from;
  final String to;
  final Timeframe timeframe;
  final PagingState paging;
  final int entriesTotal;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(contactStatementProvider((contactId: contactId, from: from, to: to)));
    final openingAsync = ref.watch(contactStatementOpeningProvider((contactId: contactId, from: from)));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (entries) {
        // Opening is the carried-forward outstanding from entries before the
        // period. For all-time (empty `from`) the provider returns 0.
        final opening = openingAsync.valueOrNull ?? 0.0;

        double lent = 0;
        double borrowed = 0;
        for (final e in entries) {
          if (e.direction == 'payable') {
            borrowed += e.amount;
          } else {
            lent += e.amount;
          }
        }
        // Closing reconciles with the card: Opening + Lent − Borrowed = Closing.
        final closing = opening + (lent - borrowed);
        // Outstanding this period (used by the net-balance card).
        final outstanding = closing;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatementSummaryCard(
              opening: opening,
              closing: closing,
              lent: lent,
              borrowed: borrowed,
            ),
            const SizedBox(height: 12),
            _NetBalanceCard(outstanding: outstanding),
            const SizedBox(height: 24),

            // Net flow chart
            const _SectionHeader('NET FLOW'),
            SizedBox(
              height: 220,
              child: _buildChart(entries, cs),
            ),
            InsightCard(
              text: _buildInsight(entries, lent, borrowed, outstanding),
            ),
            const SizedBox(height: 24),

            // Transactions list (paginated — summary/chart above use ALL entries)
            const _SectionHeader('TRANSACTIONS'),
            const SizedBox(height: 4),
            _TransactionsList(entries: entries.take(paging.visibleCount).toList()),
            if (paging.hasMore(entriesTotal))
              LoadMoreButton(
                showing: paging.visibleCount,
                total: entriesTotal,
                pageSize: paging.pageSize,
                onTap: onLoadMore,
              ),
          ],
        );
      },
    );
  }

  Widget _buildChart(List<DueEntry> entries, ColorScheme cs) {
    // Group by day if month, or month if year, or year for all-time
    final lentByBucket = <int, double>{};
    final borrowedByBucket = <int, double>{};
    int maxIndex = 0;
    int? minIndex;

    for (final e in entries) {
      final dt = DateTime.parse(e.entryDate);
      int index = 0;
      if (timeframe == Timeframe.month) {
        index = dt.day;
        maxIndex = 31;
        minIndex ??= 1;
      } else if (timeframe == Timeframe.year) {
        index = dt.month;
        maxIndex = 12;
        minIndex ??= 1;
      } else {
        index = dt.year;
        maxIndex = dt.year;
        minIndex = dt.year;
        if (dt.year > maxIndex) maxIndex = dt.year;
        if (dt.year < minIndex) minIndex = dt.year;
      }
      if (e.direction == 'payable') {
        borrowedByBucket[index] = (borrowedByBucket[index] ?? 0) + e.amount;
      } else {
        lentByBucket[index] = (lentByBucket[index] ?? 0) + e.amount;
      }
    }

    final lentSpots = <FlSpot>[];
    final borrowedSpots = <FlSpot>[];

    if (timeframe == Timeframe.all) {
      final keys = <int>{...lentByBucket.keys, ...borrowedByBucket.keys}.toList()..sort();
      int i = 0;
      for (final k in keys) {
        lentSpots.add(FlSpot(i.toDouble(), lentByBucket[k] ?? 0));
        borrowedSpots.add(FlSpot(i.toDouble(), borrowedByBucket[k] ?? 0));
        i++;
      }
    } else {
      for (int i = 1; i <= maxIndex; i++) {
        lentSpots.add(FlSpot(i.toDouble(), lentByBucket[i] ?? 0));
        borrowedSpots.add(FlSpot(i.toDouble(), borrowedByBucket[i] ?? 0));
      }
    }

    final maxVal = [
      ...lentSpots.map((s) => s.y),
      ...borrowedSpots.map((s) => s.y),
    ].fold<double>(0, (a, b) => a > b ? a : b);
    final yMax = maxVal > 0 ? maxVal * 1.2 : 1000.0;

    return LineChart(
      LineChartData(
        maxY: yMax,
        minY: 0,
        titlesData: const FlTitlesData(
          show: true,
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 5,
            ),
          ),
        ),
        gridData: FlGridData(
          horizontalInterval: yMax / 4,
          getDrawingHorizontalLine: (v) => FlLine(
            color: cs.outlineVariant.withAlpha(60),
            strokeWidth: 1,
          ),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: lentSpots,
            isCurved: true,
            color: const Color(0xFF16A34A),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF16A34A).withValues(alpha: 0.2),
            ),
          ),
          LineChartBarData(
            spots: borrowedSpots,
            isCurved: true,
            color: const Color(0xFFDC2626),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFFDC2626).withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  String _buildInsight(
    List<DueEntry> entries,
    double lent,
    double borrowed,
    double outstanding,
  ) {
    final txCount = entries.length;
    final ratio = lent + borrowed > 0 ? (lent / (lent + borrowed) * 100) : 0.0;
    final direction = outstanding > 0
        ? 'owes you'
        : (outstanding < 0 ? 'you owe them' : 'are settled up');
    return 'You had $txCount transactions with this contact in this period. '
        'Lent $ratio% of the total flow. '
        'Net, they $direction ₹${_fmt(outstanding.abs())}.';
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _StatementSummaryCard extends StatelessWidget {
  const _StatementSummaryCard({
    required this.opening,
    required this.closing,
    required this.lent,
    required this.borrowed,
  });
  final double opening;
  final double closing;
  final double lent;
  final double borrowed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _FlowRow(
            label: 'Opening Balance',
            amount: opening,
            color: cs.onSurfaceVariant,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          _FlowRow(
            label: 'Lent',
            amount: lent,
            color: const Color(0xFF16A34A),
            prefix: '+ ',
          ),
          const SizedBox(height: 12),
          _FlowRow(
            label: 'Borrowed',
            amount: borrowed,
            color: const Color(0xFFDC2626),
            prefix: '- ',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          _FlowRow(
            label: 'Closing Balance',
            amount: closing,
            color: cs.onSurface,
            isBold: true,
          ),
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.label,
    required this.amount,
    required this.color,
    this.prefix = '',
    this.isBold = false,
  });
  final String label;
  final double amount;
  final Color color;
  final String prefix;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: color,
            fontSize: isBold ? 15 : 14,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        Text(
          '$prefix₹${_fmt(amount)}',
          style: GoogleFonts.plusJakartaSans(
            color: color,
            fontSize: isBold ? 16 : 15,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _NetBalanceCard extends StatelessWidget {
  const _NetBalanceCard({required this.outstanding});
  final double outstanding;

  @override
  Widget build(BuildContext context) {
    final isPositive = outstanding >= 0;
    final color = isPositive
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);
    final prefix = outstanding > 0 ? '+' : (outstanding < 0 ? '−' : '');
    final label = isPositive
        ? 'They Owe You'
        : (outstanding < 0 ? 'You Owe Them' : 'Settled Up');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPositive
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            '$label: $prefix₹${_fmt(outstanding.abs())}',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _TransactionsList extends StatelessWidget {
  const _TransactionsList({required this.entries});
  final List<DueEntry> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      // Inset the inner list so the surrounding Column provides outer spacing
      // (we're already inside an outer ListView; this is the
      // shrink-wrapped-by-default builder case).
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (ctx, i) {
        final entry = entries[i];
        final isPayable = entry.direction == 'payable';
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: isPayable ? cs.errorContainer : cs.primaryContainer,
            child: Icon(
              isPayable ? Icons.call_received : Icons.call_made,
              size: 16,
              color: isPayable ? cs.error : cs.primary,
            ),
          ),
          title: Text(
            isPayable ? 'Borrowed' : 'Lent',
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: entry.note.isNotEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.note,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      entry.entryDate.substring(0, 10),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                )
              : Text(
                  entry.entryDate.substring(0, 10),
                  style: const TextStyle(fontSize: 12),
                ),
          trailing: Text(
            '${isPayable ? '-' : '+'}₹${_fmt(entry.amount)}',
            style: TextStyle(
              color: isPayable ? cs.error : cs.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
