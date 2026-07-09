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