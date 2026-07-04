import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:drift/drift.dart' as drift;
import '../../../data/db/app_database.dart';
import '../../../state/database_provider.dart';
import '../../../state/dues_providers.dart';
import '../widgets/report_period_app_bar.dart';

enum Timeframe { month, year, all }

final contactStatementProvider = FutureProvider.family<List<DueEntry>, ({String contactId, String from, String to})>((ref, args) async {
  final db = ref.watch(appDatabaseProvider);
  // Watch entries/settlements so it updates
  ref.watch(unsettledEntriesProvider(args.contactId));
  ref.watch(settlementsProvider(args.contactId));

  final query = db.select(db.dueEntries)
    ..where((e) => e.contactId.equals(args.contactId));
  
  if (args.from.isNotEmpty && args.to.isNotEmpty) {
    query.where((e) => e.entryDate.isBetweenValues(args.from, args.to));
  }
  query.orderBy([(e) => drift.OrderingTerm.desc(e.entryDate)]);
  
  return query.get();
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

    return Scaffold(
      appBar: ReportPeriodAppBar(
        title: 'Contact Statement',
        subtitle: periodLabel,
        onPrevious: _prevPeriod,
        onNext: _nextPeriod,
        showNavigation: _timeframe != Timeframe.all,
      ),
      body: Column(
        children: [
          // Period Type Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: SegmentedButton<Timeframe>(
              segments: const [
                ButtonSegment(value: Timeframe.month, label: Text('Monthly')),
                ButtonSegment(value: Timeframe.year, label: Text('Yearly')),
                ButtonSegment(value: Timeframe.all, label: Text('All Time')),
              ],
              selected: {_timeframe},
              onSelectionChanged: (s) => setState(() => _timeframe = s.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          // Contact picker
          if (contacts.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: _contactId,
                decoration: const InputDecoration(labelText: 'Contact', isDense: true),
                items: contacts
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.icon} ${c.name}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _contactId = v),
              ),
            ),
          const SizedBox(height: 12),
          if (_contactId == null)
            Expanded(
              child: Center(
                child: Text('No contacts', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            Expanded(
              child: _ContactStatementList(
                contactId: _contactId!,
                from: from,
                to: to,
                timeframe: _timeframe,
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

class _ContactStatementList extends ConsumerWidget {
  const _ContactStatementList({
    required this.contactId,
    required this.from,
    required this.to,
    required this.timeframe,
  });
  final String contactId;
  final String from;
  final String to;
  final Timeframe timeframe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(contactStatementProvider((contactId: contactId, from: from, to: to)));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Text('No transactions in this period',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    )),
          );
        }

        double borrowed = 0;
        double lent = 0;
        for (final e in entries) {
          if (e.direction == 'payable') {
            borrowed += e.amount;
          } else {
            lent += e.amount;
          }
        }

        return Column(
          children: [
            // Summary Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lent', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          Text('₹${_fmt(lent)}', style: TextStyle(color: cs.primary, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Orbitron')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Borrowed', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          Text('₹${_fmt(borrowed)}', style: TextStyle(color: cs.error, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Orbitron')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Graph
            SizedBox(
              height: 150,
              child: _buildChart(entries, cs),
            ),
            const SizedBox(height: 16),
            
            const Divider(height: 1),
            // List
            Expanded(
              child: ListView.separated(
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
                    title: Text(isPayable ? 'Borrowed' : 'Lent', style: const TextStyle(fontSize: 14)),
                    subtitle: entry.note.isNotEmpty
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(entry.note, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(entry.entryDate.substring(0, 10), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                            ],
                          )
                        : Text(entry.entryDate.substring(0, 10), style: const TextStyle(fontSize: 12)),
                    trailing: Text(
                      '₹${_fmt(entry.amount)}',
                      style: TextStyle(
                          color: isPayable ? cs.error : cs.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChart(List<DueEntry> entries, ColorScheme cs) {
    if (entries.isEmpty) return const SizedBox();

    // Group by day if month, or month if year
    final map = <int, double>{}; // index -> net amount (lent - borrowed)
    int maxIndex = 0;

    for (final e in entries) {
      final dt = DateTime.parse(e.entryDate);
      int index = 0;
      if (timeframe == Timeframe.month) {
        index = dt.day;
        maxIndex = 31;
      } else if (timeframe == Timeframe.year) {
        index = dt.month;
        maxIndex = 12;
      } else {
        index = dt.year;
        if (maxIndex == 0) maxIndex = dt.year;
        if (dt.year > maxIndex) maxIndex = dt.year;
      }
      
      final current = map[index] ?? 0.0;
      map[index] = current + (e.direction == 'payable' ? -e.amount : e.amount);
    }

    final spots = <FlSpot>[];
    if (timeframe == Timeframe.all) {
      final years = map.keys.toList()..sort();
      int i = 0;
      for (final y in years) {
        spots.add(FlSpot(i.toDouble(), map[y]!));
        i++;
      }
    } else {
      for (int i = 1; i <= maxIndex; i++) {
        spots.add(FlSpot(i.toDouble(), map[i] ?? 0.0));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(right: 16.0, left: 8.0),
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: cs.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: cs.primary.withAlpha(30),
              ),
            ),
          ],
          titlesData: const FlTitlesData(
            show: true,
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 5,
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
