import '../db/app_database.dart';

/// A transaction with its denormalized account / category / mode names,
/// looked up at the Dart layer by combining separate watch streams.
class TransactionRow {
  const TransactionRow({
    required this.transaction,
    this.account,
    this.category,
    this.mode,
    this.transferPairAccount,
  });

  final Transaction transaction;
  final Account? account;
  final Category? category;
  final Mode? mode;
  final Account? transferPairAccount;

  String get accountName => account?.name ?? '—';
  String get accountIcon => account?.icon ?? '🏦';
  String get categoryName => category?.name ?? '—';
  String get categoryIcon => category?.icon ?? '📦';
  String get categoryColor => category?.color ?? '#475569';
  String get modeIcon => mode?.icon ?? '💳';
  String get modeName => mode?.name ?? '—';
  String get transferPairAccountName => transferPairAccount?.name ?? '—';
}
