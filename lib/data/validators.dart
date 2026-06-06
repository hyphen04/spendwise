class AppValidators {
  // ── Amount ─────────────────────────────────────────────────────────────

  static String? amount(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Enter an amount.';
    final cleaned = raw.trim().replaceAll(',', '');
    final value = double.tryParse(cleaned);
    if (value == null) return 'Enter a valid number.';
    if (value <= 0) return 'Amount must be greater than ₹0.';
    if (value > 10000000) return 'Amount seems too large. Please verify.';
    return null;
  }

  // ── Title ───────────────────────────────────────────────────────────────

  static String? title(String? value) {
    final t = value?.trim() ?? '';
    if (t.isEmpty) return 'Title cannot be empty.';
    if (t.length > 80) return 'Title must be 80 characters or less.';
    return null;
  }

  // ── Note (optional, max 500 chars) ────────────────────────────────────

  static String? note(String? value) {
    if (value != null && value.length > 500) {
      return 'Note must be 500 characters or less.';
    }
    return null;
  }

  // ── Entity names (category, mode, account, tag) ───────────────────────

  static String? entityName(String? value, {int maxLen = 40}) {
    final t = value?.trim() ?? '';
    if (t.isEmpty) return 'Name cannot be empty.';
    if (t.length > maxLen) return 'Name must be $maxLen characters or less.';
    return null;
  }

  // ── Budget amount ───────────────────────────────────────────────────────

  static String? budgetAmount(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Enter a budget amount.';
    final value = double.tryParse(raw.trim().replaceAll(',', ''));
    if (value == null) return 'Enter a valid number.';
    if (value <= 0) return 'Budget must be greater than ₹0.';
    return null;
  }

  // ── Transfer ────────────────────────────────────────────────────────────

  static String? transferAccounts(
    String? fromId,
    String? toId,
  ) {
    if (fromId == null || fromId.isEmpty) return 'Select a source account.';
    if (toId == null || toId.isEmpty) return 'Select a destination account.';
    if (fromId == toId) {
      return 'Source and destination accounts must be different.';
    }
    return null;
  }

  // ── Date / time ─────────────────────────────────────────────────────────

  static String? dateNotInFuture(DateTime? value) {
    if (value == null) return 'Please select a date.';
    if (value.isAfter(DateTime.now())) {
      return 'Date cannot be in the future.';
    }
    return null;
  }

  // ── Required selection ───────────────────────────────────────────────

  static String? requiredId(String? id, String fieldName) {
    if (id == null || id.isEmpty) return 'Please select a $fieldName.';
    return null;
  }

}
