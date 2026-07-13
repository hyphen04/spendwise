import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/themes/app_colors.dart';
import '../../app/utils/feedback.dart';
import '../../app/utils/money_format.dart';
import '../../app/utils/tone.dart';
import '../../app/widgets/confirm_delete_dialog.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/goals_repository.dart';
import '../../state/goals_providers.dart';
import '../../utils/color_utils.dart';
import 'sheets/contribution_sheet.dart';
import 'sheets/goal_form_sheet.dart';

/// Goals & savings targets: progress toward a savings goal (distinct from
/// spend-cap budgets). Add a goal, add contributions, swipe to edit/delete.
///
/// Follows the List Row Interaction Rules (CLAUDE.md): swipe to reveal Edit
/// (start) / Delete (end), tap opens the edit form, delete is confirmed via
/// [showConfirmDeleteDialog], and a snackbar follows every edit/delete via
/// [showFeedbackSnackBar]. Tone is observational (no-shame).
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      body: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load goals: $e')),
        data: (goals) => goals.isEmpty
            ? _EmptyState(onAdd: () => showGoalFormSheet(context))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: goals.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (_, i) => _GoalTile(goal: goals[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_goals',
        onPressed: () => showGoalFormSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _GoalTile extends ConsumerWidget {
  const _GoalTile({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final repo = ref.read(goalsRepositoryProvider);
    final progress = repo.progressFor(goal);
    final color = hexToColor(goal.color);
    final pct = (progress.fraction * 100).clamp(0.0, 100.0);
    final status = Tone.goalStatus(progress.fraction,
        monthsLeft: progress.monthsLeft);

    return Slidable(
      key: ValueKey(goal.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => showGoalFormSheet(context, editing: goal),
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
      child: InkWell(
        onTap: () => showGoalFormSheet(context, editing: goal),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Progress ring with the goal icon.
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: progress.fraction.clamp(0.0, 1.0),
                      strokeWidth: 4,
                      backgroundColor: color.withAlpha(30),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                    Center(
                      child: Text(goal.icon, style: const TextStyle(fontSize: 20)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            goal.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: goal.isActive
                                      ? null
                                      : TextDecoration.lineThrough,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(status: status, color: color),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress.fraction.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: color.withAlpha(25),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${fmtMoney(progress.saved)} of ${fmtMoney(progress.target)}'
                      ' · ${pct.toStringAsFixed(0)}%'
                      '${progress.monthsLeft != null ? ' · ${progress.monthsLeft}m left' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => showContributionSheet(context, goal: goal),
                tooltip: 'Add contribution',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, GoalsRepository repo) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: 'Delete Goal',
      message: 'Delete "${goal.name}"? Saved contributions will be removed.',
    );
    if (ok) {
      await repo.delete(goal.id);
      if (context.mounted) showFeedbackSnackBar(context, 'Goal deleted');
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.color});
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reached = status.startsWith('Goal reached');
    final bg = reached ? color.withAlpha(40) : Theme.of(context).colorScheme.surfaceContainerHigh;
    final fg = reached ? color : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(status,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎯', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('Save toward something',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 8),
            Text(
              'Set a savings goal — a phone, a trip, a buffer. Add contributions '
              'anytime and watch the ring fill. Goals live on this device only; '
              'they\'re never sent to the AI.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add a goal'),
            ),
          ],
        ),
      ),
    );
  }
}