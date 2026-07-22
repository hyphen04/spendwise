import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/utils/feedback.dart';
import '../../../app/widgets/spendwise_sheet.dart';
import '../../../features/ai/domain/ai_config.dart';
import '../../../services/secure_storage_service.dart';
import '../../../state/ai_providers.dart';
import '../../../state/prefs_providers.dart';
import 'model_picker_sheet.dart';
import 'text_field_sheet.dart';

/// The "AI Copilot" section shown inside the Settings screen.
///
/// Everything here is opt-in and off by default. The API key is stored in
/// secure storage (not prefs); the rest (provider, base URL, model,
/// share-names) is prefs-backed. "Test connection" sends a trivial completion
/// and maps HTTP status to a typed, actionable message.
class AiSettingsSection extends ConsumerWidget {
  const AiSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final enabled = ref.watch(aiEnabledProvider);
    final config = ref.watch(aiConfigProvider);
    final hasKey = ref.watch(aiHasApiKeyProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Enable AI Copilot'),
          subtitle: const Text(
              'Bring your own API key. Your data stays on-device — only '
              'aggregated, anonymized numbers are sent to the AI you choose.'),
          secondary: const Icon(Icons.auto_awesome_rounded),
          value: enabled,
          onChanged: (v) => ref.read(aiEnabledProvider.notifier).set(v),
        ),
        if (enabled) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Provider'),
            subtitle: Text(config.preset.label),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showProviderSheet(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('API Key'),
            subtitle: Text(
              hasKey ? 'Set — tap to change or clear' : 'Required — tap to add',
              style: TextStyle(
                  color: hasKey ? null : cs.error, fontWeight: FontWeight.w600),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showKeySheet(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Model'),
            subtitle: Text(config.model.isEmpty
                ? 'Not set — using provider default'
                : config.model),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showModelSheet(context, ref),
          ),
          if (config.preset.kind == LlmProviderKind.custom) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Base URL'),
              subtitle: Text(config.baseUrl.isEmpty
                  ? 'Required for custom provider'
                  : config.baseUrl),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showBaseUrlSheet(context, ref),
            ),
          ],
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Share category & account names'),
            subtitle: const Text(
                'Off = send anonymized labels (Category A, Account 1). On = '
                'send your real labels for more specific advice. Notes, '
                'contact names, phone numbers & photos are never sent.'),
            secondary: const Icon(Icons.visibility_outlined),
            value: ref.watch(aiShareNamesProvider),
            onChanged: (v) {
              ref.read(aiShareNamesProvider.notifier).set(v);
              // Belt-and-suspenders: aiConfigProvider also watches
              // aiShareNamesProvider, but invalidate to match the sibling
              // provider/model/base-URL settings and guarantee the next
              // chat/report generation sees the new value without a restart.
              ref.invalidate(aiConfigProvider);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Allow AI to look up my data'),
            subtitle: const Text(
                'Lets the chat AI run read-only lookups on your device to '
                'answer questions about any category, date range, or filtered '
                'totals — and help plan around goals and budgets. Your data '
                'never leaves; lookups return aggregates only (no notes, '
                'contacts, or raw rows). On by default.'),
            secondary: const Icon(Icons.manage_search_outlined),
            value: ref.watch(aiToolCallingProvider),
            onChanged: (v) => ref.read(aiToolCallingProvider.notifier).set(v),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Dynamic charts (experimental)'),
            subtitle: const Text(
                'The AI proposes which charts to show for your month, using '
                'pre-built on-device summaries. Your data never leaves — only '
                'anonymized aggregates are sent, and the charts render from '
                'your real data on-device. Off = a safe fixed set of charts.'),
            secondary: const Icon(Icons.insights_outlined),
            value: ref.watch(aiSpecEnabledProvider),
            onChanged: (v) => ref.read(aiSpecEnabledProvider.notifier).set(v),
          ),
          if (ref.watch(aiSpecEnabledProvider)) ...[
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Allow AI to query my data (custom SQL)'),
              subtitle: const Text(
                  'Lets the AI run read-only queries on your device for charts '
                  'the built-in summaries can\'t cover. Your data still never '
                  'leaves; queries are validated and blocked from touching '
                  'private details (notes, contacts, photos). Advanced — off '
                  'is recommended.'),
              secondary: const Icon(Icons.shield_outlined),
              value: ref.watch(aiCustomSqlProvider),
              onChanged: (v) => ref.read(aiCustomSqlProvider.notifier).set(v),
            ),
          ],
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.network_check_rounded),
            title: const Text('Test Connection'),
            subtitle: const Text('Verify your key and model work'),
            trailing: const Icon(Icons.play_arrow_rounded),
            onTap: () => _testConnection(context, ref),
          ),
        ],
      ],
    );
  }

  // ── Provider picker ──────────────────────────────────────────────────────

  void _showProviderSheet(BuildContext context, WidgetRef ref) {
    showSpendWiseSheet(
      context,
      builder: (ctx) {
        final current = ref.read(aiConfigProvider).preset.id;
        // The five presets + title can exceed the sheet's constrained height on
        // smaller devices (observed RenderFlex overflow at h<=403), so wrap the
        // list in a scroll view rather than a sized-to-natural Column.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Choose Provider',
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...LlmProviderPreset.all.map((p) {
                    final selected = p.id == current;
                    return ListTile(
                      leading: Icon(selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                          color: Theme.of(ctx).colorScheme.primary),
                      title: Text(p.label),
                      subtitle: p.kind == LlmProviderKind.custom
                          ? const Text('You set the base URL + model')
                          : Text(p.freeTier
                              ? 'Default: ${p.model}  ·  free tier'
                              : 'Default: ${p.model}'),
                      onTap: () async {
                        final prefs = ref.read(prefsServiceProvider);
                        await prefs.setAiProvider(p.id);
                        // Switching provider must also switch the model: clear
                        // the stored model override so the new provider's
                        // default (preset.model) takes effect. The old override
                        // is almost certainly invalid for the new provider.
                        // For custom (no default) this leaves it unset, which
                        // is correct — the user must choose one.
                        await prefs.setAiModel(null);
                        // A custom base-URL override must not leak into a preset
                        // provider, so clear it when leaving the custom preset.
                        if (p.kind != LlmProviderKind.custom) {
                          await prefs.setAiBaseUrl(null);
                        }
                        ref.invalidate(aiConfigProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── API key entry ────────────────────────────────────────────────────────

  void _showKeySheet(BuildContext context, WidgetRef ref) {
    showSpendWiseSheet(
      context,
      builder: (ctx) => _KeyEntrySheet(
        preset: ref.read(aiConfigProvider).preset,
        hasKey: ref.read(aiHasApiKeyProvider).valueOrNull ?? false,
        onSaved: () {
          // Bump the version so aiHasApiKeyProvider re-checks secure storage.
          ref.read(aiKeyVersionProvider.notifier).state++;
        },
      ),
    );
  }

  // ── Model entry ──────────────────────────────────────────────────────────

  void _showModelSheet(BuildContext context, WidgetRef ref) {
    showModelPickerSheet(context, ref);
  }

  void _showBaseUrlSheet(BuildContext context, WidgetRef ref) {
    final current = ref.read(aiConfigProvider).baseUrl;
    TextEditingController? controller;
    showSpendWiseSheet(
      context,
      builder: (ctx) {
        controller ??= TextEditingController(text: current);
        return TextFieldSheet(
          title: 'Base URL',
          label: 'https://your-provider/v1',
          controller: controller!,
          helper: 'OpenAI-compatible /chat/completions endpoint, no key.',
          onSaved: (value) async {
            await ref
                .read(prefsServiceProvider)
                .setAiBaseUrl(value.isEmpty ? null : value);
            ref.invalidate(aiConfigProvider);
          },
        );
      },
    );
  }

  // ── Test connection ─────────────────────────────────────────────────────

  Future<void> _testConnection(BuildContext context, WidgetRef ref) async {
    showFeedbackSnackBar(context, 'Testing connection…');
    final result = await ref.read(aiTestConnectionProvider(null).future);
    if (!context.mounted) return;
    if (result == null) {
      showFeedbackSnackBar(context, 'Connected — your key and model work.');
    } else {
      showFeedbackSnackBar(context, result.userMessage, error: true);
    }
  }
}

/// API-key entry sheet. The key is written straight to secure storage and the
/// controller cleared on save; it is never echoed back as plain text beyond
/// the masked field the user is editing.
class _KeyEntrySheet extends StatefulWidget {
  const _KeyEntrySheet({
    required this.preset,
    required this.hasKey,
    required this.onSaved,
  });
  final LlmProviderPreset preset;
  final bool hasKey;
  final VoidCallback onSaved;

  @override
  State<_KeyEntrySheet> createState() => _KeyEntrySheetState();
}

class _KeyEntrySheetState extends State<_KeyEntrySheet> {
  final _controller = TextEditingController();
  bool _obscure = true;

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
            Text('API Key', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Stored securely on this device only. Never included in backups '
              'or exports, and never sent anywhere except the provider you '
              'choose.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '${widget.preset.label} API key',
                hintText: 'sk-…',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (widget.preset.helpUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Get a key'),
                  onPressed: () => launchUrl(Uri.parse(widget.preset.helpUrl),
                      mode: LaunchMode.externalApplication),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.hasKey)
                  TextButton(
                    onPressed: () async {
                      await SecureStorageService.clearLlmKey();
                      widget.onSaved();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Clear'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final v = _controller.text.trim();
                    if (v.isEmpty) return;
                    await SecureStorageService.saveLlmKey(v);
                    _controller.clear();
                    widget.onSaved();
                    if (context.mounted) Navigator.pop(context);
                  },
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

/// Generic single-field bottom sheet used for the base-URL entry (and the
/// model picker's "Use custom model name" fallback). Extracted to
/// [TextFieldSheet] so both call sites share one implementation.