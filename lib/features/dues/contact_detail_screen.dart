import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/themes/app_colors.dart';

import '../../state/dues_providers.dart';
import 'sheets/add_contact_sheet.dart';
import 'sheets/add_entry_sheet.dart';
import 'sheets/settle_sheet.dart';
import 'sheets/settlement_detail_sheet.dart';

class ContactDetailScreen extends ConsumerWidget {
  const ContactDetailScreen({super.key, required this.contactId});
  final String contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final summaryAsync = ref.watch(contactSummaryProvider(contactId));

    return Scaffold(
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (summary) {
          final contact = summary.contact;
          final balance = summary.balance;
          final isPayable = balance < 0;
          
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text(
                  contact.name,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
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
                        style: GoogleFonts.manrope(
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
                        style: GoogleFonts.inter(
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
                        style: GoogleFonts.manrope(
                          fontSize: 18, 
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      if (summary.unsettledCount > 0)
                        FilledButton.tonal(
                          onPressed: () {
                            final entries = ref.read(unsettledEntriesProvider(contactId)).valueOrNull ?? [];
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
                final entriesAsync = ref.watch(unsettledEntriesProvider(contactId));
                
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
                    
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final e = entries[i];
                          final date = DateFormat('dd MMM').format(DateTime.parse(e.entryDate));
                          final isPay = e.direction == 'payable';
                          
                          return Dismissible(
                            key: Key(e.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: cs.error,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: Icon(Icons.delete_rounded, color: cs.onError),
                            ),
                            onDismissed: (_) {
                              ref.read(duesRepositoryProvider).deleteEntry(e.id);
                            },
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
                                                style: GoogleFonts.manrope(
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
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12, 
                                                      fontWeight: FontWeight.w400,
                                                      color: cs.onSurfaceVariant
                                                    ),
                                                  ),
                                                  if (e.mealSlot != null) ...[
                                                    Text(' • ', style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                                                    Icon(
                                                      e.mealSlot == 'lunch' ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                                                      size: 12,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      e.mealSlot == 'lunch' ? 'Lunch' : 'Dinner',
                                                      style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
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
                                          style: GoogleFonts.manrope(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                            color: cs.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          );
                        },
                        childCount: entries.length,
                      ),
                    );
                  },
                );
              }),
              
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              
              // Settlement History
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                  child: Text(
                    'Settlement History',
                    style: GoogleFonts.manrope(
                      fontSize: 18, 
                      fontWeight: FontWeight.w800, 
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              
              Consumer(builder: (context, ref, _) {
                final histAsync = ref.watch(settlementsWithCountProvider(contactId));
                
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
                                          style: GoogleFonts.manrope(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurface,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${item.entryCount} entries • ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(s.settledDate))}',
                                          style: GoogleFonts.inter(
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

