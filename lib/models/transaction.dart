import 'package:flutter/foundation.dart';

class Transaction {
  final String id;
  final String title;
  final double amount;
  final DateTime dateTime;
  final int categoryId;
  final int modeId;
  final bool isExpense;

  Transaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.dateTime,
    required this.categoryId,
    required this.modeId,
    required this.isExpense,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'date': dateTime.toIso8601String(),
      'categoryId': categoryId,
      'modeId': modeId,
      'isExpense': isExpense ? 1 : 0,
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    debugPrint('Creating transaction from map: $map');
    return Transaction(
      id: map['id'].toString(),
      title: map['title'],
      amount: map['amount'],
      dateTime: DateTime.parse(map['date']),
      categoryId: map['categoryId'],
      modeId: map['modeId'],
      isExpense: map['isExpense'] == 1 || map['isExpense'] == true,
    );
  }
} 