class TransactionMode {
  final int? id;
  final String name;
  final String icon;

  TransactionMode({
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

  factory TransactionMode.fromMap(Map<String, dynamic> map) {
    return TransactionMode(
      id: map['id'],
      name: map['name'],
      icon: map['icon'],
    );
  }
} 