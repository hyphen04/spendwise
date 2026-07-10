import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/themes/app_colors.dart';
import '../../app/utils/feedback.dart';
import '../../app/widgets/confirm_delete_dialog.dart';
import '../../data/models/transaction_row.dart';
import '../../state/dues_providers.dart';
import '../../state/transactions_providers.dart';

/// Deletes a transaction after confirmation.
///
/// - If the transaction is linked to a Dues settlement, it **cannot be deleted
///   here** — the settlement owns that transaction. The user is told to undo or
///   delete the settlement first (from the contact's Settlement history), which
///   removes the linked transaction via `DuesRepository.deleteSettlement`.
/// - A transfer asks to delete both legs (the repo deletes the pair leg
///   atomically); any other transaction is a plain confirm.
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

  // A transaction linked to a settlement is owned by that settlement. Block the
  // delete and point the user at the settlement instead of letting them orphan
  // the settlement (the FK is SET NULL, so deleting would silently unlink it —
  // we refuse rather than leave a dangling settlement).
  if (settlement != null) {
    final settled = DateFormat('dd MMM yyyy')
        .format(DateTime.parse(settlement.settledDate));
    await showCannotDeleteDialog(
      context,
      title: "Can't delete this transaction",
      message:
          'It is linked to a Dues settlement (settled $settled). Undo or delete '
          'that settlement first — from the contact\'s Settlement history — '
          'then the transaction is removed with it.',
    );
    return;
  }

  final isTransfer = tx.kind.startsWith('transfer');

  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final appColors = Theme.of(dialogContext).extension<AppColors>()!;
      final danger = appColors.expense;
      final onDanger = appColors.onExpense;
      return AlertDialog(
        title: Text('Delete Transaction',
            style: TextStyle(color: danger, fontWeight: FontWeight.w700)),
        content: Text(
          isTransfer
              ? 'Delete both legs of this transfer?'
              : 'Permanently delete this transaction?',
          style: TextStyle(color: danger),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete', style: TextStyle(color: onDanger)),
          ),
        ],
      );
    },
  );

  if (confirm != true) return;

  await ref.read(transactionsRepositoryProvider).delete(tx.id);

  if (!context.mounted) return;
  showFeedbackSnackBar(context, 'Transaction deleted');
}