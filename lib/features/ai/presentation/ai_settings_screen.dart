import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/themes/app_fonts.dart';

import '../../../state/ai_providers.dart';
import 'ai_settings_section.dart';

/// Dedicated, feature-scoped settings screen for the AI Copilot.
///
/// The main Settings screen is large; rather than burying the AI config in its
/// inline list, the AI section lives here on its own pushed screen. Reachable
/// from the chat (tune icon) and as a single entry from main Settings. The
/// privacy posture is stated on-screen so users know exactly what leaves the
/// device before they enable anything.
class AiSettingsScreen extends ConsumerWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final enabled = ref.watch(aiEnabledProvider);
    final hasKey = ref.watch(aiHasApiKeyProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Copilot')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _StatusBanner(enabled: enabled, hasKey: hasKey),
          const SizedBox(height: 12),
          Card(
            color: cs.surfaceContainerLowest,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: AiSettingsSection(),
            ),
          ),
          const SizedBox(height: 16),
          _PrivacyCard(),
        ],
      ),
    );
  }
}

// ── Status banner ───────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.enabled, required this.hasKey});
  final bool enabled;
  final bool hasKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String label;
    String detail;
    Color tint;
    Color onTint;
    IconData icon;
    if (!enabled) {
      label = 'AI Copilot is off';
      detail = 'Turn it on below and add an API key to start asking.';
      tint = cs.surfaceContainerHighest;
      onTint = cs.onSurfaceVariant;
      icon = Icons.lock_outline_rounded;
    } else if (!hasKey) {
      label = 'Almost ready — add your API key';
      detail = 'Enable is on, but no key is set yet.';
      tint = cs.errorContainer.withValues(alpha: 0.5);
      onTint = cs.onErrorContainer;
      icon = Icons.key_rounded;
    } else {
      label = 'Ready';
      detail = 'You can ask questions about your spending.';
      tint = cs.primaryContainer;
      onTint = cs.onPrimaryContainer;
      icon = Icons.check_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: onTint, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: plusJakartaSans(
                        fontWeight: FontWeight.w800, color: onTint)),
                const SizedBox(height: 2),
                Text(detail,
                    style: plusJakartaSans(
                        fontSize: 12,
                        height: 1.35,
                        color: onTint.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Privacy disclosure ───────────────────────────────────────────────────────

class _PrivacyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.shield_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text('Privacy at a glance',
                style: plusJakartaSans(
                    fontWeight: FontWeight.w800, color: cs.onSurface)),
          ]),
          const SizedBox(height: 12),
          _row(context, Icons.check_circle_rounded, cs.primary,
              'What leaves your device',
              'Only aggregated, anonymized numbers (totals, category '
              'percentages, budget status, 6-month cashflow).'),
          const SizedBox(height: 10),
          _row(
              context,
              Icons.check_circle_rounded,
              cs.primary,
              'Optional: real names',
              'Off by default. Turn on "Share names" to send your category & '
              'account labels for more specific advice.'),
          const SizedBox(height: 10),
          _row(context, Icons.block_rounded, cs.error, 'Never sent',
              'Transaction notes, contact names, phone numbers, photos, '
              'device contacts, and receipt files — in any mode.'),
          const SizedBox(height: 12),
          Text(
            'You bring your own API key and use this at your own risk. The key '
            'is stored securely on this device only. Your chats are also saved '
            'on this device only — never uploaded.',
            style: plusJakartaSans(
                fontSize: 12,
                height: 1.4,
                color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, Color color, String title,
      String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 2),
              Text(body,
                  style: plusJakartaSans(
                      fontSize: 12,
                      height: 1.35,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}