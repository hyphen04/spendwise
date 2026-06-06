class MonthlyStats {
  final DateTime month;
  final double openingBalance;
  final double closingBalance;
  final double totalIncome;
  final double totalExpense;
  final Map<String, double> categoryWiseExpenses;
  final Map<String, double> incomeSourceWise;
  final Map<String, double> modeWiseBalances;

  MonthlyStats({
    required this.month,
    required this.openingBalance,
    required this.closingBalance,
    required this.totalIncome,
    required this.totalExpense,
    required this.categoryWiseExpenses,
    required this.incomeSourceWise,
    required this.modeWiseBalances,
  });
} 