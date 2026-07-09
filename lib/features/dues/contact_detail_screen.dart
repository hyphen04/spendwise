import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/themes/app_colors.dart';
import '../../data/db/app_database.dart';
import '../../app/utils/feedback.dart';
import '../../app/utils/infinite_scroll.dart';
import '../../app/widgets/confirm_delete_dialog.dart';
import '../../app/widgets/load_more_button.dart';

import '../../state/dues_providers.dart';
import 'sheets/add_contact_sheet.dart';
import 'sheets/add_entry_sheet.dart';
import 'sheets/settle_sheet.dart';
import 'sheets/settlement_detail_sheet.dart';

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
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (summary) {
          final contact = summary.contact;
          final balance = summary.balance;
          final isPayable = balance < 0;

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
              SliverAppBar(
                pinned: true,
                title: Text(
                  contact.name,
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: () => showAddContactSheet(context, existingContact: contact),
                  ),
                ],
              ),
              
              // Hero Balance
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Color(int.parse(contact.color.replaceFirst('#', '0xFF'))).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(contact.icon, style: const TextStyle(fontSize: 36)),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '₹${balance.abs().toStringAsFixed(0)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          letterSpacing: -1.5,
                          color: balance == 0 
                              ? cs.onSurface 
                              : (isPayable ? Theme.of(context).extension<AppColors>()!.expense : Theme.of(context).extension<AppColors>()!.income),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        balance == 0 
                            ? 'All Settled Up' 
                            : (isPayable ? 'You Owe Them' : 'They Owe You'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16, 
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Unsettled Entries List
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Unsettled Entries',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, 
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      if (summary.unsettledCount > 0)
                        FilledButton.tonal(
                          onPressed: () {
                            final entries = ref.read(unsettledEntriesProvider(widget.contactId)).valueOrNull ?? [];
                            showSettleSheet(context, contact: contact, entries: entries);
                          },
                          child: const Text('Settle'),
                        ),
                    ],
                  ),
                ),
              ),

              // The actual unsettled entries list
              Consumer(builder: (context, ref, _) {
                final entriesAsync = ref.watch(unsettledEntriesProvider(widget.contactId));
                
                return entriesAsync.when(
                  loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
                  error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                  data: (entries) {
                    if (entries.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text('No pending entries', style: TextStyle(color: cs.onSurfaceVariant)),
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
                              onTap: () => showAddDueEntrySheet(context, prefilledContact: contact, existingEntry: e),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                                child: Row(
                                        children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: isPay ? Theme.of(context).extension<AppColors>()!.expense.withValues(alpha: 0.1) : Theme.of(context).extension<AppColors>()!.income.withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            isPay ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                            color: isPay ? Theme.of(context).extension<AppColors>()!.expense : Theme.of(context).extension<AppColors>()!.income,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Text(
                                                    date,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 12, 
                                                      fontWeight: FontWeight.w400,
                                                      color: cs.onSurfaceVariant
                                                    ),
                                                  ),
                                                  if (e.mealSlot != null) ...[
                                                    Text(' • ', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: cs.onSurfaceVariant)),
                                                    Icon(
                                                      e.mealSlot == 'lunch' ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                                                      size: 12,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      e.mealSlot == 'lunch' ? 'Lunch' : 'Dinner',
                                                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: cs.onSurfaceVariant),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '₹${e.amount.toStringAsFixed(0)}',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const [FontFeature.tabularFigures()],
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
              
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              
              // Settlement History
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                  child: Text(
                    'Settlement History',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, 
                      fontWeight: FontWeight.w800, 
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              
              Consumer(builder: (context, ref, _) {
                final histAsync = ref.watch(settlementsWithCountProvider(widget.contactId));
                
                return histAsync.when(
                  loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                  error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                  data: (settlementsWithCount) {
                    if (settlementsWithCount.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('No settlements yet', style: TextStyle(color: cs.onSurfaceVariant)),
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
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Settled ₹${s.totalAmount.toStringAsFixed(0)}',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurface,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${item.entryCount} entries • ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(s.settledDate))}',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12, 
                                            fontWeight: FontWeight.w400,
                                            color: cs.onSurfaceVariant
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (s.linkedTransactionId != null)
                                    Icon(Icons.link_rounded, color: cs.primary, size: 20),
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
              
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 100)),
            ],
          ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
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

