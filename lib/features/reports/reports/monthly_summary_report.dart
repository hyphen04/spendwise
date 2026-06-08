import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/reports_providers.dart';

class MonthlySummaryReport extends ConsumerWidget {
  const MonthlySummaryReport({super.key, required this.year, required this.month});
  final int year;
  final int month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(monthlySummaryProvider((year, month)));
    final monthLabel = '${_months[month - 1]} $year';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Monthly Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(monthLabel, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Stat cards
            Row(
              children: [
                _StatCard(label: 'Income', amount: s.income, color: Theme.of(context).colorScheme.onSurface),
                const SizedBox(width: 12),
                _StatCard(label: 'Expense', amount: s.expense, color: Theme.of(context).colorScheme.error),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Net savings',
                      style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    '${s.net >= 0 ? '+' : ''}₹${_fmt(s.net)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: s.net >= 0
                              ? Theme.of(context).colorScheme.onSurface
                              : cs.error,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),

            if (s.biggestSpendTitle != null && s.biggestSpendAmount != null) ...[
              const SizedBox(height: 16),
              _SectionHeader('Biggest spend'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.biggestSpendTitle!,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (s.biggestSpendNote != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              s.biggestSpendNote!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₹${_fmt(s.biggestSpendAmount!)}',
                      style: TextStyle(
                          color: cs.error, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],

            if (s.topExpenseCategories.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionHeader('Top expense categories'),
              const SizedBox(height: 8),
              ...s.topExpenseCategories.map((cat) => _CategoryBar(
                    cat: cat,
                    maxTotal: s.topExpenseCategories.first.total,
                  )),
            ],

            if (s.income == 0 && s.expense == 0) ...[
              const SizedBox(height: 48),
              Center(
                child: Text(
                  'No transactions in $monthLabel',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.amount, required this.color});
  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color)),
            const SizedBox(height: 4),
            Text(
              '₹${_fmt(amount)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.cat, required this.maxTotal});
  final dynamic cat;
  final double maxTotal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = maxTotal > 0 ? (cat.total / maxTotal).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(cat.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(cat.name,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text('₹${_fmt(cat.total)}',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: fraction,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}
