import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/themes/app_colors.dart';
import '../../app/utils/feedback.dart';
import '../../app/utils/money_format.dart';
import '../../app/widgets/confirm_delete_dialog.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../state/bills_providers.dart';
import '../../state/manage_providers.dart';
import '../../utils/color_utils.dart';
import 'sheets/recurring_form_sheet.dart';

/// Bills & subscriptions: a list of recurring items (user-added + detected),
/// with upcoming-due badges, swipe-to-edit/delete, and a "Re-detect" action
/// that re-runs on-device recurring-payment detection over the last 12 months.
///
/// Follows the List Row Interaction Rules (CLAUDE.md): swipe to reveal Edit
/// (start) / Delete (end), tap opens the edit form, delete is confirmed via
/// [showConfirmDeleteDialog], and a snackbar follows every edit/delete via
/// [showFeedbackSnackBar].
class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger one-time detection seeding (idempotent; safe to ignore result).
    ref.read(seedDetectedRecurringProvider);
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(recurringItemsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills & Subscriptions'),
        actions: [
          IconButton(
            tooltip: 'Re-detect from transactions',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => _redetect(context, ref),
          ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load bills: $e')),
        data: (items) => items.isEmpty
            ? _EmptyState(onAdd: () => showRecurringFormSheet(context))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (_, i) => _RecurringTile(item: items[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_bills',
        onPressed: () => showRecurringFormSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _redetect(BuildContext context, WidgetRef ref) async {
    showFeedbackSnackBar(context, 'Scanning transactions…');
    ref.invalidate(seedDetectedRecurringProvider);
    final count = await ref.read(seedDetectedRecurringProvider.future);
    if (!context.mounted) return;
    if (count > 0) {
      showFeedbackSnackBar(context, 'Found $count new recurring bill${count == 1 ? '' : 's'}.');
    } else {
      showFeedbackSnackBar(context, 'No new recurring bills found.');
    }
  }
}

class _RecurringTile extends ConsumerWidget {
  const _RecurringTile({required this.item});
  final RecurringItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final repo = ref.read(recurringRepositoryProvider);

    final cats = ref.watch(categoriesStreamProvider).valueOrNull ?? const <Category>[];
    final cat = cats.where((c) => c.id == item.categoryId).firstOrNull;
    final color = hexToColor(cat?.color);
    final dueDays = repo.daysUntilDue(item);

    return Slidable(
      key: ValueKey(item.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => showRecurringFormSheet(context, editing: item),
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
        onTap: () => showRecurringFormSheet(context, editing: item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(cat?.icon ?? '🔁',
                    style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: item.isActive
                                      ? null
                                      : TextDecoration.lineThrough,
                                ),
                          ),
                        ),
                        if (item.source == 'detected') ...[
                          const SizedBox(width: 8),
                          _Chip('Detected', cs.surfaceContainerHigh,
                              cs.onSurfaceVariant),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${fmtMoney(item.amount)} · ${_cadenceLabel(item.cadence)}'
                      '${cat != null ? ' · ${cat.name}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (item.isActive && dueDays != null) _DueBadge(dueDays: dueDays),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, RecurringRepository repo) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: 'Delete Bill',
      message: 'Delete "${item.name}"? You can always add it again.',
    );
    if (ok) {
      await repo.delete(item.id);
      if (context.mounted) showFeedbackSnackBar(context, 'Bill deleted');
    }
  }
}

/// Observation-tone due badge (no-shame: "overdue by N days" is a neutral
/// heads-up, not a red failure cue). Warm amber for due-soon/overdue, neutral
/// otherwise.
class _DueBadge extends StatelessWidget {
  const _DueBadge({required this.dueDays});
  final int dueDays;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color bg;
    final Color fg;
    if (dueDays < 0) {
      label = 'overdue by ${-dueDays}d';
      bg = const Color(0xFFF59E0B).withAlpha(40);
      fg = const Color(0xFFB45309);
    } else if (dueDays == 0) {
      label = 'due today';
      bg = const Color(0xFFF59E0B).withAlpha(40);
      fg = const Color(0xFFB45309);
    } else if (dueDays <= 3) {
      label = 'due in ${dueDays}d';
      bg = const Color(0xFFF59E0B).withAlpha(40);
      fg = const Color(0xFFB45309);
    } else {
      label = 'in ${dueDays}d';
      bg = Theme.of(context).colorScheme.surfaceContainerHigh;
      fg = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
      );
}

String _cadenceLabel(String cadence) {
  const labels = {
    'weekly': 'Weekly',
    'fortnightly': 'Fortnightly',
    'monthly': 'Monthly',
    'quarterly': 'Quarterly',
    'yearly': 'Yearly',
  };
  return labels[cadence] ?? cadence;
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
            const Text('🔁', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('Track recurring bills & subscriptions',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 8),
            Text(
              'Add a bill, or let SpendWise detect recurring charges from your '
              'transactions. We\'ll surface what\'s due soon. Detection runs '
              'on-device — your data never leaves.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add a bill'),
            ),
          ],
        ),
      ),
    );
  }
}