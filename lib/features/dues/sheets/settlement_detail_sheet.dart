import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../app/themes/app_colors.dart';
import '../../../app/utils/feedback.dart';
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

class SettlementDetailSheet extends ConsumerStatefulWidget {
  const SettlementDetailSheet({super.key, required this.settlement});
  final DueSettlement settlement;

  @override
  ConsumerState<SettlementDetailSheet> createState() =>
      _SettlementDetailSheetState();
}

class _SettlementDetailSheetState extends ConsumerState<SettlementDetailSheet> {
  /// Held in state so the displayed date refreshes in place after an edit,
  /// without having to pop/reopen the sheet. Day-only — the settlement date is a
  /// posting day, not a moment.
  late DateTime _date = DateTime.parse(widget.settlement.settledDate);

  Future<void> _editDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    await ref
        .read(duesRepositoryProvider)
        .updateSettlementDate(widget.settlement.id, picked);
    if (!mounted) return;
    setState(() => _date = picked);
    showFeedbackSnackBar(context, 'Settlement date updated');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final danger = appColors.expense;
    final entriesAsync = ref.watch(settlementEntriesProvider(widget.settlement.id));

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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  // Edit settlement date — re-dates both the settlement record
                  // and its linked transaction so reports count it on the new
                  // day. Balances the delete icon on the right.
                  IconButton(
                    icon: const Icon(Icons.edit_calendar_rounded),
                    tooltip: 'Edit settlement date',
                    onPressed: _editDate,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Settlement Details',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: danger),
                    onPressed: () => _showDeleteDialog(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '₹${widget.settlement.totalAmount.toStringAsFixed(0)}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _editDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('dd MMM yyyy').format(_date),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.edit_rounded,
                        size: 13, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (widget.settlement.note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(widget.settlement.note,
                    style: GoogleFonts.plusJakartaSans(color: cs.onSurfaceVariant)),
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
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    loading: () => Text(
                      'Entries Included',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    error: (_, __) => Text(
                      'Entries Included',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
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
                      final date =
                          DateFormat('dd MMM').format(DateTime.parse(e.entryDate));
                      final isPay = e.direction == 'payable';

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 13),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isPay
                                    ? appColors.expense.withValues(alpha: 0.1)
                                    : appColors.income.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                isPay
                                    ? Icons.arrow_downward_rounded
                                    : Icons.arrow_upward_rounded,
                                color:
                                    isPay ? appColors.expense : appColors.income,
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
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      if (e.mealSlot != null) ...[
                                        Text(' • ',
                                            style: GoogleFonts.plusJakartaSans(
                                                fontSize: 12,
                                                color: cs.onSurfaceVariant)),
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
                                          style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12,
                                              color: cs.onSurfaceVariant),
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

  Future<void> _showDeleteDialog(BuildContext context, WidgetRef ref) async {
    final danger = Theme.of(context).extension<AppColors>()!.expense;
    final onDanger = Theme.of(context).extension<AppColors>()!.onExpense;
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
            style: FilledButton.styleFrom(
                backgroundColor: danger, foregroundColor: onDanger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await ref.read(duesRepositoryProvider).deleteSettlement(widget.settlement.id);
      if (context.mounted) Navigator.pop(context); // Close the sheet
    }
  }
}