import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../data/db/app_database.dart';

class JsonImporter {
  static Future<void> importData(AppDatabase db, String content) async {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid backup format: Not a JSON object.');
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid backup format: Missing "data" key.');
    }

    await db.transaction(() async {
      // 1. Core Lookups
      if (data.containsKey('accounts')) {
        for (final item in data['accounts']) {
          await db.into(db.accounts).insert(
                Account.fromJson(item),
                mode: InsertMode.insertOrReplace,
              );
        }
      }

      if (data.containsKey('categories')) {
        for (final item in data['categories']) {
          await db.into(db.categories).insert(
                Category.fromJson(item),
                mode: InsertMode.insertOrReplace,
              );
        }
      }

      if (data.containsKey('modes')) {
        for (final item in data['modes']) {
          await db.into(db.modes).insert(
                Mode.fromJson(item),
                mode: InsertMode.insertOrReplace,
              );
        }
      }

      // 2. Dependents
      if (data.containsKey('budgets')) {
        for (final item in data['budgets']) {
          await db.into(db.budgets).insert(
                Budget.fromJson(item),
                mode: InsertMode.insertOrReplace,
              );
        }
      }

      if (data.containsKey('due_contacts')) {
        for (final item in data['due_contacts']) {
          await db.into(db.dueContacts).insert(
                DueContact.fromJson(item),
                mode: InsertMode.insertOrReplace,
              );
        }
      }

      // 3. Foreign key constraints dependents
      if (data.containsKey('transactions')) {
        for (final item in data['transactions']) {
          await db.into(db.transactions).insert(
                Transaction.fromJson(item),
                mode: InsertMode.insertOrReplace,
              );
        }
      }

      if (data.containsKey('due_entries')) {
        for (final item in data['due_entries']) {
          await db.into(db.dueEntries).insert(
                DueEntry.fromJson(item),
                mode: InsertMode.insertOrReplace,
              );
        }
      }

      if (data.containsKey('due_settlements')) {
        for (final item in data['due_settlements']) {
          await db.into(db.dueSettlements).insert(
                DueSettlement.fromJson(item),
                mode: InsertMode.insertOrReplace,
              );
        }
      }
    });
  }
}
