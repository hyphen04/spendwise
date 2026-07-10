import 'package:flutter/material.dart';

import '../themes/app_colors.dart';

/// Shows a destructive confirmation dialog and returns `true` only if the user
/// confirms. Returns `false` on cancel / dismiss.
///
/// This is the single shared helper for the "always confirm before delete" rule
/// (see CLAUDE.md → List Row Interaction Rules). Reuse this instead of inlining
/// a new AlertDialog for every delete flow.
///
/// Renders in the app's destructive red (`AppColors.expense`) — not
/// `ColorScheme.error`, which this app repurposes to a monochrome token.
Future<bool> showConfirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final appColors = Theme.of(ctx).extension<AppColors>()!;
      final danger = appColors.expense;
      final onDanger = appColors.onExpense;
      return AlertDialog(
        title: Text(title, style: TextStyle(color: danger, fontWeight: FontWeight.w700)),
        content: Text(message, style: TextStyle(color: danger)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel, style: TextStyle(color: onDanger)),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Shows a non-dismissable "you can't delete this" dialog with a single OK
/// button. Use when a record is still referenced by other rows (e.g. an
/// account/category/mode linked to transactions, a category used by a budget,
/// a transaction linked to a settlement, a settled due entry) and the delete
/// must be refused with a clear "N records bound to it" message.
///
/// Sibling to [showConfirmDeleteDialog] (which confirms a delete that *will*
/// happen). Renders in the app's destructive red (`AppColors.expense`), not
/// `ColorScheme.error`. Returns when the user taps OK.
Future<void> showCannotDeleteDialog(
  BuildContext context, {
  String title = 'Cannot Delete',
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final danger = Theme.of(ctx).extension<AppColors>()!.expense;
      final onDanger = Theme.of(ctx).extension<AppColors>()!.onExpense;
      return AlertDialog(
        title: Text(title, style: TextStyle(color: danger, fontWeight: FontWeight.w700)),
        content: Text(message, style: TextStyle(color: danger)),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: TextStyle(color: onDanger)),
          ),
        ],
      );
    },
  );
}