import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import '../../../app/themes/app_fonts.dart';

import '../../../app/themes/app_colors.dart';
import '../../../app/utils/feedback.dart';
import '../../../app/widgets/confirm_delete_dialog.dart';
import '../../../app/widgets/spendwise_sheet.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/ai_chat_repository.dart';
import '../../../state/ai_providers.dart';
import '../../../state/app_mode_providers.dart';

/// Lists saved AI Copilot chats (threads). Tap to reopen/continue, swipe right
/// to rename, swipe left to delete, or use the row's "more" menu to pin /
/// archive / move to a folder. A "Select" action in the app bar enters bulk
/// mode: select-all or pick individual chats, then delete / move / pin /
/// archive the batch. Folders group chats and are reached via the filter chip
/// row under the app bar.
///
/// Follows the app's list-row rules (CLAUDE.md): swipe-to-reveal actions,
/// confirm before delete, snackbar after every edit/delete. Folders / pin /
/// archive are local-only metadata on `ai_threads` — never sent to the AI.
class AiChatListScreen extends ConsumerStatefulWidget {
  const AiChatListScreen({super.key});

  @override
  ConsumerState<AiChatListScreen> createState() => _AiChatListScreenState();
}

/// Sentinel filter value for the "Archived" view (a folder name can never be
/// this since real names come from user input).
const _kArchivedFilter = '__archived__';

class _AiChatListScreenState extends ConsumerState<AiChatListScreen> {
  final Set<String> _selected = {};
  bool _selectMode = false;
  /// `null` = All active, [_kArchivedFilter] = Archived, otherwise a folder name.
  String? _filter;

  AiChatRepository get _repo => ref.read(aiChatRepositoryProvider);

  Future<void> _newChat(BuildContext context) async {
    final thread = await _repo.createThread();
    if (!context.mounted) return;
    // `replace` (not push): the chat swaps in for this list, so the back stack
    // stays one AI screen deep — back from the chat returns to the shell tab
    // (Reports), not a pile of list screens. To come back to the list, the user
    // taps the history button in the chat (which replaces back to the list).
    context.replace('/ai/ask/${thread.id}');
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  void _enterSelectMode() => setState(() {
        _selectMode = true;
        _selected.clear();
      });

  void _exitSelectMode() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  void _toggleSelected(String id) => setState(() {
        if (!_selected.add(id)) _selected.remove(id);
      });

  void _selectAll(List<AiThread> visible) => setState(() {
        if (_selected.length == visible.length) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(visible.map((t) => t.id));
        }
      });

  // ── Per-row actions ────────────────────────────────────────────────────────

