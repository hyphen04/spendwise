import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/utils/feedback.dart';
import '../../../app/utils/infinite_scroll.dart';
import '../../../app/widgets/load_more_button.dart';
import '../../../app/widgets/spendwise_sheet.dart';
import '../../../state/ai_providers.dart';
import '../../../state/model_browser_provider.dart';
import '../../../state/prefs_providers.dart';
import '../domain/ai_config.dart';
import '../domain/ai_model.dart';
import 'text_field_sheet.dart';

/// Opens the searchable, paginated model picker as a bottom sheet.
///
/// Lists models the user's provider actually supports (fetched live from
/// `GET /models`), paged 40 at a time with a debounced search filter. A
/// "Use custom model name" footer always lets the user type an id by hand
/// (for custom providers that don't expose a list, failed fetches, or power
/// users). See [ModelBrowserNotifier] for the fetch + cache + filter logic.
void showModelPickerSheet(BuildContext context, WidgetRef ref) {
  showSpendWiseSheet(
    context,
    builder: (_) => const _ModelPickerSheet(),
  );
}

class _ModelPickerSheet extends ConsumerStatefulWidget {
  const _ModelPickerSheet();

  @override
  ConsumerState<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<_ModelPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Kick off the first fetch for the current provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(modelBrowserProvider.notifier).open();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    final trimmed = v.trim();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) ref.read(modelBrowserProvider.notifier).setQuery(trimmed);
    });
  }

  Future<void> _selectModel(AiModel model) async {
    await ref.read(prefsServiceProvider).setAiModel(model.id);
    ref.invalidate(aiConfigProvider);
    if (!mounted) return;
    showFeedbackSnackBar(context, 'Model updated');
    Navigator.pop(context);
  }

  void _openManualEntry() {
    final current = ref.read(aiConfigProvider).model;
    Navigator.pop(context); // close the picker, then open manual entry on top.
    TextEditingController? controller;
    showSpendWiseSheet(
      context,
      builder: (ctx) {
        controller ??= TextEditingController(text: current);
        return TextFieldSheet(
          title: 'Model',
          label: 'Model name',
          controller: controller!,
          helper: 'Leave empty to use the provider default.',
          onSaved: (value) async {
            await ref
                .read(prefsServiceProvider)
                .setAiModel(value.isEmpty ? null : value);
            ref.invalidate(aiConfigProvider);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = ref.watch(aiConfigProvider);
    final browser = ref.watch(modelBrowserProvider);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Choose Model',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          config.preset.label,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: browser.status == ModelBrowserStatus.loading
                        ? null
                        : () =>
                            ref.read(modelBrowserProvider.notifier).retry(),
                  ),
                ],
              ),
            ),
            // ── Search field ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search models…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.cancel_rounded, size: 20),
                          onPressed: () {
                            _searchCtrl.clear();
                            _debounce?.cancel();
                            ref
                                .read(modelBrowserProvider.notifier)
                                .setQuery('');
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ── Body ─────────────────────────────────────────────────────
            Expanded(child: _body(context, config, browser)),
            // ── Manual-entry footer ──────────────────────────────────────
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Use custom model name'),
              subtitle: const Text('Type a model id that isn\'t listed above.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _openManualEntry,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
      BuildContext context, AiConfig config, ModelBrowserState browser) {
    switch (browser.status) {
      case ModelBrowserStatus.idle:
      case ModelBrowserStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ModelBrowserStatus.error:
        return _StatusMessage(
          icon: Icons.error_outline_rounded,
          message: browser.error ?? 'Could not load models.',
          action: FilledButton.tonalIcon(
            onPressed: () => ref.read(modelBrowserProvider.notifier).retry(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        );
      case ModelBrowserStatus.manual:
        return const _StatusMessage(
          icon: Icons.edit_rounded,
          message:
              'This provider doesn\'t expose a model list.\nEnter the model name below.',
        );
      case ModelBrowserStatus.loaded:
        if (browser.visible.isEmpty) {
          return _StatusMessage(
            icon: Icons.search_off_rounded,
            message: browser.query.isEmpty
                ? 'No models available.'
                : 'No models match "${browser.query}".',
          );
        }
        return _modelList(context, config, browser);
    }
  }

  Widget _modelList(
      BuildContext context, AiConfig config, ModelBrowserState browser) {
    final currentModel = config.model;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Dismiss the keyboard as soon as the user starts scrolling the list.
        if (n is ScrollUpdateNotification) {
          FocusScope.of(context).unfocus();
        }
        maybeLoadMore(
          n,
          hasMore: browser.hasMore,
          onLoadMore: () =>
              ref.read(modelBrowserProvider.notifier).loadMore(),
        );
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          ...browser.visible.map((m) => _ModelTile(
                model: m,
                selected: m.id == currentModel &&
                    currentModel.isNotEmpty,
                onTap: () => _selectModel(m),
              )),
          if (browser.hasMore)
            LoadMoreButton(
              showing: browser.visible.length,
              total: browser.totalFiltered,
              pageSize: 40,
              onTap: () => ref.read(modelBrowserProvider.notifier).loadMore(),
            ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.model, required this.selected, required this.onTap});
  final AiModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      title: Text(
        model.display,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: selected ? TextStyle(color: cs.primary, fontWeight: FontWeight.w600) : null,
      ),
      subtitle: model.display != model.id
          ? Text(model.id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: cs.onSurfaceVariant))
          : null,
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: cs.primary)
          : Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}