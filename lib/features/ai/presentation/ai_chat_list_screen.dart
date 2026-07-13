import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/themes/app_colors.dart';
import '../../../app/utils/feedback.dart';
import '../../../app/widgets/confirm_delete_dialog.dart';
import '../../../data/db/app_database.dart';
import '../../../state/ai_providers.dart';

/// Lists saved AI Copilot chats (threads). Tap to reopen/continue, swipe left
/// to delete, swipe right to rename, FAB to start a new chat. Follows the app's
/// list-row rules (CLAUDE.md): swipe-to-reveal actions, confirm before delete,
/// snackbar after edit/delete.
class AiChatListScreen extends ConsumerWidget {
  const AiChatListScreen({super.key});

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final thread = await ref.read(aiChatRepositoryProvider).createThread();
    if (!context.mounted) return;
    // `replace` (not push): the chat swaps in for this list, so the back stack
    // stays one AI screen deep — back from the chat returns to the shell tab
    // (Reports), not a pile of list screens. To come back to the list, the user
    // taps the history button in the chat (which replaces back to the list).
    context.replace('/ai/ask/${thread.id}');
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, AiThread thread) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(initial: thread.title.isEmpty ? '' : thread.title),
    );
    if (result == null) return;
    final trimmed = result.trim();
    if (trimmed.isEmpty || trimmed == thread.title) return;
    await ref.read(aiChatRepositoryProvider).renameThread(thread.id, trimmed);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, 'Chat renamed');
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, AiThread thread) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Delete chat?',
      message: 'This conversation and all its messages will be permanently '
          'removed from this device.',
    );
    if (!confirmed) return;
    await ref.read(aiChatRepositoryProvider).deleteThread(thread.id);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, 'Chat deleted');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(aiThreadsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _newChat(context, ref),
        child: const Icon(Icons.edit_note_rounded),
      ),
      body: threadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load chats: $e')),
        data: (threads) {
          if (threads.isEmpty) {
            return _EmptyState(onStart: () => _newChat(context, ref));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            itemCount: threads.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final t = threads[i];
              return _ChatRow(
                thread: t,
                onTap: () => context.replace('/ai/ask/${t.id}'),
                onRename: () => _rename(context, ref, t),
                onDelete: () => _delete(context, ref, t),
              );
            },
          );
        },
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.thread,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final AiThread thread;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;

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
            backgroundColor: appColors.expense,
            foregroundColor: appColors.onExpense,
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
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
                    Text(
                      thread.title.isEmpty ? 'New chat' : thread.title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      thread.preview.isEmpty
                          ? 'No messages yet'
                          : thread.preview,
                      style: GoogleFonts.plusJakartaSans(
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
              Text(
                _relativeTime(thread.updatedAt),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
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
            Icon(Icons.auto_awesome_rounded, size: 56, color: cs.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No chats yet',
                style: GoogleFonts.plusJakartaSans(
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

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

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
      title: const Text('Rename chat'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(border: OutlineInputBorder()),
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