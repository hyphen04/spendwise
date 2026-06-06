import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/budget_progress.dart';
import '../../../data/repositories/budgets_repository.dart';
import '../../../state/home_providers.dart';
import '../sheets/budget_form_sheet.dart';
import '../widgets/color_picker_row.dart';

class BudgetsTab extends ConsumerWidget {
  const BudgetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final progressAsync =
        ref.watch(budgetProgressProvider((now.year, now.month)));

    return Scaffold(
      body: progressAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) => items.isEmpty
            ? _EmptyState(onAdd: () => showBudgetFormSheet(context))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (ctx, i) => _BudgetCard(progress: items[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_budgets',
        onPressed: () => showBudgetFormSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.progress});
  final BudgetProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final repo = ref.read(budgetsRepositoryProvider);
    final color = hexToColor(progress.categoryColor);
    final isOver = progress.isOver;
    final progressColor = isOver ? cs.error : cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(progress.categoryIcon,
                    style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.categoryName,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      _subtitle(progress),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_Action>(
                onSelected: (action) =>
                    _handle(action, context, ref, repo),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _Action.edit, child: Text('Edit')),
                  PopupMenuItem(value: _Action.delete, child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  color: progressColor,
                  backgroundColor: progressColor.withAlpha(30),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '₹${_fmt(progress.spent)} / ₹${_fmt(progress.budget.amount)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isOver ? cs.error : cs.onSurfaceVariant,
                      fontWeight: isOver ? FontWeight.w600 : null,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _subtitle(BudgetProgress p) {
    final period = p.budget.period == 'week' ? 'Weekly' : 'Monthly';
    final acct =
        p.budget.accountId != null ? ' · specific account' : '';
    return '$period$acct';
  }

  void _handle(_Action action, BuildContext context, WidgetRef ref,
      BudgetsRepository repo) {
    switch (action) {
      case _Action.edit:
        showBudgetFormSheet(context, editing: progress.budget);
      case _Action.delete:
        _confirmDelete(context, repo);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, BudgetsRepository repo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Budget'),
        content: Text('Delete budget for "${progress.categoryName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await repo.delete(progress.budget.id);
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

enum _Action { edit, delete }

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📊', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(
            'No budgets yet',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
