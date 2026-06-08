import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/manage_providers.dart';
import '../../../state/reports_providers.dart';

class TopSpendsReport extends ConsumerWidget {
  const TopSpendsReport({
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
    final async = ref.watch(topSpendsProvider((from, to)));
    final catMap = {
      for (final c in ref.watch(categoriesStreamProvider).valueOrNull ?? [])
        c.id: c.name
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Top Spends', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(monthLabel, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (txs) {
          if (txs.isEmpty) {
            return Center(
              child: Text('No expenses in $monthLabel',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
            );
          }
          final maxAmt = txs.first.amount;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: txs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 56),
            itemBuilder: (ctx, i) {
              final tx = txs[i];
              final fraction =
                  maxAmt > 0 ? (tx.amount / maxAmt).clamp(0.0, 1.0) : 0.0;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.errorContainer,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
                title: Text(
                    catMap[tx.categoryId] ?? 'Expense',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tx.note.isNotEmpty)
                      Text(
                        tx.note,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      tx.transactionDate.substring(0, 10),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: fraction,
                      minHeight: 3,
                      color: cs.error,
                      backgroundColor: cs.error.withAlpha(20),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
                trailing: Text(
                  '₹${_fmt(tx.amount)}',
                  style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
