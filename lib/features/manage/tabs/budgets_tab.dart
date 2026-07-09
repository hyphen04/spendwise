import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../app/themes/app_colors.dart';
import '../../../app/utils/feedback.dart';
import '../../../app/widgets/confirm_delete_dialog.dart';
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
    final appColors = Theme.of(context).extension<AppColors>()!;
    final repo = ref.read(budgetsRepositoryProvider);
    final color = hexToColor(progress.categoryColor);
    final isOver = progress.isOver;
    final progressColor = isOver ? cs.error : cs.primary;

    return Slidable(
      key: ValueKey(progress.budget.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) =>
                showBudgetFormSheet(context, editing: progress.budget),
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            icon: Icons.edit_outlined,
            label: 'Edit',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => _confirmDelete(context, repo),
            backgroundColor: appColors.expense,
            foregroundColor: appColors.onExpense,
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
          ),
        ],
      ),
      child: Padding(
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
                const SizedBox(width: 6),
                Text(
                  '₹${_fmt(progress.spent)} / ₹${_fmt(progress.effectiveAmount)}',
                  style: TextStyle(
                    color: isOver ? cs.error : cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: isOver ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _subtitle(BudgetProgress p) {
    final period = p.budget.period == 'week' ? 'Weekly' : 'Monthly';
    final acct =
        p.budget.accountId != null ? ' · specific account' : '';
    return '$period$acct';
  }

  Future<void> _confirmDelete(
      BuildContext context, BudgetsRepository repo) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: 'Delete Budget',
      message: 'Delete budget for "${progress.categoryName}"?',
    );
    if (ok) {
      await repo.delete(progress.budget.id);
      if (context.mounted) showFeedbackSnackBar(context, 'Budget deleted');
    }
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

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
