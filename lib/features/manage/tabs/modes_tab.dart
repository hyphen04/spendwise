import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/modes_repository.dart';
import '../../../state/manage_providers.dart';
import '../../../state/prefs_providers.dart';
import '../sheets/mode_form_sheet.dart';
import '../widgets/entity_tile.dart';

class ModesTab extends ConsumerWidget {
  const ModesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(modesStreamProvider);

    return Scaffold(
      body: stream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (modes) => modes.isEmpty
            ? _EmptyState(onAdd: () => showModeFormSheet(context))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: modes.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (ctx, i) => _ModeTile(mode: modes[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_modes',
        onPressed: () => showModeFormSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ModeTile extends ConsumerWidget {
  const _ModeTile({required this.mode});
  final Mode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(modesRepositoryProvider);

    final defaultModeId = ref.watch(defaultModeIdProvider);
    final isDefault = mode.id == defaultModeId;

    return EntityTile(
      icon: mode.icon,
      name: mode.name,
      isDefault: isDefault,
      onEdit: () => showModeFormSheet(context, editing: mode),
      onArchive: () => _confirmArchive(context, repo, mode),
      onDelete: () => _handleDelete(context, ref, repo, mode),
      onSetDefault: () =>
          ref.read(defaultModeIdProvider.notifier).set(mode.id),
      onClearDefault: () =>
          ref.read(defaultModeIdProvider.notifier).set(null),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    ModesRepository repo,
    Mode mode,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Mode'),
        content: Text(
            'Archive "${mode.name}"? It will be hidden from pickers but transactions are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (ok == true) await repo.archive(mode.id);
  }

  Future<void> _handleDelete(
    BuildContext context,
    WidgetRef ref,
    ModesRepository repo,
    Mode mode,
  ) async {
    final count = await repo.countTransactions(mode.id);
    if (!context.mounted) return;

    if (count == 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Mode'),
          content: Text('Permanently delete "${mode.name}"?'),
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
      if (ok == true) await repo.reassignAndDelete(mode.id, mode.id);
      return;
    }

    final allModes = await repo.getAllActive();
    if (!context.mounted) return;
    final others = allModes.where((m) => m.id != mode.id).toList();

    if (others.isEmpty) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cannot Delete'),
          content: Text(
              '"${mode.name}" has $count transaction(s). Create another mode first, then reassign.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    Mode? target;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Reassign & Delete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '"${mode.name}" has $count transaction(s).\nMove them to:'),
              const SizedBox(height: 12),
              DropdownButton<Mode>(
                isExpanded: true,
                value: target,
                hint: const Text('Select mode'),
                items: others
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text('${m.icon} ${m.name}'),
                        ))
                    .toList(),
                onChanged: (v) => setSt(() => target = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed:
                  target == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Reassign & Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && target != null) {
      await repo.reassignAndDelete(mode.id, target!.id);
    }
  }
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
          const Text('💳', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text('No payment modes yet',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
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
