import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/reports_providers.dart';

class TagReportReport extends ConsumerWidget {
  const TagReportReport({
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
    final async = ref.watch(tagBreakdownProvider((from, to)));

    return Scaffold(
      appBar: AppBar(title: Text('Tag Report — $monthLabel')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tags) {
          if (tags.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🏷️', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  Text('No tagged transactions in $monthLabel',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                          )),
                ],
              ),
            );
          }
          final total = tags.fold<double>(0, (s, t) => s + t.total);
          final maxAmt = tags.first.total;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total tagged expenses',
                        style: Theme.of(context).textTheme.bodyMedium),
                    Text('₹${_fmt(total)}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...tags.map((tag) {
                final fraction = maxAmt > 0
                    ? (tag.total / maxAmt).clamp(0.0, 1.0)
                    : 0.0;
                final pct = total > 0 ? tag.total / total * 100 : 0.0;
                final tagColor = _hexToColor(tag.color);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: tagColor.withAlpha(24),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: tagColor.withAlpha(60)),
                            ),
                            child: Text(
                              tag.name,
                              style: TextStyle(
                                  color: tagColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '₹${_fmt(tag.total)}  ${pct.toStringAsFixed(1)}%',
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: fraction,
                        minHeight: 5,
                        color: tagColor,
                        backgroundColor: tagColor.withAlpha(24),
                        borderRadius: BorderRadius.circular(3),
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

  static Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