  Future<void> _rename(BuildContext context, AiThread thread) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _RenameDialog(initial: thread.title.isEmpty ? '' : thread.title),
    );
    if (result == null) return;
    final trimmed = result.trim();
    if (trimmed.isEmpty || trimmed == thread.title) return;
    await _repo.renameThread(thread.id, trimmed);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, 'Chat renamed');
  }

  Future<void> _delete(BuildContext context, AiThread thread) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Delete chat?',
      message:
          'This conversation and all its messages will be permanently removed '
          'from this device.',
    );
    if (!confirmed) return;
    await _repo.deleteThread(thread.id);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, 'Chat deleted');
  }

  Future<void> _togglePin(BuildContext context, AiThread thread) async {
    await _repo.pinThread(thread.id, !thread.pinned);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, thread.pinned ? 'Unpinned' : 'Pinned to top');
  }

  Future<void> _toggleArchive(BuildContext context, AiThread thread) async {
    await _repo.archiveThread(thread.id, !thread.archived);
    if (!context.mounted) return;
    showFeedbackSnackBar(
        context, thread.archived ? 'Unarchived' : 'Archived');
  }

  Future<void> _moveOne(BuildContext context, AiThread thread) async {
    final folder = await _showMoveDialog(context, preselect: thread.folder);
    if (folder == null) return;
    await _repo.moveToFolder(thread.id, folder);
    if (!context.mounted) return;
    showFeedbackSnackBar(context,
        folder.isEmpty ? 'Removed from folder' : 'Moved to "$folder"');
  }

  // ── Bulk actions ───────────────────────────────────────────────────────────

  List<AiThread> _selectedThreads(List<AiThread> all) =>
      all.where((t) => _selected.contains(t.id)).toList();

  Future<void> _bulkDelete(BuildContext context, List<AiThread> all) async {
    final ids = _selectedThreads(all).map((t) => t.id).toList();
    if (ids.isEmpty) return;
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Delete ${ids.length} chats?',
      message:
          'These conversations and all their messages will be permanently '
          'removed from this device.',
    );
    if (!confirmed) return;
    await _repo.bulkDelete(ids);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, '${ids.length} chats deleted');
    _exitSelectMode();
  }

  Future<void> _bulkMove(BuildContext context, List<AiThread> all) async {
    final ids = _selectedThreads(all).map((t) => t.id).toList();
    if (ids.isEmpty) return;
    final folder = await _showMoveDialog(context);
    if (folder == null) return;
    await _repo.bulkMove(ids, folder);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, folder.isEmpty
        ? 'Removed ${ids.length} from folder'
        : 'Moved ${ids.length} to "$folder"');
  }

  Future<void> _bulkPin(BuildContext context, List<AiThread> all) async {
    final sel = _selectedThreads(all);
    if (sel.isEmpty) return;
    final allPinned = sel.every((t) => t.pinned);
    await _repo.bulkPin(sel.map((t) => t.id).toList(), !allPinned);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, allPinned ? 'Unpinned' : 'Pinned');
  }

  Future<void> _bulkArchive(BuildContext context, List<AiThread> all) async {
    final sel = _selectedThreads(all);
    if (sel.isEmpty) return;
    final allArchived = sel.every((t) => t.archived);
    await _repo.bulkArchive(sel.map((t) => t.id).toList(), !allArchived);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, allArchived ? 'Unarchived' : 'Archived');
    if (!allArchived) _exitSelectMode(); // archiving hides them from the view
  }

  // ── Folder management ──────────────────────────────────────────────────────

  /// Pick a folder (or "None" / create a new one). Returns the folder name
  /// ('' = unfile), or `null` if cancelled.
  Future<String?> _showMoveDialog(BuildContext context,
      {String preselect = ''}) async {
    final folders = ref.read(aiFoldersStreamProvider).valueOrNull ?? const [];

    return showDialog<String>(
      context: context,
      builder: (ctx) => _MoveFolderDialog(
        folders: folders,
        preselect: preselect,
        onCreateNew: () async {
          final name = await showDialog<String>(
            context: ctx,
            builder: (dctx) => _RenameDialog(
                initial: '', title: 'New folder', hint: 'Folder name'),
          );
          return name?.trim();
        },
      ),
    );
  }

  Future<void> _manageFolders(BuildContext context) async {
    await showSpendWiseSheet(
      context,
      builder: (_) => _ManageFoldersSheet(
        repo: _repo,
        onChanged: () => ref.invalidate(aiFoldersStreamProvider),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(aiEffectiveEnabledProvider);
    final threadsAsync = ref.watch(aiThreadsStreamProvider);
    final foldersAsync = ref.watch(aiFoldersStreamProvider);

    return Scaffold(
      appBar: _buildAppBar(context, threadsAsync),
      bottomNavigationBar: _selectMode
          ? _BulkActionBar(
              selectedCount: _selected.length,
              allPinned: _selectedThreads(threadsAsync.valueOrNull ?? const [])
                  .every((t) => t.pinned),
              allArchived: _selectedThreads(
                      threadsAsync.valueOrNull ?? const [])
                  .every((t) => t.archived),
              onDelete: () => _bulkDelete(context,
                  threadsAsync.valueOrNull ?? const []),
              onMove: () => _bulkMove(context,
                  threadsAsync.valueOrNull ?? const []),
              onPin: () =>
                  _bulkPin(context, threadsAsync.valueOrNull ?? const []),
              onArchive: () => _bulkArchive(context,
                  threadsAsync.valueOrNull ?? const []),
            )
          : null,
      floatingActionButton: enabled && !_selectMode
          ? FloatingActionButton(
              onPressed: () => _newChat(context),
              child: const Icon(Icons.edit_note_rounded),
            )
          : null,
      body: !enabled
          ? _DisabledState(onConfigure: () => context.push('/ai/settings'))
          : threadsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load chats: $e')),
              data: (threads) {
                if (threads.isEmpty) {
                  return _EmptyState(onStart: () => _newChat(context));
                }
                final folders = foldersAsync.valueOrNull ?? const <String>[];
                final visible = _filterThreads(threads);
                return Column(
                  children: [
                    _FilterChipRow(
                      folders: folders,
                      filter: _filter,
                      onChanged: (f) => setState(() {
                        _filter = f;
                        _selected.clear();
                      }),
                    ),
                    Expanded(child: _buildList(context, visible)),
                  ],
                );
              },
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, AsyncValue<List<AiThread>> threadsAsync) {
    final all = threadsAsync.valueOrNull ?? const <AiThread>[];
    if (_selectMode) {
      final visible = _filterThreads(all);
      final allSelected =
          visible.isNotEmpty && _selected.length == visible.length;
      return AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelectMode,
        ),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(
            tooltip: allSelected ? 'Deselect all' : 'Select all',
            icon: Icon(allSelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded),
            onPressed: visible.isEmpty ? null : () => _selectAll(visible),
          ),
        ],
      );
    }
    return AppBar(
      title: const Text('Chats'),
      actions: [
        IconButton(
          tooltip: 'Select',
          icon: const Icon(Icons.checklist_rounded),
          onPressed: () => _enterSelectMode(),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'folders', child: Text('Manage folders')),
            PopupMenuItem(value: 'archived', child: Text('Archived')),
          ],
          onSelected: (v) {
            if (v == 'folders') {
              _manageFolders(context);
            } else if (v == 'archived') {
              setState(() {
                _filter = _kArchivedFilter;
                _selected.clear();
              });
            }
          },
        ),
      ],
    );
  }

  /// Threads visible under the current [_filter] (All = active non-archived,
  /// Archived = archived, otherwise the named folder's chats).
  List<AiThread> _filterThreads(List<AiThread> all) {
    if (_filter == _kArchivedFilter) {
      return all.where((t) => t.archived).toList();
    }
    if (_filter == null || _filter!.isEmpty) {
      return all.where((t) => !t.archived).toList();
    }
    return all.where((t) => !t.archived && t.folder == _filter).toList();
  }

  Widget _buildList(BuildContext context, List<AiThread> visible) {
    if (visible.isEmpty) {
      return _InlineEmpty(
        message: _filter == _kArchivedFilter
            ? 'No archived chats.'
            : (_filter == null || _filter!.isEmpty)
                ? ''
                : 'No chats in this folder.',
      );
    }

    // Pinned-first ordering (archived view has no pin split).
    final pinned = visible.where((t) => t.pinned).toList();
    final rest = visible.where((t) => !t.pinned).toList();

    if (_filter == _kArchivedFilter || pinned.isEmpty) {
      return _threadListView(context, visible);
    }
    // Pinned section header + rest.
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      children: [
        _SectionHeader('Pinned'),
        for (final t in pinned) _chatRow(context, t),
        const Divider(height: 24, indent: 16),
        _SectionHeader('All chats'),
        for (final t in rest) _chatRow(context, t),
      ],
    );
  }

  Widget _threadListView(BuildContext context, List<AiThread> threads) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: threads.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (_, i) => _chatRow(context, threads[i]),
    );
  }

  Widget _chatRow(BuildContext context, AiThread t) {
    return _ChatRow(
      thread: t,
      selectMode: _selectMode,
      selected: _selected.contains(t.id),
      onTap: _selectMode
          ? () => _toggleSelected(t.id)
          : () => context.replace('/ai/ask/${t.id}'),
      onToggleSelect: () => _toggleSelected(t.id),
      onRename: () => _rename(context, t),
      onDelete: () => _delete(context, t),
      onTogglePin: () => _togglePin(context, t),
      onToggleArchive: () => _toggleArchive(context, t),
      onMove: () => _moveOne(context, t),
    );
  }
}

