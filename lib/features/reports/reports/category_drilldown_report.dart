import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/reports_providers.dart';

class CategoryDrilldownReport extends ConsumerWidget {
  const CategoryDrilldownReport({
    super.key,
    required this.from,
    required this.to,
    required this.monthLabel,
  });
  final String from;
  final String to;
  final String monthLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(categoryBreakdownProvider((from, to)));

    return Scaffold(
      appBar: AppBar(title: Text('Categories — $monthLabel')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cats) {
          if (cats.isEmpty) {
            return Center(
              child: Text('No expense categories in $monthLabel',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
            );
          }
          final total = cats.fold<double>(0, (s, c) => s + c.total);
          final palette = _palette(cats.length);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Pie chart
              SizedBox(
                height: 220,
                child: PieChart(
                  PieChartData(
                    sections: cats.asMap().entries.map((e) {
                      final pct = total > 0 ? e.value.total / total : 0.0;
                      return PieChartSectionData(
                        value: e.value.total,
                        color: palette[e.key % palette.length],
                        radius: 80,
                        title: pct > 0.05
                            ? '${(pct * 100).toStringAsFixed(0)}%'
                            : '',
                        titleStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.surface),
                      );
                    }).toList(),
                    sectionsSpace: 2,
                    centerSpaceRadius: 48,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Ranked list
              ...cats.asMap().entries.map((e) {
                final cat = e.value;
                final pct = total > 0 ? cat.total / total : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: palette[e.key % palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(cat.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(cat.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                Text(
                                  '₹${_fmt(cat.total)}  ${(pct * 100).toStringAsFixed(1)}%',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: pct,
                              minHeight: 4,
                              color: palette[e.key % palette.length],
                              backgroundColor: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  // Grayscale ramp: near-black → light gray, fully monochrome.
  static List<Color> _palette(int count) {
    final n = count < 1 ? 1 : count;
    return List.generate(n, (i) {
      // Spread from 0x18 (near-black) to 0xCC (light gray)
      final t = n == 1 ? 0.0 : i / (n - 1);
      final v = (0x18 + (0xCC - 0x18) * t).round();
      return Color.fromARGB(255, v, v, v);
    });
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
