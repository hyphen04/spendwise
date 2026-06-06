import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/reports_repository.dart';

class JsonExporter {
  static Future<String> export(
      AppDatabase db, String from, String to) async {
    final repo = ReportsRepository(db);
    final rows = await repo.transactionsForExport(from: from, to: to);

    final data = {
      'exported_at': DateTime.now().toIso8601String(),
      'period': {'from': from, 'to': to},
      'count': rows.length,
      'transactions': rows
          .map((r) => {
                'id': r.id,
                'title': r.title,
                'amount': r.amount,
                'date': r.date,
                'kind': r.kind,
                'account': r.accountName,
                'category': r.categoryName,
                'mode': r.modeName,
                if (r.note != null && r.note!.isNotEmpty) 'note': r.note,
              })
          .toList(),
    };

    final dir = await getTemporaryDirectory();
    final stamp = _stamp(from, to);
    final file = File('${dir.path}/spendwise_$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file.path;
  }

  static String _stamp(String from, String to) =>
      '${from.substring(0, 10)}_${to.substring(0, 10)}';
}
