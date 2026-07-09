import 'package:flutter/material.dart';

import '../themes/app_colors.dart';

/// Shows a brief floating snackbar. The app's `SnackBarThemeData` already sets
/// `behavior: floating` and the rounded background, so a plain `SnackBar` is
/// enough for success feedback.
///
/// Pass `error: true` for error messages (renders on the destructive red
/// `AppColors.expense`, since this app repurposes `ColorScheme.error` to a
/// monochrome token). This is the shared helper for the "always snackbar after
/// edit/delete" rule (see CLAUDE.md → List Row Interaction Rules) — reuse it
/// instead of inlining `ScaffoldMessenger.of(context).showSnackBar(...)`.
void showFeedbackSnackBar(BuildContext context, String message,
    {bool error = false}) {
  final appColors = Theme.of(context).extension<AppColors>()!;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? appColors.expense : null,
    ),
  );
}