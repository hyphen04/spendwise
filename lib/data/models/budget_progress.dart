import '../db/app_database.dart';

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.spent,
    this.category,
  });

  final Budget budget;
  final double spent;
  final Category? category;

  double get fraction =>
      budget.amount > 0 ? (spent / budget.amount).clamp(0.0, 1.0) : 0.0;
  bool get isOver => spent > budget.amount;
  String get categoryIcon => category?.icon ?? '📦';
  String get categoryName => category?.name ?? budget.categoryId;
  String get categoryColor => category?.color ?? '#475569';
}
