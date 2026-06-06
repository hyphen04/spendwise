class ExpenseCategory {
  final int? id;
  final String name;
  final String icon;

  ExpenseCategory({
    this.id,
    required this.name,
    required this.icon,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
    };
  }

  factory ExpenseCategory.fromMap(Map<String, dynamic> map) {
    return ExpenseCategory(
      id: map['id'],
      name: map['name'],
      icon: map['icon'],
    );
  }
} 