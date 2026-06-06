import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/tags_repository.dart';
import '../../../state/manage_providers.dart';
import '../sheets/tag_form_sheet.dart';
import '../widgets/color_picker_row.dart';

class TagsTab extends ConsumerWidget {
  const TagsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(tagsStreamProvider);

    return Scaffold(
      body: stream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tags) => tags.isEmpty
            ? _EmptyState(onAdd: () => showTagFormSheet(context))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: tags.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (ctx, i) => _TagTile(tag: tags[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_tags',
        onPressed: () => showTagFormSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TagTile extends ConsumerWidget {
  const _TagTile({required this.tag});
  final Tag tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(tagsRepositoryProvider);
    final color = hexToColor(tag.color);

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
      title: Text(tag.name),
      trailing: PopupMenuButton<_Action>(
        icon: Icon(Icons.more_vert,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        onSelected: (action) {
          switch (action) {
            case _Action.edit:
              showTagFormSheet(context, editing: tag);
            case _Action.archive:
              _confirmArchive(context, repo, tag);
            case _Action.delete:
              _handleDelete(context, repo, tag);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: _Action.edit, child: Text('Edit')),
          const PopupMenuItem(
              value: _Action.archive, child: Text('Archive')),
          PopupMenuItem(
            value: _Action.delete,
            child: Text('Delete',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    TagsRepository repo,
    Tag tag,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Tag'),
        content: Text('Archive "${tag.name}"?'),
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
    if (ok == true) await repo.archive(tag.id);
  }

  Future<void> _handleDelete(
    BuildContext context,
    TagsRepository repo,
    Tag tag,
  ) async {
    final count = await repo.countTransactions(tag.id);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Tag'),
        content: Text(count > 0
            ? 'Delete "${tag.name}"? It will be removed from $count transaction(s).'
            : 'Permanently delete "${tag.name}"?'),
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
    if (ok == true) await repo.detachAndDelete(tag.id);
  }
}

enum _Action { edit, archive, delete }

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏷️', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text('No tags yet',
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
