import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../state/manage_providers.dart';
import '../sheets/category_form_sheet.dart';
import '../widgets/entity_tile.dart';

class CategoriesTab extends ConsumerStatefulWidget {
  const CategoriesTab({super.key});

  @override
  ConsumerState<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<CategoriesTab> {
  String _selectedKind = 'expense';

  @override
  Widget build(BuildContext context) {
    final stream = ref.watch(categoriesByKindProvider(_selectedKind));

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
                ButtonSegment(value: 'both', label: Text('Both')),
              ],
              selected: {_selectedKind},
              onSelectionChanged: (s) =>
                  setState(() => _selectedKind = s.first),
            ),
          ),
          Expanded(
            child: stream.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (cats) => cats.isEmpty
                  ? _EmptyState(
                      message: 'No $_selectedKind categories',
                      onAdd: () => showCategoryFormSheet(
                        context,
                        initialKind: _selectedKind,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: cats.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (ctx, i) =>
                          _CategoryTile(category: cats[i]),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_categories',
        onPressed: () => showCategoryFormSheet(
          context,
          initialKind: _selectedKind,
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(categoriesRepositoryProvider);
    final kindLabel = category.kind[0].toUpperCase() + category.kind.substring(1);

    return EntityTile(
      icon: category.icon,
      name: category.name,
      colorHex: category.color,
      subtitle: kindLabel,
      onEdit: () => showCategoryFormSheet(context, editing: category),
      onArchive: () => _confirmArchive(context, repo, category),
      onDelete: () => _handleDelete(context, ref, repo, category),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    CategoriesRepository repo,
    Category cat,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Category'),
        content: Text(
            'Archive "${cat.name}"? It will be hidden from pickers but transactions are kept.'),
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
    if (ok == true) await repo.archive(cat.id);
  }

  Future<void> _handleDelete(
    BuildContext context,
    WidgetRef ref,
    CategoriesRepository repo,
    Category cat,
  ) async {
    final count = await repo.countTransactions(cat.id);
    if (!context.mounted) return;

    if (count == 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Category'),
          content: Text('Permanently delete "${cat.name}"?'),
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
      if (ok == true) await repo.reassignAndDelete(cat.id, cat.id);
      return;
    }

    final allCats = await repo.getAllActive();
    if (!context.mounted) return;
    final others = allCats
        .where((c) => c.id != cat.id && c.kind != 'both'
            ? c.kind == cat.kind || c.kind == 'both'
            : true)
        .toList();

    if (others.isEmpty) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cannot Delete'),
          content: Text(
              '"${cat.name}" has $count transaction(s). Create another category first, then reassign.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    Category? target;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Reassign & Delete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${cat.name}" has $count transaction(s).\nMove them to:'),
              const SizedBox(height: 12),
              DropdownButton<Category>(
                isExpanded: true,
                value: target,
                hint: const Text('Select category'),
                items: others
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.icon} ${c.name}'),
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
      await repo.reassignAndDelete(cat.id, target!.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.onAdd});
  final String message;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📦', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(message,
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