// ── Filter chip row ──────────────────────────────────────────────────────────

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.folders,
    required this.filter,
    required this.onChanged,
  });

  final List<String> folders;
  final String? filter;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(String label, String? value) {
      final selected = filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onChanged(value),
          selectedColor: cs.primaryContainer,
          labelStyle: plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          chip('All', null),
          for (final f in folders) chip('📁 $f', f),
          chip('Archived', _kArchivedFilter),
        ],
      ),
    );
  }
}

// ── Chat row ─────────────────────────────────────────────────────────────────

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.thread,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onTogglePin,
    required this.onToggleArchive,
    required this.onMove,
    this.selectMode = false,
    this.selected = false,
    this.onToggleSelect,
  });

  final AiThread thread;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleArchive;
  final VoidCallback onMove;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            if (selectMode) ...[
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? cs.primary : cs.outline,
                size: 24,
              ),
              const SizedBox(width: 14),
            ] else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.auto_awesome_rounded,
                    color: cs.onPrimaryContainer, size: 22),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (thread.pinned && !selectMode) ...[
                        Icon(Icons.push_pin_rounded,
                            size: 13, color: cs.primary),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          thread.title.isEmpty ? 'New chat' : thread.title,
                          style: plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    thread.preview.isEmpty
                        ? (thread.folder.isEmpty
                            ? 'No messages yet'
                            : '📁 ${thread.folder}')
                        : thread.preview,
                    style: plusJakartaSans(
                      fontSize: 12,
                      height: 1.3,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!selectMode) ...[
              Text(
                _relativeTime(thread.updatedAt),
                style: plusJakartaSans(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              _RowMoreMenu(
                thread: thread,
                onRename: onRename,
                onDelete: onDelete,
                onTogglePin: onTogglePin,
                onToggleArchive: onToggleArchive,
                onMove: onMove,
              ),
            ],
          ],
        ),
      ),
    );

    if (selectMode) return row; // no swipe actions in select mode

    return Slidable(
      key: ValueKey(thread.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => onRename(),
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            icon: Icons.edit_outlined,
            label: 'Rename',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: Theme.of(context).extension<AppColors>()!.expense,
            foregroundColor:
                Theme.of(context).extension<AppColors>()!.onExpense,
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
          ),
        ],
      ),
      child: row,
    );
  }
}

