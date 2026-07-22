import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../data/db/app_database.dart';
import 'export_service.dart';

class JsonExporter {
  static Future<String> export(AppDatabase db, ExportConfig config) async {
    final data = <String, dynamic>{
      'exported_at': DateTime.now().toIso8601String(),
      'app_version': '2.7.0',
      'data': <String, dynamic>{},
    };

    final dataMap = data['data'] as Map<String, dynamic>;

    if (config.entities.contains(ExportEntity.accounts)) {
      final rows = await db.select(db.accounts).get();
      dataMap['accounts'] = rows.map((r) => r.toJson()).toList();
    }

    if (config.entities.contains(ExportEntity.categories)) {
      final rows = await db.select(db.categories).get();
      dataMap['categories'] = rows.map((r) => r.toJson()).toList();
    }

    if (config.entities.contains(ExportEntity.modes)) {
      final rows = await db.select(db.modes).get();
      dataMap['modes'] = rows.map((r) => r.toJson()).toList();
    }

    if (config.entities.contains(ExportEntity.budgets)) {
      final rows = await db.select(db.budgets).get();
      dataMap['budgets'] = rows.map((r) => r.toJson()).toList();
    }

    if (config.entities.contains(ExportEntity.dues)) {
      final contacts = await db.select(db.dueContacts).get();
      dataMap['due_contacts'] = contacts.map((r) => r.toJson()).toList();

      final entries = await db.select(db.dueEntries).get();
      dataMap['due_entries'] = entries.map((r) => r.toJson()).toList();

      final settlements = await db.select(db.dueSettlements).get();
      dataMap['due_settlements'] = settlements.map((r) => r.toJson()).toList();
    }

    if (config.entities.contains(ExportEntity.transactions)) {
      final rows = await db.select(db.transactions).get();
      dataMap['transactions'] = rows.map((r) => r.toJson()).toList();
    }

    final dir = await getTemporaryDirectory();
    final stamp = _stamp(config);
    final file = File('${dir.path}/spendwise_$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file.path;
  }

  static String _stamp(ExportConfig c) =>
      '${c.fromIso.substring(0, 10)}_${c.toIso.substring(0, 10)}';
}
