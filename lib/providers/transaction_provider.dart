import 'package:flutter/foundation.dart';
import '../models/expense_category.dart';
import '../services/database_helper.dart';
import '../models/transaction.dart';
import '../models/transaction_mode.dart';
import '../models/monthly_stats.dart';

class TransactionProvider with ChangeNotifier {
  List<Transaction> _transactions = [];
  List<ExpenseCategory> _categories = [];
  List<TransactionMode> _modes = [];

  List<Transaction> get transactions {
    final sorted = List<Transaction>.from(_transactions);
    sorted.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return sorted;
  }

  List<ExpenseCategory> get categories => _categories;
  List<TransactionMode> get modes => _modes;
  
  List<Transaction> get expenses => 
    transactions.where((t) => t.isExpense == true).toList();
  
  List<Transaction> get incomes => 
    transactions.where((t) => t.isExpense == false).toList();

  double get totalIncome {
    return incomes.fold(0, (sum, item) => sum + item.amount);
  }

  double get totalExpense {
    return expenses.fold(0, (sum, item) => sum + item.amount);
  }

  double get totalBalance => totalIncome - totalExpense;

  Map<ExpenseCategory, double> get categoryWiseExpenses {
    final map = <ExpenseCategory, double>{};
    for (var transaction in expenses) {
      final category = getCategoryById(transaction.categoryId);
      map[category] = (map[category] ?? 0) + transaction.amount;
    }
    return map;
  }

  Future<void> loadTransactions() async {
    try {
      debugPrint("Loading transactions...");
      _transactions = await DatabaseHelper.instance.getTransactions();
      _categories = await DatabaseHelper.instance.getCategories();
      _modes = await DatabaseHelper.instance.getTransactionModes();
      debugPrint("Loaded ${_transactions.length} transactions");
      debugPrint("Loaded ${_categories.length} categories");
      debugPrint("Loaded ${_modes.length} transaction modes");
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading transactions: $e');
      _transactions = [];
      notifyListeners();
    }
  }

  Future<void> addTransaction({
    required String title,
    required double amount,
    required bool isExpense,
    required DateTime dateTime,
    required int categoryId,
    required int modeId,
  }) async {
    try {
      debugPrint("Adding transaction: $title (isExpense: $isExpense)");
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      
      final transaction = Transaction(
        id: id,
        title: title,
        amount: amount,
        dateTime: dateTime,
        categoryId: categoryId,
        modeId: modeId,
        isExpense: isExpense,
      );
      
      debugPrint("Created transaction object with isExpense=${transaction.isExpense}");
      await DatabaseHelper.instance.insertTransaction(transaction);
      await loadTransactions();
    } catch (e) {
      debugPrint('Error adding transaction: $e');
      rethrow;
    }
  }

  Future<void> updateTransaction(Transaction transaction) async {
    try {
      await DatabaseHelper.instance.updateTransaction(transaction);
      await loadTransactions();
    } catch (e) {
      debugPrint('Error updating transaction: $e');
      rethrow;
    }
  }

  Future<void> deleteTransaction(String id) async {
    try {
      await DatabaseHelper.instance.deleteTransaction(id);
      await loadTransactions();
    } catch (e) {
      debugPrint('Error deleting transaction: $e');
      rethrow;
    }
  }

  ExpenseCategory getCategoryById(int id) {
    return _categories.firstWhere((category) => category.id == id);
  }

  List<Transaction> getTransactionsSorted() {
    final sorted = List<Transaction>.from(_transactions);
    sorted.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return sorted;
  }

  List<Transaction> getTransactionsForDateRange(DateTime start, DateTime end) {
    return _transactions.where((transaction) {
      return transaction.dateTime.isAfter(start.subtract(const Duration(days: 1))) &&
             transaction.dateTime.isBefore(end.add(const Duration(days: 1)));
    }).toList();
  }

  TransactionMode getModeById(int id) {
    return _modes.firstWhere((mode) => mode.id == id);
  }

  MonthlyStats getMonthlyStats(DateTime month) {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0);

    final monthTransactions = _transactions.where((t) =>
        t.dateTime.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
        t.dateTime.isBefore(endOfMonth.add(const Duration(days: 1)))).toList();

    final previousTransactions = _transactions.where((t) =>
        t.dateTime.isBefore(startOfMonth)).toList();
    final openingBalance = previousTransactions.fold(0.0, (sum, t) =>
        sum + (t.isExpense ? -t.amount : t.amount));

    final totalIncome = monthTransactions
        .where((t) => !t.isExpense)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final totalExpense = monthTransactions
        .where((t) => t.isExpense)
        .fold(0.0, (sum, t) => sum + t.amount);

    final categoryWiseExpenses = <String, double>{};
    for (var t in monthTransactions.where((t) => t.isExpense)) {
      final category = getCategoryById(t.categoryId);
      categoryWiseExpenses[category.name] = 
          (categoryWiseExpenses[category.name] ?? 0) + t.amount;
    }

    final incomeSourceWise = <String, double>{};
    for (var t in monthTransactions.where((t) => !t.isExpense)) {
      final mode = getModeById(t.modeId);
      incomeSourceWise[mode.name] = 
          (incomeSourceWise[mode.name] ?? 0) + t.amount;
    }

    final modeWiseBalances = <String, double>{};
    for (var mode in _modes) {
      final modeTransactions = _transactions.where((t) => 
        t.modeId == mode.id
      ).toList();
      
      double balance = 0.0;
      for (var t in modeTransactions) {
        balance += t.isExpense ? -t.amount : t.amount;
      }
      modeWiseBalances[mode.name] = balance;
    }

    return MonthlyStats(
      month: startOfMonth,
      openingBalance: openingBalance,
      closingBalance: openingBalance + totalIncome - totalExpense,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      categoryWiseExpenses: categoryWiseExpenses,
      incomeSourceWise: incomeSourceWise,
      modeWiseBalances: modeWiseBalances,
    );
  }

  List<DateTime> getAvailableMonths() {
    final months = _transactions.map((t) => 
      DateTime(t.dateTime.year, t.dateTime.month, 1)
    ).toSet().toList();
    
    if (months.isEmpty) {
      months.add(DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      ));
    }
    
    months.sort((a, b) => b.compareTo(a));
    return months;
  }
} 