class _RowMoreMenu extends StatelessWidget {
  const _RowMoreMenu({
    required this.thread,
    required this.onRename,
    required this.onDelete,
    required this.onTogglePin,
    required this.onToggleArchive,
    required this.onMove,
  });

  final AiThread thread;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleArchive;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert_rounded,
          color: cs.onSurfaceVariant, size: 20),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'pin',
          child: Text(thread.pinned ? 'Unpin' : 'Pin to top'),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Text(thread.archived ? 'Unarchive' : 'Archive'),
        ),
        const PopupMenuItem(value: 'move', child: Text('Move to folder')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
      onSelected: (v) {
        switch (v) {
          case 'pin':
            onTogglePin();
          case 'archive':
            onToggleArchive();
          case 'move':
            onMove();
          case 'rename':
            onRename();
          case 'delete':
            onDelete();
        }
      },
    );
  }
}

// ── Bulk action bar ──────────────────────────────────────────────────────────

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.selectedCount,
    required this.allPinned,
    required this.allArchived,
    required this.onDelete,
    required this.onMove,
    required this.onPin,
    required this.onArchive,
  });

  final int selectedCount;
  final bool allPinned;
  final bool allArchived;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onPin;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final none = selectedCount == 0;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: _action(
                icon: allPinned ? Icons.push_pin_outlined : Icons.push_pin,
                label: allPinned ? 'Unpin' : 'Pin',
                onPressed: none ? null : onPin,
              ),
            ),
            Expanded(
              child: _action(
                icon: allArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                label: allArchived ? 'Unarchive' : 'Archive',
                onPressed: none ? null : onArchive,
              ),
            ),
            Expanded(
              child: _action(
                icon: Icons.drive_file_move_outline,
                label: 'Move',
                onPressed: none ? null : onMove,
              ),
            ),
            Expanded(
              child: _action(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                onPressed: none ? null : onDelete,
                color: appColors.expense,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One bulk-action button: icon stacked over a short label. Vertical so the
  /// bar stays narrow (4 labeled buttons fit any width), wrapped in `Expanded`
  /// by the caller so the row never overflows — the label ellipsizes on extreme
  /// widths instead of the row clipping.
  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Move-to-folder dialog ────────────────────────────────────────────────────

class _MoveFolderDialog extends StatefulWidget {
  const _MoveFolderDialog({
    required this.folders,
    required this.preselect,
    required this.onCreateNew,
  });

  final List<String> folders;
  final String preselect;
  final Future<String?> Function() onCreateNew;

  @override
  State<_MoveFolderDialog> createState() => _MoveFolderDialogState();
}

class _MoveFolderDialogState extends State<_MoveFolderDialog> {
  late String _selection;

  @override
  void initState() {
    super.initState();
    _selection = widget.preselect;
  }

  Widget _folderOption(BuildContext context, String value, String label) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
        _selection == value
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: _selection == value ? cs.primary : cs.outline,
        size: 22,
      ),
      title: Text(label),
      onTap: () => setState(() => _selection = value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Move to folder'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _folderOption(context, '', 'None (no folder)'),
            for (final f in widget.folders) _folderOption(context, f, '📁 $f'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final name = await widget.onCreateNew();
                  if (name == null || name.isEmpty) return;
                  if (!mounted) return;
                  setState(() => _selection = name);
                },
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('New folder'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selection),
          child: const Text('Move'),
        ),
      ],
    );
  }
}

