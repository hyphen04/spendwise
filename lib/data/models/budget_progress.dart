import '../db/app_database.dart';

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.spent,
    required this.month,
    this.category,
  });

  final Budget budget;
  final double spent;
  final DateTime month;
  final Category? category;

  double get effectiveAmount {
    if (budget.period == 'week') {
      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
      return budget.amount * (daysInMonth / 7);
    }
    if (budget.period == 'year') {
      return budget.amount / 12;
    }
    return budget.amount;
  }

  double get fraction =>
      effectiveAmount > 0 ? (spent / effectiveAmount).clamp(0.0, 1.0) : 0.0;
  bool get isOver => spent > effectiveAmount;
  String get categoryIcon => category?.icon ?? '📦';
  String get categoryName => category?.name ?? budget.categoryId;
  String get categoryColor => category?.color ?? '#475569';
}
