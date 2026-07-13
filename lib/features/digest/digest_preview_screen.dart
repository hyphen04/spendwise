import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/utils/money_format.dart';
import '../../state/ai_providers.dart';
import '../../state/digest_providers.dart';
import '../../state/manage_providers.dart';
import 'weekly_digest.dart';

/// Preview the weekly digest (computed on-device) and share it as plain text.
/// User-owned: the summary is theirs to keep/share — nothing is uploaded.
class DigestPreviewScreen extends ConsumerWidget {
  const DigestPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final digestAsync = ref.watch(weeklyDigestProvider);
    // Resolve the top-category icon from the categories stream by name.
    final cats = ref.watch(categoriesStreamProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Digest'),
        actions: [
          digestAsync.maybeWhen(
            data: (d) => IconButton(
              tooltip: 'Share as text',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => SharePlus.instance.share(ShareParams(text: d.toShareText())),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: digestAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not compute digest: $e')),
        data: (d) {
          final cat = d.topCategoryName != null
              ? cats.where((c) => c.name == d.topCategoryName).firstOrNull
              : null;
          final deltaText = d.hasPriorWeek && d.deltaPct.isFinite
              ? '${d.deltaPct < 0 ? '▼' : '▲'} ${(d.deltaPct.abs() * 100).toStringAsFixed(0)}% vs last week'
              : 'No prior week to compare';

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                '${_fmtDate(d.weekStart)} – ${_fmtDate(d.weekEnd)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 12),
              _BigStat(label: 'Spent this week', value: fmtMoney(d.spentThisWeek)),
              const SizedBox(height: 6),
              Text(
                '$deltaText · ${d.txnCountThisWeek} '
                '${d.txnCountThisWeek == 1 ? 'transaction' : 'transactions'}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _AiSummaryCard(digest: d),
              const SizedBox(height: 20),
              if (d.topCategoryName != null) ...[
                _SectionTile(
                  icon: cat?.icon ?? '📦',
                  color: const Color(0xFF2563EB),
                  title: 'Top category',
                  value:
                      '${d.topCategoryName} · ${fmtMoney(d.topCategoryAmount)}',
                ),
                const SizedBox(height: 20),
              ],
              Text('OBSERVATIONS',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.5)),
              const SizedBox(height: 10),
              for (final o in d.observations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•', style: TextStyle(color: cs.primary)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(o,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14, color: cs.onSurface)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('One tip',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(d.tip,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14, color: cs.onSurface)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(text: d.toShareText())),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share as text'),
              ),
              const SizedBox(height: 12),
              Text(
                'Computed on your device. Sharing sends only what you see above — '
                'nothing is uploaded to a server.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} '
      '${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.4)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  letterSpacing: -0.8)),
        ),
      ],
    );
  }
}

/// Optional AI-polished 2-sentence summary. Only shown when AI is enabled with
/// a key set; falls back to the deterministic digest text on any failure.
/// Names are anonymized before leaving the device and restored after — the
/// legend never leaves (see [WeeklyDigestPolishController]).
class _AiSummaryCard extends ConsumerWidget {
  const _AiSummaryCard({required this.digest});
  final WeeklyDigest digest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final aiOn = ref.watch(aiEnabledProvider);
    final hasKey = ref.watch(aiHasApiKeyProvider).valueOrNull ?? false;
    final polish = ref.watch(weeklyDigestPolishProvider);

    if (!aiOn || !hasKey) {
      // AI off / no key → show nothing; the deterministic digest below is the
      // whole experience.
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withAlpha(80),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('AI summary',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant)),
              ),
              if (polish.title == null && !polish.loading)
                TextButton(
                  onPressed: () =>
                      ref.read(weeklyDigestPolishProvider.notifier).polish(),
                  child: const Text('Generate'),
                ),
              if (polish.title != null)
                TextButton(
                  onPressed: () =>
                      ref.read(weeklyDigestPolishProvider.notifier).reset(),
                  child: const Text('Clear'),
                ),
            ],
          ),
          if (polish.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (polish.title != null) ...[
            const SizedBox(height: 6),
            Text(polish.title!,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text(polish.body!,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: cs.onSurface)),
          ] else if (polish.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(polish.error!,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.error)),
            ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });
  final String icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(icon, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
              Text(value,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ],
          ),
        ),
      ],
    );
  }
}