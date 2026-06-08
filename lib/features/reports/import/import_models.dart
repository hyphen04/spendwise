enum ImportFormat { csv, xlsx, json }

class ParsedRow {
  final int rowIndex;
  final String? rawDate;
  final String? rawTime;
  final String? title;
  final String? rawAmount;
  final String? kind;
  final String? account;
  final String? category;
  final String? mode;
  final String? note;

  const ParsedRow({
    required this.rowIndex,
    this.rawDate,
    this.rawTime,
    this.title,
    this.rawAmount,
    this.kind,
    this.account,
    this.category,
    this.mode,
    this.note,
  });
}

class ResolvedRow {
  final int rowIndex;
  final String? existingAccountId;
  final String accountName;
  final String? existingCategoryId;
  final String categoryName;
  final String? existingModeId;
  final String modeName;
  final String title;
  final double amount;
  final String kind;
  final String transactionDate; // ISO-8601
  final String note;

  const ResolvedRow({
    required this.rowIndex,
    this.existingAccountId,
    required this.accountName,
    this.existingCategoryId,
    required this.categoryName,
    this.existingModeId,
    required this.modeName,
    required this.title,
    required this.amount,
    required this.kind,
    required this.transactionDate,
    required this.note,
  });
}

class ImportError {
  final int rowIndex;
  final String message;
  const ImportError({required this.rowIndex, required this.message});
}

class ImportPreview {
  final List<ResolvedRow> validRows;
  final List<ImportError> errors;
  final Set<String> newAccountNames;
  final Set<String> newCategoryNames;
  final Set<String> newModeNames;
  // lowercased category name → inferred kind for auto-creation
  final Map<String, String> categoryKindHint;

  const ImportPreview({
    required this.validRows,
    required this.errors,
    required this.newAccountNames,
    required this.newCategoryNames,
    required this.newModeNames,
    required this.categoryKindHint,
  });

  int get validCount => validRows.length;
  int get errorCount => errors.length;
  int get newEntityCount =>
      newAccountNames.length + newCategoryNames.length + newModeNames.length;
}
