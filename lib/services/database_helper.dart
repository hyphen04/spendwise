import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sql;
import 'package:path/path.dart';
import '../models/expense_category.dart';
import '../models/transaction.dart';
import '../models/transaction_mode.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static sql.Database? _database;

  DatabaseHelper._init();

  Future<sql.Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expenses.db');
    return _database!;
  }

  Future<sql.Database> _initDB(String filePath) async {
    final dbPath = await sql.getDatabasesPath();
    final path = join(dbPath, filePath);

    return await sql.openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(sql.Database db, int version) async {
    try {
      debugPrint("Creating database tables...");
      
      // Drop existing tables if they exist
      await db.execute('DROP TABLE IF EXISTS transactions');
      await db.execute('DROP TABLE IF EXISTS categories');
      await db.execute('DROP TABLE IF EXISTS transaction_modes');
      
      // Create tables
      await db.execute('''
        CREATE TABLE transaction_modes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          icon TEXT NOT NULL
        )
      ''');
      debugPrint("Transaction modes table created");

      await db.execute('''
        CREATE TABLE categories(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          icon TEXT NOT NULL
        )
      ''');
      debugPrint("Categories table created");

      await db.execute('''
        CREATE TABLE transactions(
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          amount REAL NOT NULL,
          date TEXT NOT NULL,
          categoryId INTEGER NOT NULL,
          modeId INTEGER NOT NULL,
          isExpense INTEGER NOT NULL,
          FOREIGN KEY (categoryId) REFERENCES categories (id),
          FOREIGN KEY (modeId) REFERENCES transaction_modes (id)
        )
      ''');
      debugPrint("Transactions table created");

      // Insert default transaction modes
      final modes = [
        {'name': 'Cash', 'icon': '💵'},
        {'name': 'Online', 'icon': '🌐'},
        {'name': 'Card', 'icon': '💳'},
        {'name': 'Other', 'icon': '📱'},
      ];

      for (var mode in modes) {
        await db.insert('transaction_modes', mode);
      }
      debugPrint("Default transaction modes inserted");
      
      // Insert default categories
      final categories = [
        {'name': 'Food', 'icon': '🍴'},
        {'name': 'Transport', 'icon': '🚗'},
        {'name': 'Rent', 'icon': '🏠'},
        {'name': 'Other', 'icon': '📦'},
      ];

      for (var category in categories) {
        await db.insert('categories', category);
      }
      debugPrint("Default categories inserted");
      
    } catch (e) {
      debugPrint("Error creating database: $e");
      debugPrint("Stack trace: ${StackTrace.current}");
    }
  }

  Future<List<ExpenseCategory>> getCategories() async {
    final db = await instance.database;
    final result = await db.query('categories');
    return result.map((json) => ExpenseCategory.fromMap(json)).toList();
  }

  Future<ExpenseCategory> insertCategory(ExpenseCategory category) async {
    final db = await instance.database;
    await db.insert('categories', category.toMap());
    return category;
  }

  Future<List<Transaction>> getTransactions() async {
    final db = await instance.database;
    try {
      final result = await db.query(
        'transactions',
        orderBy: 'date DESC',
      );
      debugPrint("Raw transaction data: $result");
      
      return result.map((map) {
        final newMap = Map<String, dynamic>.from(map);
        newMap['isExpense'] = newMap['isExpense'] == 1;
        debugPrint('Processing transaction: $newMap');
        return Transaction.fromMap(newMap);
      }).toList();
    } catch (e) {
      debugPrint('Error getting transactions: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      return [];
    }
  }

  Future<void> insertTransaction(Transaction transaction) async {
    final db = await instance.database;
    try {
      final map = Map<String, dynamic>.from(transaction.toMap());
      map['isExpense'] = transaction.isExpense ? 1 : 0;
      
      await db.insert(
        'transactions',
        map,
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error inserting transaction: $e');
      throw Exception('Failed to insert transaction: $e');
    }
  }

  Future<void> deleteTransaction(String id) async {
    final db = await instance.database;
    await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateTransaction(Transaction transaction) async {
    final db = await instance.database;
    try {
      final map = Map<String, dynamic>.from(transaction.toMap());
      map['isExpense'] = transaction.isExpense ? 1 : 0;
      
      await db.update(
        'transactions',
        map,
        where: 'id = ?',
        whereArgs: [transaction.id],
      );
    } catch (e) {
      debugPrint('Error updating transaction: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      throw Exception('Failed to update transaction: $e');
    }
  }

  // Add method to check if database exists and its tables
  Future<void> checkDatabase() async {
    final db = await instance.database;
    
    // Check if tables exist
    final tables = await db.query(
      'sqlite_master',
      where: 'type = ?',
      whereArgs: ['table'],
    );
    debugPrint("Database tables: ${tables.map((t) => t['name'])}"); // Debug print

    // Check categories
    final categories = await db.query('categories');
    debugPrint("Categories in database: $categories"); // Debug print

    // Check transactions
    final transactions = await db.query('transactions');
    debugPrint("Transactions in database: $transactions"); // Debug print
  }

  Future<void> resetDatabase() async {
    try {
      debugPrint("Resetting database...");
      final dbPath = await sql.getDatabasesPath();
      final path = join(dbPath, 'expenses.db');
      
      // Delete the database
      await sql.deleteDatabase(path);
      debugPrint("Database deleted");
      
      // Reinitialize the database
      _database = null;
      await database;
      debugPrint("Database reinitialized");
      
      await checkDatabase();
    } catch (e) {
      debugPrint("Error resetting database: $e");
      debugPrint("Stack trace: ${StackTrace.current}");
    }
  }

  Future<List<TransactionMode>> getTransactionModes() async {
    final db = await instance.database;
    final result = await db.query('transaction_modes');
    return result.map((json) => TransactionMode.fromMap(json)).toList();
  }

  Future<List<Map<String, dynamic>>> getTransactionsRaw() async {
    final db = await database;
    return db.query('transactions');
  }

  Future<List<Map<String, dynamic>>> getCategoriesRaw() async {
    final db = await database;
    return db.query('categories');
  }

  Future<List<Map<String, dynamic>>> getModesRaw() async {
    final db = await database;
    return db.query('transaction_modes');
  }

  Future<void> importData(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      // Clear existing data
      await txn.delete('transactions');
      await txn.delete('categories');
      await txn.delete('transaction_modes');

      // Import categories
      for (var category in data['categories']) {
        await txn.insert('categories', category);
      }

      // Import modes
      for (var mode in data['modes']) {
        await txn.insert('transaction_modes', mode);
      }

      // Import transactions
      for (var transaction in data['transactions']) {
        await txn.insert('transactions', transaction);
      }
    });
  }
} 