// ── Manage folders sheet ─────────────────────────────────────────────────────

class _ManageFoldersSheet extends ConsumerStatefulWidget {
  const _ManageFoldersSheet({required this.repo, required this.onChanged});
  final AiChatRepository repo;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ManageFoldersSheet> createState() => _ManageFoldersSheetState();
}

class _ManageFoldersSheetState extends ConsumerState<_ManageFoldersSheet> {
  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(aiFoldersStreamProvider);
    final folders = foldersAsync.valueOrNull ?? const <String>[];
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Manage folders',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Folders are created when you move a chat into one. Renaming or '
            'deleting a folder updates every chat in it.',
            style: plusJakartaSans(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (folders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No folders yet. Move a chat into a new folder to '
                  'create one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: folders.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (_, i) {
                  final f = folders[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.folder_rounded, color: cs.primary),
                    title: Text(f),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Rename',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _renameFolder(context, f),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 20, color: cs.error),
                          onPressed: () => _deleteFolder(context, f),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameFolder(BuildContext context, String oldName) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _RenameDialog(initial: oldName, title: 'Rename folder', hint: 'Folder name'),
    );
    if (result == null) return;
    final trimmed = result.trim();
    if (trimmed.isEmpty || trimmed == oldName) return;
    await widget.repo.renameFolder(oldName, trimmed);
    widget.onChanged();
    if (!context.mounted) return;
    showFeedbackSnackBar(context, 'Folder renamed');
  }

  Future<void> _deleteFolder(BuildContext context, String name) async {
    final ok = await showConfirmDeleteDialog(
      context,
      title: 'Delete folder "$name"?',
      message:
          'The folder is removed; its chats stay on this device but become '
          'unfiled.',
      confirmLabel: 'Delete folder',
    );
    if (!ok) return;
    await widget.repo.deleteFolder(name);
    widget.onChanged();
    if (!context.mounted) return;
    showFeedbackSnackBar(context, 'Folder deleted');
  }
}

// ── Small shared widgets ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Text(
        label,
        style: plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: 56, color: cs.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No chats yet',
                style: plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Tap the pencil to start a new conversation. Your chats are saved '
              'on this device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('New chat'),
              onPressed: onStart,
            ),
          ],
        ),
      ),
    );
  }
}

class _DisabledState extends StatelessWidget {
  const _DisabledState({required this.onConfigure});
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('AI Copilot is off',
                style: plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'AI Copilot is hidden in Offline mode, or not enabled. Switch to '
              'Online mode and enable AI in Settings to use chats.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Configure AI'),
              onPressed: onConfigure,
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial, this.title, this.hint});
  final String initial;
  final String? title;
  final String? hint;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? 'Rename chat'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: widget.hint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Compact relative-time label (Today / Yesterday / N days ago / date).
String _relativeTime(int ms) {
  final now = DateTime.now();
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime(now.year, now.month, now.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
  if (diff == 0) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return 'Today $h:$m';
  }
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return '$diff days ago';
  final d = t.day.toString().padLeft(2, '0');
  final mo = t.month.toString().padLeft(2, '0');
  return '$d/$mo/${t.year}';
}