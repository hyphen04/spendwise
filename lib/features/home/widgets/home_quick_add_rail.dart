import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/themes/app_fonts.dart';
import '../../../state/quick_add_providers.dart';
import '../../../data/db/app_database.dart';
import '../../transactions/sheets/amount_entry_sheet.dart';
import 'quick_add_sheet.dart';

/// The Home quick-add rail: a horizontal row of the user's most-used category
/// chips (top 5 by transaction frequency) + a "+ more" chip that opens the
/// full add flow. Tapping a category chip opens the [QuickAddSheet] with that
/// category locked in — type the amount, confirm, done.
///
/// Driven by [recentCategoriesProvider] (on-device, derived from transaction
/// history; no DB change). Hidden entirely while the provider is loading or
/// yields no categories, so the Home layout never reserves space for an empty
/// rail on a brand-new install with no categories at all.
class HomeQuickAddRail extends ConsumerWidget {
  const HomeQuickAddRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final catsAsync = ref.watch(recentCategoriesProvider);
    final cats = catsAsync.valueOrNull ?? <Category>[];

    if (cats.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'quick add',
              style: plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cats.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == cats.length) {
                  // "+ more" → full add flow.
                  return _RailChip(
                    iconData: Icons.add_rounded,
                    label: 'more',
                    accent: true,
                    onTap: () => showAmountEntrySheet(context),
                  );
                }
                final c = cats[i];
                return _RailChip(
                  icon: c.icon,
                  label: c.name,
                  onTap: () => showQuickAddSheet(context, categoryId: c.id),
                );
              },
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 80.ms, duration: 300.ms);
  }
}

class _RailChip extends StatelessWidget {
  const _RailChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.iconData,
    this.accent = false,
  });

  /// Emoji icon (category chips). Mutually exclusive with [iconData].
  final String? icon;
  final IconData? iconData;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = accent ? cs.onPrimary : cs.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: accent ? cs.primary : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: accent ? null : Border.all(color: cs.outline, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconData != null)
              Icon(iconData, size: 16, color: iconColor)
            else if (icon != null)
              Text(icon!, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent ? cs.onPrimary : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}