class HomeSummary {
  const HomeSummary({required this.income, required this.expense});
  const HomeSummary.zero() : income = 0, expense = 0;

  final double income;
  final double expense;
  double get net => income - expense;
}
