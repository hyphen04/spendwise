import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/reports_repository.dart';
import 'export_service.dart';

class JsonExporter {
  static Future<String> export(AppDatabase db, ExportConfig config) async {
    final repo = ReportsRepository(db);
    final rows = await repo.transactionsForExport(
      from: config.fromIso,
      to: config.toIso,
      kind: config.kindFilter,
      accountIds: config.accountIds,
    );

    final cols = config.columns;

    final data = {
      'exported_at': DateTime.now().toIso8601String(),
      'period': {'from': config.fromIso.substring(0, 10), 'to': config.toIso.substring(0, 10)},
      if (config.kindFilter != null) 'kind_filter': config.kindFilter,
      if (config.presetAccountName != null) 'account': config.presetAccountName,
      'count': rows.length,
      'transactions': rows.map((r) {
        final map = <String, dynamic>{};
        if (cols.contains(ExportColumn.id)) map['id'] = r.id;
        if (cols.contains(ExportColumn.date)) map['date'] = r.date.substring(0, 10);
        if (cols.contains(ExportColumn.time)) {
          final dt = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
          map['time'] =
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }
        if (cols.contains(ExportColumn.title)) map['title'] = r.title;
        if (cols.contains(ExportColumn.amount)) map['amount'] = r.amount;
        if (cols.contains(ExportColumn.kind)) map['kind'] = r.kind;
        if (cols.contains(ExportColumn.account)) map['account'] = r.accountName;
        if (cols.contains(ExportColumn.category)) map['category'] = r.categoryName;
        if (cols.contains(ExportColumn.mode)) map['mode'] = r.modeName;
        if (cols.contains(ExportColumn.note) &&
            r.note != null &&
            r.note!.isNotEmpty) {
          map['note'] = r.note;
        }
        if (cols.contains(ExportColumn.createdAt)) {
          map['created_at'] =
              DateTime.fromMillisecondsSinceEpoch(r.createdAt).toIso8601String();
        }
        return map;
      }).toList(),
    };

    final dir = await getTemporaryDirectory();
    final stamp = _stamp(config);
    final file = File('${dir.path}/spendwise_$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file.path;
  }

  static String _stamp(ExportConfig c) =>
      '${c.fromIso.substring(0, 10)}_${c.toIso.substring(0, 10)}';
}
