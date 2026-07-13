import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/widgets/spendwise_sheet.dart';
import '../../../state/ai_providers.dart';
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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
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
    _scrollToBottom();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = ref.watch(aiEnabledProvider);
    final state = ref.watch(askChatProvider(widget.threadId));
    final thread = ref.watch(aiThreadStreamProvider(widget.threadId)).valueOrNull;
    final title = (thread?.title.isEmpty ?? true) ? 'New chat' : thread!.title;

    // Auto-scroll as messages change.
    ref.listen(askChatProvider(widget.threadId), (_, __) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chat history',
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            // `replace` (not push, not go) so the Chats list swaps in for this
            // chat — the back stack stays exactly one AI screen deep (either the
            // chat OR the list), never both stacked. `go` broke back-from-list
            // because it rebuilt the whole stack; `replace` keeps the shell tab
            // (Reports) beneath, so back from the list returns there in one tap.
            // The current chat disposes (and is pruned if empty) on swap-out.
            onPressed: () => context.replace('/ai/chats'),
          ),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newChat,
          ),
          IconButton(
            tooltip: 'AI settings',
            icon: const Icon(Icons.tune_rounded),
            // Root → root push to the dedicated AI settings screen.
            onPressed: () => context.push('/ai/settings'),
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
                style: GoogleFonts.plusJakartaSans(
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                style: GoogleFonts.plusJakartaSans(
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
    final bg = isUser
        ? cs.primary
        : message.isError
            ? cs.errorContainer
            : cs.surfaceContainerHighest;
    final fg = isUser
        ? cs.onPrimary
        : message.isError
            ? cs.onErrorContainer
            : cs.onSurface;

    return GestureDetector(
      onLongPress: () => _showActions(context),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: isUser
              ? Text(
                  message.content,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, height: 1.4, color: fg),
                )
              // Assistant (markdown) — shows a blinking caret while streaming.
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.content.isEmpty && message.streaming)
                      _caret(fg)
                    else
                      AiMarkdown(
                        source: message.content +
                            (message.streaming ? ' ▋' : ''),
                      ),
                  ],
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

  Widget _caret(Color fg) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}