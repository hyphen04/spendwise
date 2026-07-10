import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/themes/app_colors.dart';
import '../../app/utils/feedback.dart';
import '../../app/utils/infinite_scroll.dart';
import '../../app/utils/phone_utils.dart';
import '../../app/widgets/confirm_delete_dialog.dart';
import '../../app/widgets/contact_avatar.dart';
import '../../app/widgets/load_more_button.dart';
import '../../data/db/app_database.dart';

import '../../state/dues_providers.dart';
import 'sheets/add_contact_sheet.dart';
import 'sheets/add_entry_sheet.dart';
import 'sheets/settle_sheet.dart';
import 'sheets/settlement_detail_sheet.dart';
import 'widgets/phone_chooser_sheet.dart';

class ContactDetailScreen extends ConsumerStatefulWidget {
  const ContactDetailScreen({super.key, required this.contactId});
  final String contactId;

  @override
  ConsumerState<ContactDetailScreen> createState() =>
      _ContactDetailScreenState();
}

class _ContactDetailScreenState extends ConsumerState<ContactDetailScreen> {
  final _paging = PagingState();

  Future<void> _deleteEntry(BuildContext context, WidgetRef ref, DueEntry e) async {
    // A settled entry is owned by its settlement — deleting it here would
    // silently desync the settlement (the entry count it shows would shrink
    // with no warning). Block and point the user at the settlement instead.
    if (e.isSettled) {
      await showCannotDeleteDialog(
        context,
        title: "Can't delete this entry",
        message:
            'It is part of a settlement. Undo the settlement first — from '
            'Settlement history below — to delete this entry.',
      );
      return;
    }

    final ok = await showConfirmDeleteDialog(
      context,
      title: 'Delete Entry',
      message: 'Permanently delete this entry?',
    );
    if (!ok) return;
    await ref.read(duesRepositoryProvider).deleteEntry(e.id);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, 'Entry deleted');
  }

  Future<void> _deleteContact(BuildContext context, DueContact contact) async {
    final repo = ref.read(duesRepositoryProvider);
    // Pre-count so the user is told exactly what blocks deletion (entries and/or
    // settlements), instead of a generic caught-exception message. Both FKs are
    // RESTRICT, so the count is authoritative; the try/catch below is the net.
    final entries = await repo.countEntriesByContact(contact.id);
    final settlements = await repo.countSettlementsByContact(contact.id);
    if (!context.mounted) return;
    if (entries > 0 || settlements > 0) {
      final parts = <String>[];
      if (entries == 1) {
        parts.add('1 entry');
      } else if (entries > 1) {
        parts.add('$entries entries');
      }
      if (settlements == 1) {
        parts.add('1 settlement');
      } else if (settlements > 1) {
        parts.add('$settlements settlements');
      }
      await showCannotDeleteDialog(
        context,
        message:
            '"${contact.name}" has ${parts.join(' and ')} bound to it. Settle or delete them first.',
      );
      return;
    }

    final ok = await showConfirmDeleteDialog(
      context,
      title: 'Delete Contact',
      message: 'Delete "${contact.name}"? You cannot undo this action.',
    );
    if (!ok) return;
    try {
      await repo.deleteContact(contact.id);
      if (!context.mounted) return;
      showFeedbackSnackBar(context, 'Contact deleted');
      Navigator.of(context).pop();
    } catch (_) {
      if (!context.mounted) return;
      showFeedbackSnackBar(
        context,
        'Cannot delete contact. Settle or delete their entries first.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final summaryAsync = ref.watch(contactSummaryProvider(widget.contactId));
    // Watched here too so the parent can drive infinite scroll (hasMore needs
    // the total). Riverpod caches the family result — the inner Consumer
    // watching the same provider does not run a second query.
    final entriesTotal =
        ref.watch(unsettledEntriesProvider(widget.contactId)).valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: cs.surface,
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (summary) {
          final contact = summary.contact;
          final phones = _phonesOf(contact);
          final balance = summary.balance;
          final isPayable = balance < 0;
          final balanceColor = balance == 0
              ? cs.onSurface
              : (isPayable ? appColors.expense : appColors.income);
          final sign = balance == 0 ? '' : (isPayable ? '−' : '+');
          final balanceLabel =
              balance == 0 ? 'all settled up' : (isPayable ? 'you owe' : 'you get');

          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              maybeLoadMore(
                n,
                hasMore: _paging.hasMore(entriesTotal),
                onLoadMore: () => setState(_paging.loadMore),
              );
              return false;
            },
            child: CustomScrollView(
              slivers: [
                // The bar carries only back + edit + delete. No title — the
                // contact's name lives in the hero card below, so it isn't
                // shown twice.
                SliverAppBar(
                  pinned: true,
                  backgroundColor: cs.surface,
                  surfaceTintColor: Colors.transparent,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.edit_rounded),
                      tooltip: 'Edit',
                      onPressed: () =>
                          showAddContactSheet(context, existingContact: contact),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Delete contact',
                      onPressed: () => _deleteContact(context, contact),
                    ),
                  ],
                ),

                // ── Hero card: who they are, the balance, how to reach them ──────
                // One contained unit (card with an outline border, matching the
                // app's card theme) instead of loose sections held together by
                // thin dividers. The balance is the focal number; identity sits
                // compact above it; Call/WhatsApp sit as proper buttons below.
                // A large amount never collides with the buttons — the number is
                // on its own line and the buttons are on another, full-width.
                SliverToBoxAdapter(
                  child: _HeroCard(
                    contact: contact,
                    phones: phones,
                    balance: balance,
                    isPayable: isPayable,
                    balanceColor: balanceColor,
                    sign: sign,
                    balanceLabel: balanceLabel,
                  )
                      .animate()
                      .fadeIn(duration: 280.ms)
                      .slideY(begin: -0.02, end: 0, duration: 280.ms),
                ),

                // ── Section: unsettled entries ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
                    child: Row(
                      children: [
                        Text(
                          'unsettled entries',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '${summary.unsettledCount}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (summary.unsettledCount > 0)
                          FilledButton.tonal(
                            onPressed: () {
                              final entries = ref
                                  .read(unsettledEntriesProvider(widget.contactId))
                                  .valueOrNull ??
                                  [];
                              showSettleSheet(
                                  context, contact: contact, entries: entries);
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 7),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Settle up'),
                          ),
                      ],
                    ),
                  ),
                ),

                // The actual unsettled entries list.
                Consumer(builder: (context, ref, _) {
                  final entriesAsync = ref.watch(unsettledEntriesProvider(widget.contactId));

                  return entriesAsync.when(
                    loading: () => const SliverToBoxAdapter(
                        child: Center(child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ))),
                    error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                    data: (entries) {
                      if (entries.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 28),
                            child: Center(
                              child: Text(
                                'No pending entries',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      final visible = entries.take(_paging.visibleCount).toList();
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final e = visible[i];
                            final date = DateFormat('dd MMM').format(DateTime.parse(e.entryDate));
                            final isPay = e.direction == 'payable';
                            final dirColor = isPay ? appColors.expense : appColors.income;

                            return Slidable(
                              key: Key(e.id),
                              startActionPane: ActionPane(
                                motion: const DrawerMotion(),
                                extentRatio: 0.25,
                                children: [
                                  SlidableAction(
                                    onPressed: (_) => showAddDueEntrySheet(
                                        context,
                                        prefilledContact: contact,
                                        existingEntry: e),
                                    backgroundColor: cs.primary,
                                    foregroundColor: cs.onPrimary,
                                    icon: Icons.edit_outlined,
                                    label: 'Edit',
                                  ),
                                ],
                              ),
                              endActionPane: ActionPane(
                                motion: const DrawerMotion(),
                                extentRatio: 0.25,
                                children: [
                                  SlidableAction(
                                    onPressed: (_) =>
                                        _deleteEntry(context, ref, e),
                                    backgroundColor: appColors.expense,
                                    foregroundColor: appColors.onExpense,
                                    icon: Icons.delete_outline_rounded,
                                    label: 'Delete',
                                  ),
                                ],
                              ),
                              child: InkWell(
                                onTap: () => showAddDueEntrySheet(
                                    context, prefilledContact: contact, existingEntry: e),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 13),
                                  child: Row(
                                    children: [
                                      _DirectionChip(
                                        isPay: isPay,
                                        color: dirColor,
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              e.note.isEmpty ? 'Entry' : e.note,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Text(
                                                  date,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w400,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                                if (e.mealSlot != null) ...[
                                                  Text('  •  ',
                                                      style:
                                                          GoogleFonts.plusJakartaSans(
                                                              fontSize: 12,
                                                              color: cs
                                                                  .onSurfaceVariant)),
                                                  Icon(
                                                    e.mealSlot == 'lunch'
                                                        ? Icons.wb_sunny_rounded
                                                        : Icons.nights_stay_rounded,
                                                    size: 12,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    e.mealSlot == 'lunch'
                                                        ? 'Lunch'
                                                        : 'Dinner',
                                                    style:
                                                        GoogleFonts.plusJakartaSans(
                                                            fontSize: 12,
                                                            color: cs
                                                                .onSurfaceVariant),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '₹${NumberFormat('#,##,###').format(e.amount)}',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ],
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: visible.length,
                        ),
                      );
                    },
                  );
                }),

                // Load-more fallback for the unsettled entries list.
                if (_paging.hasMore(entriesTotal))
                  SliverToBoxAdapter(
                    child: LoadMoreButton(
                      showing: _paging.visibleCount,
                      total: entriesTotal,
                      pageSize: _paging.pageSize,
                      onTap: () => setState(_paging.loadMore),
                    ),
                  ),

                // ── Section: settlement history ───────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Divider(height: 1, thickness: 0.8, color: cs.outline),
                  ),
                ),

                Consumer(builder: (context, ref, _) {
                  final histAsync =
                      ref.watch(settlementsWithCountProvider(widget.contactId));

                  return histAsync.when(
                    loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                    error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                    data: (settlementsWithCount) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          child: Row(
                            children: [
                              Text(
                                'settlement history',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                '${settlementsWithCount.length}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),

                // ── Settlement history list ───────────────────────────────────────
                Consumer(builder: (context, ref, _) {
                  final histAsync =
                      ref.watch(settlementsWithCountProvider(widget.contactId));

                  return histAsync.when(
                    loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                    error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                    data: (settlementsWithCount) {
                      if (settlementsWithCount.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 22),
                            child: Center(
                              child: Text(
                                'No settlements yet',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      cs.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final item = settlementsWithCount[i];
                            final s = item.settlement;
                            return InkWell(
                              onTap: () => showSettlementDetailSheet(context, s),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 13),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: appColors.income
                                            .withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: appColors.income,
                                      ),
                                    ),
                                    const SizedBox(width: 13),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Settled ₹${NumberFormat('#,##,###').format(s.totalAmount)}',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurface,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures()
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${item.entryCount} entries  •  ${DateFormat('dd MMM yyyy').format(DateTime.parse(s.settledDate))}',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (s.linkedTransactionId != null)
                                      Icon(Icons.link_rounded,
                                          color: cs.primary, size: 18),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: settlementsWithCount.length,
                        ),
                      );
                    },
                  );
                }),

                SliverToBoxAdapter(
                    child:
                        SizedBox(height: MediaQuery.paddingOf(context).bottom + 100)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_contact_detail',
        onPressed: () {
          final summary = summaryAsync.valueOrNull;
          if (summary != null) {
            showAddDueEntrySheet(context, prefilledContact: summary.contact);
          }
        },
        tooltip: 'Add Entry',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

/// Small circular arrow chip leading each entry row — ↑ you get (income) /
/// ↓ you owe (expense), matching the Dues screen's direction language.
class _DirectionChip extends StatelessWidget {
  const _DirectionChip({required this.isPay, required this.color});
  final bool isPay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        isPay ? Icons.south_rounded : Icons.north_rounded,
        color: color,
        size: 18,
      ),
    );
  }
}

/// The hero: one contained card holding the contact's identity, the balance
/// (the focal number), and the Call/WhatsApp reach actions.
///
/// Everything that belongs to *this person* lives in one bordered unit, so the
/// top of the screen reads as a confident profile card rather than a balance
/// floating between ambiguous dividers. Layout order — identity → balance →
/// reach — gives a natural "who / what you owe / how to reach them" reading,
/// and putting the amount on its own line (with the buttons on the line below
/// it) means a large amount never crowds the buttons off-screen.
///
/// The balance uses the app's direction language: sign + color carry meaning
/// (−/red = you owe, +/green = you get), Space Grotesk with tabular figures and
/// a FittedBox so it scales down instead of overflowing. When settled, the
/// money line becomes a clean "all settled up" rather than ₹0.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.contact,
    required this.phones,
    required this.balance,
    required this.isPayable,
    required this.balanceColor,
    required this.sign,
    required this.balanceLabel,
  });

  final DueContact contact;
  final List<ContactPhone> phones;
  final double balance;
  final bool isPayable;
  final Color balanceColor;
  final String sign;
  final String balanceLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final hasPhone = phones.isNotEmpty;
    final isVendor = contact.type == 'vendor';
    final settled = balance == 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Identity ──────────────────────────────────────────────────────
          Row(
            children: [
              ContactAvatar(
                photoPath: contact.photoPath,
                emoji: contact.icon,
                colorHex: contact.color,
                size: 52,
                emojiFontSize: 26,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    if (hasPhone) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.call_rounded,
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              formatPhone(phones.first.number),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (phones.length > 1) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest
                                    .withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '+${phones.length - 1}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isVendor ? 'vendor' : 'person',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ── Balance (the focal number) ─────────────────────────────────────
          if (settled)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 22, color: appColors.income),
                const SizedBox(width: 8),
                Text(
                  'all settled up',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$sign₹${NumberFormat('#,##,###').format(balance.abs())}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: balanceColor,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPayable ? Icons.south_rounded : Icons.north_rounded,
                      size: 15,
                      color: balanceColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      balanceLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),

          // ── Reach actions ──────────────────────────────────────────────────
          if (hasPhone) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ReachButton(
                    icon: Icons.call_rounded,
                    label: 'Call',
                    color: cs.primary,
                    onTap: () => _ContactActions.call(context, phones),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ReachButton(
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: () => _ContactActions.whatsapp(context, phones),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Dials [phone] via the system dialer.
///
/// iOS `UIApplication.open` is strict about `tel:` URLs — a bare 10-digit local
/// number can return false and never open the dialer. Use E.164 with the India
/// country code (+91). We store a normalized 10-digit key (91 stripped during
/// import), so prepend it here. We launch directly rather than gating on
/// `canLaunchUrl`: on iOS `canLaunchUrl('tel:')` returns false unless `tel` is
/// in `LSApplicationQueriesSchemes`, so a guard would silently disable calling.
Future<void> _dialPhone(BuildContext context, String phone) async {
  final ok = await launchUrl(Uri.parse('tel:+91$phone'),
      mode: LaunchMode.platformDefault);
  if (!ok && context.mounted) {
    showFeedbackSnackBar(context, 'Could not open dialer', error: true);
  }
}

/// Opens the WhatsApp chat with [phone].
///
/// Prefers the `whatsapp://` custom scheme — `UIApplication.open` launches the
/// app directly. The `https://wa.me` universal link, when opened programmatically
/// on iOS, routes through Safari ("Open in WhatsApp") instead of the app, so it's
/// only the fallback when WhatsApp isn't installed.
Future<void> _openWhatsApp(BuildContext context, String phone) async {
  // International number without '+': 91 + 10-digit (we store a normalized
  // 10-digit India key with 91 stripped on import).
  final phoneParam = '91$phone';
  var ok = await launchUrl(
      Uri.parse('whatsapp://send?phone=$phoneParam'),
      mode: LaunchMode.platformDefault);
  if (!ok) {
    ok = await launchUrl(Uri.parse('https://wa.me/$phoneParam'),
        mode: LaunchMode.platformDefault);
  }
  if (!ok && context.mounted) {
    showFeedbackSnackBar(context, 'WhatsApp not available', error: true);
  }
}

/// Every phone number attached to [contact] for the call/WhatsApp chooser.
///
/// Decodes the `phones` JSON column; falls back to the legacy `phone` primary
/// when that's empty (a single-number contact or one created before v11).
/// De-duplicates by normalized key. Mirrors `DuesRepository.getContactPhones`
/// but is sync/Drift-free so the Stateless card can call it directly.
List<ContactPhone> _phonesOf(DueContact contact) {
  final fromJson = ContactPhone.decode(contact.phones);
  if (fromJson.isNotEmpty) {
    final seen = <String>{};
    final out = <ContactPhone>[];
    for (final p in fromJson) {
      if (p.number.isEmpty || seen.contains(p.number)) continue;
      seen.add(p.number);
      out.add(p);
    }
    return out;
  }
  if (contact.phone != null && contact.phone!.isNotEmpty) {
    return [ContactPhone(number: contact.phone!)];
  }
  return const [];
}

/// Call + WhatsApp reach actions. When the contact has more than one number,
/// tapping either button first opens a chooser so the user picks which number
/// to use; with a single number it acts directly. Exposed as static methods so
/// the hero card's buttons can wire up without a stateful wrapper.
class _ContactActions {
  static Future<void> call(BuildContext context, List<ContactPhone> phones) async {
    if (phones.isEmpty) return;
    if (phones.length == 1) {
      await _dialPhone(context, phones.first.number);
      return;
    }
    final chosen = await showPhoneChooser(
      context,
      phones,
      title: 'Call which number?',
      subtitle: 'Pick a number to dial',
      icon: Icons.call_rounded,
    );
    if (chosen == null || !context.mounted) return;
    await _dialPhone(context, chosen.number);
  }

  static Future<void> whatsapp(
      BuildContext context, List<ContactPhone> phones) async {
    if (phones.isEmpty) return;
    if (phones.length == 1) {
      await _openWhatsApp(context, phones.first.number);
      return;
    }
    final chosen = await showPhoneChooser(
      context,
      phones,
      title: 'WhatsApp which number?',
      subtitle: 'Pick a number to message',
      icon: Icons.chat_rounded,
    );
    if (chosen == null || !context.mounted) return;
    await _openWhatsApp(context, chosen.number);
  }
}

/// A compact, tinted reach button (Call / WhatsApp). Equal-width inside the
/// hero card's action row. Color is tied to the action (primary / WhatsApp
/// green) so each button has its own identity at a glance.
class _ReachButton extends StatelessWidget {
  const _ReachButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}