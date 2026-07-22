import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/themes/app_colors.dart';
import '../../../app/themes/app_fonts.dart';
import '../../../app/utils/money_format.dart';
import '../../../app/widgets/contact_avatar.dart';
import '../../../app/widgets/spendwise_card.dart';
import '../../../data/db/app_database.dart';
import '../../../state/dues_providers.dart';
import '../../../state/prefs_providers.dart';
import '../../dues/sheets/add_entry_sheet.dart';

/// Home quick-dues card — restores the inline "quick dues entry" the old
/// `HomeDuesWidget` provided. A horizontal scroller of due-contact chips (avatar
/// + name + signed balance); tapping a chip opens the canonical
/// [showAddDueEntrySheet] prefilled with that contact so logging a new due is
/// one tap + amount. Long-press a chip (or the header chevron) opens the full
/// per-contact `/dues/:id` screen for settle-up. Hidden entirely when there are
/// no due contacts, so Home never reserves space for an empty card.
///
/// On-device only; reads `dueContactsStreamProvider` + `allContactBalancesProvider`.
class HomeQuickDuesCard extends ConsumerWidget {
  const HomeQuickDuesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Respect the Settings → "Quick Dues Widget" toggle. The card is also
    // hidden below when there are no due contacts, but this gate honors the
    // user's choice to remove the card from Home entirely.
    if (!ref.watch(showQuickDuesProvider)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final contactsAsync = ref.watch(dueContactsStreamProvider);
    final balances = ref.watch(allContactBalancesProvider).valueOrNull ?? const <String, double>{};

    final contacts = (contactsAsync.valueOrNull ?? <DueContact>[])
        .where((c) => !c.isArchived)
        .toList();
    if (contacts.isEmpty) return const SizedBox.shrink();

    // Non-zero balances first (the ones you actually care about), then rest.
    contacts.sort((a, b) {
      final ba = balances[a.id] ?? 0;
      final bb = balances[b.id] ?? 0;
      return ba.abs().compareTo(bb.abs()) * -1; // larger |balance| first
    });

    return SpendwiseCard(
      outerPadding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      innerPadding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'quick dues',
                style: plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/dues'),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      Text(
                        'all',
                        style: plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 16, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: contacts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final c = contacts[i];
                final bal = balances[c.id] ?? 0.0;
                return _DueChip(
                  contact: c,
                  balance: bal,
                  cs: cs,
                  appColors: appColors,
                  onTap: () => showAddDueEntrySheet(context, prefilledContact: c),
                  onLongPress: () => context.push('/dues/${c.id}'),
                );
              },
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms);
  }
}

class _DueChip extends StatelessWidget {
  const _DueChip({
    required this.contact,
    required this.balance,
    required this.cs,
    required this.appColors,
    required this.onTap,
    required this.onLongPress,
  });

  final DueContact contact;
  final double balance;
  final ColorScheme cs;
  final AppColors appColors;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final receivable = balance > 0;
    final payable = balance < 0;
    final color = receivable
        ? appColors.income
        : payable
            ? appColors.expense
            : cs.onSurfaceVariant;
    String balLabel;
    if (balance == 0) {
      balLabel = 'settled';
    } else {
      balLabel = '${receivable ? '+' : '−'}${fmtMoney(balance.abs())}';
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        // Adaptive width: short names get a tight chip, long names grow and
        // wrap to a second line. Fixed height keeps every chip (and its
        // avatar + balance) aligned across the row.
        constraints: const BoxConstraints(minWidth: 72, maxWidth: 120),
        child: Container(
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              ContactAvatar(
                photoPath: contact.photoPath,
                emoji: contact.icon,
                colorHex: contact.color,
                size: 34,
              ),
              const SizedBox(height: 6),
              Expanded(
                // Center the name vertically so a short 1-line name sits
                // balanced, not floating at the top with a gap under it.
                child: Center(
                  child: Text(
                    contact.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                balLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}