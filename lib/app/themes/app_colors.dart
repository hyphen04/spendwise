import 'package:flutter/material.dart';

/// Semantic color tokens for SpendWise. Applied as a ThemeExtension so every
/// widget can access them via `Theme.of(context).extension<AppColors>()!`.
class AppColors extends ThemeExtension<AppColors> {
  final Color income;
  final Color onIncome;
  final Color incomeContainer;
  final Color onIncomeContainer;

  final Color expense;
  final Color onExpense;
  final Color expenseContainer;
  final Color onExpenseContainer;

  final Color transfer;
  final Color onTransfer;
  final Color transferContainer;
  final Color onTransferContainer;

  const AppColors({
    required this.income,
    required this.onIncome,
    required this.incomeContainer,
    required this.onIncomeContainer,
    required this.expense,
    required this.onExpense,
    required this.expenseContainer,
    required this.onExpenseContainer,
    required this.transfer,
    required this.onTransfer,
    required this.transferContainer,
    required this.onTransferContainer,
  });

  // ── Monochrome ("mibu") palette ─────────────────────────────────────────────
  // Fully monochrome: income / expense / transfer all resolve to the text color
  // so amounts render in black (light) or off-white (dark). The +/− sign carries
  // the directional meaning. Containers map to the neutral surface fill.
  static AppColors light() => const AppColors(
        income: Color(0xFF0A0A0A),
        onIncome: Color(0xFFFFFFFF),
        incomeContainer: Color(0xFFF2F2F2),
        onIncomeContainer: Color(0xFF0A0A0A),
        expense: Color(0xFF0A0A0A),
        onExpense: Color(0xFFFFFFFF),
        expenseContainer: Color(0xFFF2F2F2),
        onExpenseContainer: Color(0xFF0A0A0A),
        transfer: Color(0xFF0A0A0A),
        onTransfer: Color(0xFFFFFFFF),
        transferContainer: Color(0xFFF2F2F2),
        onTransferContainer: Color(0xFF0A0A0A),
      );

  static AppColors dark() => const AppColors(
        income: Color(0xFFF5F5F5),
        onIncome: Color(0xFF0A0A0A),
        incomeContainer: Color(0xFF1C1C1E),
        onIncomeContainer: Color(0xFFF5F5F5),
        expense: Color(0xFFF5F5F5),
        onExpense: Color(0xFF0A0A0A),
        expenseContainer: Color(0xFF1C1C1E),
        onExpenseContainer: Color(0xFFF5F5F5),
        transfer: Color(0xFFF5F5F5),
        onTransfer: Color(0xFF0A0A0A),
        transferContainer: Color(0xFF1C1C1E),
        onTransferContainer: Color(0xFFF5F5F5),
      );

  /// Convenience: return the foreground color for a transaction kind string.
  Color forKind(String kind) {
    switch (kind) {
      case 'income':
        return income;
      case 'expense':
        return expense;
      case 'transfer':
        return transfer;
      default:
        return expense;
    }
  }

  /// Container color for a transaction kind.
  Color containerForKind(String kind) {
    switch (kind) {
      case 'income':
        return incomeContainer;
      case 'expense':
        return expenseContainer;
      case 'transfer':
        return transferContainer;
      default:
        return expenseContainer;
    }
  }

  @override
  AppColors copyWith({
    Color? income,
    Color? onIncome,
    Color? incomeContainer,
    Color? onIncomeContainer,
    Color? expense,
    Color? onExpense,
    Color? expenseContainer,
    Color? onExpenseContainer,
    Color? transfer,
    Color? onTransfer,
    Color? transferContainer,
    Color? onTransferContainer,
  }) {
    return AppColors(
      income: income ?? this.income,
      onIncome: onIncome ?? this.onIncome,
      incomeContainer: incomeContainer ?? this.incomeContainer,
      onIncomeContainer: onIncomeContainer ?? this.onIncomeContainer,
      expense: expense ?? this.expense,
      onExpense: onExpense ?? this.onExpense,
      expenseContainer: expenseContainer ?? this.expenseContainer,
      onExpenseContainer: onExpenseContainer ?? this.onExpenseContainer,
      transfer: transfer ?? this.transfer,
      onTransfer: onTransfer ?? this.onTransfer,
      transferContainer: transferContainer ?? this.transferContainer,
      onTransferContainer: onTransferContainer ?? this.onTransferContainer,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      income: Color.lerp(income, other.income, t)!,
      onIncome: Color.lerp(onIncome, other.onIncome, t)!,
      incomeContainer: Color.lerp(incomeContainer, other.incomeContainer, t)!,
      onIncomeContainer: Color.lerp(onIncomeContainer, other.onIncomeContainer, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      onExpense: Color.lerp(onExpense, other.onExpense, t)!,
      expenseContainer: Color.lerp(expenseContainer, other.expenseContainer, t)!,
      onExpenseContainer: Color.lerp(onExpenseContainer, other.onExpenseContainer, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      onTransfer: Color.lerp(onTransfer, other.onTransfer, t)!,
      transferContainer: Color.lerp(transferContainer, other.transferContainer, t)!,
      onTransferContainer: Color.lerp(onTransferContainer, other.onTransferContainer, t)!,
    );
  }
}
