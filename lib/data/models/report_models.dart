class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.color,
    required this.total,
  });
  final String categoryId;
  final String name;
  final String icon;
  final String color;
  final double total;
}

class ModeTotal {
  const ModeTotal({
    required this.modeId,
    required this.name,
    required this.icon,
    required this.total,
  });
  final String modeId;
  final String name;
  final String icon;
  final double total;
}

class MonthTotal {
  const MonthTotal({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });
  final int year;
  final int month;
  final double income;
  final double expense;
  double get net => income - expense;
}

class TagTotal {
  const TagTotal({
    required this.tagId,
    required this.name,
    required this.color,
    required this.total,
  });
  final String tagId;
  final String name;
  final String color;
  final double total;
}

class MonthlySummary {
  const MonthlySummary({
    required this.income,
    required this.expense,
    required this.topExpenseCategories,
    this.biggestSpendTitle,
    this.biggestSpendAmount,
    this.biggestSpendNote,
  });
  final double income;
  final double expense;
  final List<CategoryTotal> topExpenseCategories;
  final String? biggestSpendTitle;
  final double? biggestSpendAmount;
  final String? biggestSpendNote;
  double get net => income - expense;
}

class ExportRow {
  const ExportRow({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.kind,
    required this.accountName,
    required this.categoryName,
    required this.modeName,
    this.note,
  });
  final String id;
  final String title;
  final double amount;
  final String date;
  final String kind;
  final String accountName;
  final String categoryName;
  final String modeName;
  final String? note;
}
