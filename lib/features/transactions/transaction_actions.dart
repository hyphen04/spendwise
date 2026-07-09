import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/themes/app_colors.dart';
import '../../app/utils/feedback.dart';
import '../../data/models/transaction_row.dart';
import '../../state/dues_providers.dart';
import '../../state/transactions_providers.dart';

/// Deletes a transaction after confirmation, preserving the settlement-aware
/// variants that used to live in the (now removed) transaction detail sheet:
///
/// - If the transaction is linked to a Dues settlement, the user can choose
///   "Delete Tx Only" (keep the settlement) or "Undo & Delete" (undo the
///   settlement, which marks its entries as unsettled again).
/// - Otherwise a plain confirm. A transfer asks to delete both legs (the repo
///   already deletes the pair leg atomically).
///
/// Shows a "Transaction deleted" snackbar on success. This is the shared entry
/// point for the transaction delete swipe action — do not inline a new dialog.
Future<void> confirmAndDeleteTransaction(
  BuildContext context,
  WidgetRef ref,
  TransactionRow row,
) async {
  final tx = row.transaction;
  final duesRepo = ref.read(duesRepositoryProvider);
  final settlement = await duesRepo.getSettlementForTransaction(tx.id);
  if (!context.mounted) return;

  final isTransfer = tx.kind.startsWith('transfer');

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final appColors = Theme.of(dialogContext).extension<AppColors>()!;
      final danger = appColors.expense;
      final onDanger = appColors.onExpense;
      return AlertDialog(
        title: Text('Delete Transaction',
            style: TextStyle(color: danger, fontWeight: FontWeight.w700)),
        content: Text(
          settlement != null
              ? 'This transaction is linked to a Dues settlement.\n\nDo you also want to undo the Dues settlement? (This will mark the tiffin/dues entries as unsettled again)'
              : (isTransfer
                  ? 'Delete both legs of this transfer?'
                  : 'Permanently delete this transaction?'),
          style: TextStyle(color: danger),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel'),
          ),
          if (settlement != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: danger),
              onPressed: () => Navigator.pop(dialogContext, 'delete_tx_only'),
              child: const Text('Delete Tx Only'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(
                dialogContext, settlement != null ? 'delete_and_undo' : 'delete'),
            child: Text(settlement != null ? 'Undo & Delete' : 'Delete',
                style: TextStyle(color: onDanger)),
          ),
        ],
      );
    },
  );

  if (result == null || result == 'cancel') return;

  if (result == 'delete_and_undo' && settlement != null) {
    await duesRepo.undoSettlement(settlement.id);
  }
  await ref.read(transactionsRepositoryProvider).delete(tx.id);

  if (!context.mounted) return;
  showFeedbackSnackBar(context, 'Transaction deleted');
}