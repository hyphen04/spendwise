import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../app/themes/app_colors.dart';
import '../../../data/db/app_database.dart';
import '../../../state/dues_providers.dart';

void showSettlementDetailSheet(BuildContext context, DueSettlement settlement) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SettlementDetailSheet(settlement: settlement),
  );
}

class SettlementDetailSheet extends ConsumerWidget {
  const SettlementDetailSheet({super.key, required this.settlement});
  final DueSettlement settlement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final entriesAsync = ref.watch(settlementEntriesProvider(settlement.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, 
              height: 4, 
              decoration: BoxDecoration(
                color: cs.outlineVariant, 
                borderRadius: BorderRadius.circular(2)
              )
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40), // Balance the icon width
                  Text(
                    'Settlement Details', 
                    style: GoogleFonts.manrope(
                      fontSize: 20, 
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      letterSpacing: -0.5,
                    )
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                    onPressed: () => _showDeleteDialog(context, ref, cs),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '₹${settlement.totalAmount.toStringAsFixed(0)}', 
              style: GoogleFonts.manrope(
                fontSize: 36, 
                fontWeight: FontWeight.w800, 
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onSurface,
              )
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(settlement.settledDate)), 
              style: GoogleFonts.inter(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              )
            ),
            if (settlement.note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest, 
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Text(
                  settlement.note, 
                  style: GoogleFonts.inter(color: cs.onSurfaceVariant)
                ),
              ),
            ],
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  entriesAsync.when(
                    data: (entries) => Text(
                      '${entries.length} Entries Included',
                      style: GoogleFonts.manrope(
                        fontSize: 16, 
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      )
                    ),
                    loading: () => Text(
                      'Entries Included',
                      style: GoogleFonts.manrope(
                        fontSize: 16, 
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      )
                    ),
                    error: (_, __) => Text(
                      'Entries Included',
                      style: GoogleFonts.manrope(
                        fontSize: 16, 
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      )
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: entriesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error: $e')),
                data: (entries) {
                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      final date = DateFormat('dd MMM').format(DateTime.parse(e.entryDate));
                      final isPay = e.direction == 'payable';
                      
                      return Padding(
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
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteDialog(BuildContext context, WidgetRef ref, ColorScheme cs) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Settlement?'),
        content: const Text(
          'This will undo the settlement, returning the entries to the unsettled list. '
          'Any associated transaction will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await ref.read(duesRepositoryProvider).deleteSettlement(settlement.id);
      if (context.mounted) Navigator.pop(context); // Close the sheet
    }
  }
}
