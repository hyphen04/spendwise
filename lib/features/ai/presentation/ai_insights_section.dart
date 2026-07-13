import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../state/ai_providers.dart';
import '../services/ai_insight_polish_controller.dart';

/// Compact entry point for the locally-computed smart insights inside the
/// Reports hub. Shows a single tappable row — "Smart Insights — N
/// observations" with a ✨ badge when AI-polished results are available — that
/// pushes the fullscreen, WhatsApp-status-style viewer at `/ai/insights`
/// (swipe + tap-zones + full body, no truncation).
///
/// This is the no-API-key surface: it works for every user, offline, with AI
/// fully disabled. When AI is enabled AND a key is set, an on-demand "Get AI
/// coaching on these" trigger fires
/// [aiPolishedInsightsProvider.notifier.polish] — the polished list is rendered
/// inside the viewer (the raw/polished toggle lives there), not in this compact
/// row. Real names are restored on-device by the polish controller; on any
/// failure the local insights remain visible.
///
/// Mounted from `reports_screen.dart` as `const AiInsightsSection()`.
class AiInsightsSection extends ConsumerWidget {
  const AiInsightsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final localAsync = ref.watch(aiInsightsProvider);
    final polish = ref.watch(aiPolishedInsightsProvider);
    final enabled = ref.watch(aiEnabledProvider);
    final hasKey = ref.watch(aiHasApiKeyProvider).valueOrNull ?? false;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: localAsync.when(
          loading: () => _placeholder(cs),
          error: (e, _) => _empty(cs, 'Insights unavailable right now.'),
          data: (local) {
            if (local.isEmpty) {
              return _empty(
                cs,
                'No notable patterns this month yet. Keep tracking — insights '
                'appear as your data grows.',
              );
            }
            return _entryCard(
              context: context,
              ref: ref,
              cs: cs,
              count: local.length,
              polish: polish,
              enabled: enabled,
              hasKey: hasKey,
            );
          },
        ),
      ),
    );
  }

  Widget _entryCard({
    required BuildContext context,
    required WidgetRef ref,
    required ColorScheme cs,
    required int count,
    required AiPolishState polish,
    required bool enabled,
    required bool hasKey,
  }) {
    final hasPolished = polish.polished != null;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/ai/insights'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Text('✨', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Smart Insights',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (hasPolished) ...[
                                const SizedBox(width: 8),
                                _polishedBadge(cs),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$count ${count == 1 ? 'observation' : 'observations'}'
                            '${hasPolished ? ' · AI-polished' : ''}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant),
                  ],
                ),
                _polishFooter(
                  ref: ref,
                  cs: cs,
                  polish: polish,
                  enabled: enabled,
                  hasKey: hasKey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The on-demand AI-coaching trigger. The raw/polished toggle used to live
  /// here; it now lives in the fullscreen viewer header, so this footer only
  /// surfaces the polish action (idle button, in-progress spinner, error +
  /// retry, and a subtle re-polish link once polished results exist).
  Widget _polishFooter({
    required WidgetRef ref,
    required ColorScheme cs,
    required AiPolishState polish,
    required bool enabled,
    required bool hasKey,
  }) {
    // Error hint + retry (local insights remain visible, opened from the row).
    if (polish.error != null && polish.polished == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: cs.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                polish.error!,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: cs.error),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(aiPolishedInsightsProvider.notifier).polish(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Polishing in progress.
    if (polish.loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'Getting AI coaching…',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Polished results available → subtle re-polish link (toggle is in viewer).
    if (polish.polished != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () =>
                ref.read(aiPolishedInsightsProvider.notifier).polish(),
            child: Text(
              'Re-polish',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    // Idle → offer the polish button (only when AI is enabled + key set).
    if (enabled && hasKey) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () =>
                ref.read(aiPolishedInsightsProvider.notifier).polish(),
            icon: Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
            label: Text(
              'Get AI coaching on these',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _polishedBadge(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 12, color: cs.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            'AI-polished',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: cs.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Analyzing your spending…',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(ColorScheme cs, String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}