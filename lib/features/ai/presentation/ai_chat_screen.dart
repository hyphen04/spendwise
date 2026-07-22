import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/themes/app_fonts.dart';
import '../../../app/utils/feedback.dart';
import '../../../app/widgets/confirm_delete_dialog.dart';
import '../../../app/widgets/spendwise_sheet.dart';
import '../../../state/ai_providers.dart';
import '../../../state/app_mode_providers.dart';
import '../services/ai_chat_controller.dart';
import '../widgets/ai_markdown.dart';

/// The Ask chat screen — the hero AI feature, now persisted per thread.
///
/// Opens only when AI is enabled; otherwise shows a gentle prompt to enable +
/// add a key. Assistant replies stream in chunk-by-chunk and are rendered with
/// the app's markdown renderer. Every user message and each completed reply is
/// persisted (see [AskChatNotifier]); the hidden system/context preamble is
/// rebuilt in memory per session and is never stored. The privacy boundary
/// lives in [AiPayloadBuilder] (called by the controller) — nothing here or in
/// storage touches raw user data.
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key, required this.threadId});

  final String threadId;

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  /// True while the list is parked at (or very near) the bottom. Tracked from
  /// the scroll listener so a streaming reply doesn't yank the user back down
  /// if they scrolled up to read history — we only auto-scroll when they're
  /// already following the latest.
  bool _pinnedToBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final pos = _scrollController.position.pixels;
    final pinned = (max - pos) <= 120;
    if (pinned != _pinnedToBottom) _pinnedToBottom = pinned;
  }

  /// Keep the latest message in view. While a reply is actively streaming we
  /// **jump** to the bottom instantly — starting a 200ms tween on every chunk
  /// (chunks arrive many times per second) makes competing animations stutter.
  /// An instant jump lets the text flow smoothly, as if the bubble were growing
  /// under your finger. For non-streaming changes (a new bubble appearing) we
  /// use an eased tween so the motion feels intentional.
  void _maybeScroll(bool streaming) {
    if (!_pinnedToBottom) return; // user scrolled up — leave them be
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (streaming) {
        _scrollController.jumpTo(max);
      } else {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ref.read(askChatProvider(widget.threadId).notifier).send(text);
    // The user just sent — re-pin and ease down to the new bubble + reply.
    _pinnedToBottom = true;
    _maybeScroll(false);
  }

  Future<void> _newChat() async {
    final thread = await ref.read(aiChatRepositoryProvider).createThread();
    if (!mounted) return;
    // Replace (not push) so repeatedly starting new chats doesn't stack a
    // pile of chat screens — back from the new chat returns to wherever you
    // came from (Reports or the Chats list). The abandoned chat's notifier
    // disposes, and if it was empty it's pruned automatically.
    context.replace('/ai/ask/${thread.id}');
  }

  Future<void> _renameChat(String current) async {
    final result = await showSpendWiseSheet<String>(
      context,
      builder: (ctx) => _RenameSheet(
        initialValue: current,
        title: 'Rename chat',
        helper: 'This is the title shown in your chat history.',
      ),
    );
    final name = result?.trim() ?? '';
    if (name.isEmpty || name == current) return;
    await ref.read(aiChatRepositoryProvider).renameThread(widget.threadId, name);
    if (!mounted) return;
    showFeedbackSnackBar(context, 'Chat renamed');
  }

  Future<void> _deleteChat() async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Delete chat?',
      message:
          'This permanently deletes this conversation and all its messages '
          'from this device.',
    );
    if (!confirmed) return;
    await ref.read(aiChatRepositoryProvider).deleteThread(widget.threadId);
    if (!mounted) return;
    // The thread is gone — swap back to the chats list (replace, so back
    // doesn't return to a deleted chat).
    context.replace('/ai/chats');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = ref.watch(aiEffectiveEnabledProvider);
    final state = ref.watch(askChatProvider(widget.threadId));
    final thread = ref.watch(aiThreadStreamProvider(widget.threadId)).valueOrNull;
    final title = (thread?.title.isEmpty ?? true) ? 'New chat' : thread!.title;

    // Auto-scroll as messages change. While the last bubble is streaming we
    // glue to the bottom instantly (see _maybeScroll); otherwise ease down.
    ref.listen(askChatProvider(widget.threadId), (_, next) {
      final streaming =
          next.messages.isNotEmpty && next.messages.last.streaming;
      _maybeScroll(streaming);
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: plusJakartaSans(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newChat,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              switch (v) {
                case 'history':
                  // `replace` (not push) so the Chats list swaps in for this
                  // chat — the back stack stays exactly one AI screen deep,
                  // never both stacked. The current chat disposes (and is
                  // pruned if empty) on swap-out.
                  context.replace('/ai/chats');
                case 'rename':
                  _renameChat(title);
                case 'delete':
                  _deleteChat();
                case 'settings':
                  context.push('/ai/settings');
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: Icon(Icons.chat_bubble_outline_rounded),
                  title: Text('Chat history'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Rename chat'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: cs.error),
                  title: Text('Delete chat', style: TextStyle(color: cs.error)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.tune_rounded),
                  title: Text('AI settings'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: enabled ? _buildChat(cs, state) : _buildDisabled(cs),
    );
  }

  Widget _buildDisabled(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('AI Copilot is off',
                style: plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Bring your own API key to ask questions about your spending. '
              'Your data stays on-device — only aggregated, anonymized numbers '
              'are sent to the AI you choose.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Configure AI'),
              onPressed: () => context.push('/ai/settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat(ColorScheme cs, AskConversationState state) {
    return Column(
      children: [
        Expanded(
          child: state.messages.isEmpty
              ? _buildEmptyState(cs)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) {
                    final isLast = i == state.messages.length - 1;
                    return _MessageBubble(
                      message: state.messages[i],
                      cs: cs,
                      isLastAssistant: isLast &&
                          state.messages[i].role == 'assistant' &&
                          state.messages[i].id.isNotEmpty,
                      onEdit: state.messages[i].role == 'user'
                          ? (text) => ref
                              .read(askChatProvider(widget.threadId).notifier)
                              .editAndResend(state.messages[i].id, text)
                          : null,
                      onRegenerate: isLast &&
                              state.messages[i].role == 'assistant' &&
                              state.messages[i].id.isNotEmpty
                          ? () => ref
                              .read(askChatProvider(widget.threadId).notifier)
                              .regenerateLast()
                          : null,
                      onDelete: state.messages[i].id.isEmpty
                          ? null // transient error bubble — nothing to delete
                          : () => ref
                              .read(askChatProvider(widget.threadId).notifier)
                              .deleteMessage(state.messages[i].id),
                    );
                  },
                ),
        ),
        _buildComposer(cs, state.isLoading),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    final suggestions = [
      'Why am I over budget this month?',
      'How does my spending compare to last month?',
      'Which category should I watch next month?',
      'What\'s my savings trend over 6 months?',
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 40, color: cs.primary),
            const SizedBox(height: 12),
            Text('Ask anything about your spending',
                style: plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Answers are based only on your anonymized monthly summary — '
              'no notes, contacts, or transactions are shared. Chats are saved '
              'on this device; tap the history icon to browse them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions
                  .map((s) => ActionChip(
                        label: Text(s),
                        onPressed: () {
                          _controller.text = s;
                          _send();
                        },
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(ColorScheme cs, bool isLoading) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Ask about your spending…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: isLoading ? null : _send,
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.cs,
    required this.isLastAssistant,
    this.onEdit,
    this.onRegenerate,
    this.onDelete,
  });

  final AskMessage message;
  final ColorScheme cs;
  final bool isLastAssistant;
  final ValueChanged<String>? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';

    // User → a filled primary bubble, right-aligned.
    if (isUser) {
      return GestureDetector(
        onLongPress: () => _showActions(context),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.80,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              message.content,
              style: plusJakartaSans(
                  fontSize: 14, height: 1.4, color: cs.onPrimary),
            ),
          ),
        ),
      );
    }

    // Assistant error → a distinct error bubble so it reads as a problem.
    if (message.isError) {
      return GestureDetector(
        onLongPress: () => _showActions(context),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.88,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Text(
              message.content,
              style: plusJakartaSans(
                  fontSize: 14, height: 1.4, color: cs.onErrorContainer),
            ),
          ),
        ),
      );
    }

    // Assistant (markdown) — rendered on a flat `Card` (the same surface the
    // settings-screen menu rows use: `surfaceContainerLow`, rounded, thin
    // outline, no elevation), full-width like a settings card. Before the
    // first token lands we show an animated typing indicator; once text
    // streams in we render it with a trailing block cursor while streaming.
    // Long-press still opens the actions sheet.
    return GestureDetector(
      onLongPress: () => _showActions(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: message.content.isEmpty && message.streaming
                ? _TypingDots(color: cs.onSurfaceVariant)
                : AiMarkdown(
                    source:
                        message.content + (message.streaming ? ' ▋' : ''),
                  ),
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showSpendWiseSheet(
      context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEdit != null)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit & resend'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditSheet(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: message.content));
                },
              ),
              if (onRegenerate != null)
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('Regenerate'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onRegenerate!();
                  },
                ),
              if (onDelete != null)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                  title: Text('Delete', style: TextStyle(color: cs.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onDelete!();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showEditSheet(BuildContext context) {
    final controller = TextEditingController(text: message.content);
    showSpendWiseSheet(
      context,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit message',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Everything after this message will be removed and the '
                  'answer will be regenerated.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        Navigator.pop(ctx);
                        onEdit!(text);
                      },
                      child: const Text('Resend'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}

/// Three dots that breathe in a staggered wave — the "AI is typing" cue shown
/// in an empty streaming bubble before the first token arrives. Loops forever
/// while mounted; cheap (a single ticker driving three sibling dots).
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot peaks later in the cycle — a wave traveling left→right.
            final phase = _controller.value * 2 * pi + i * (2 * pi / 3);
            final bump = (sin(phase) + 1) / 2; // 0..1
            final opacity = 0.35 + 0.65 * bump;
            final scale = 0.7 + 0.3 * bump;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: opacity),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Bottom sheet for renaming a chat thread. Pops with the entered text on
/// Save (or submit), or null on dismiss/Cancel. The sheet owns its own
/// controller so the controller's lifetime is tied to the widget — it's
/// disposed only after the sheet is fully removed from the tree (i.e. after
/// the dismiss animation finishes), avoiding a use-after-dispose when the
/// TextField rebuilds during the exit animation.
class _RenameSheet extends StatefulWidget {
  const _RenameSheet({
    required this.initialValue,
    required this.title,
    required this.helper,
  });

  final String initialValue;
  final String title;
  final String helper;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.helper,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => Navigator.pop(context, v),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _controller.text),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}