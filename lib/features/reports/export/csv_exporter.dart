import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/reports_repository.dart';
import 'export_service.dart';

class CsvExporter {
  static Future<String> export(AppDatabase db, ExportConfig config) async {
    final repo = ReportsRepository(db);
    final rows = await repo.transactionsForExport(
      from: config.fromIso,
      to: config.toIso,
      kind: config.kindFilter,
      accountIds: config.accountIds,
    );

    final cols = config.columns;
    final headers = <String>[];
    if (cols.contains(ExportColumn.date)) headers.add('Date');
    if (cols.contains(ExportColumn.time)) headers.add('Time');
    if (cols.contains(ExportColumn.amount)) headers.add('Amount');
    if (cols.contains(ExportColumn.kind)) headers.add('Type');
    if (cols.contains(ExportColumn.account)) headers.add('Account');
    if (cols.contains(ExportColumn.category)) headers.add('Category');
    if (cols.contains(ExportColumn.mode)) headers.add('Mode');
    if (cols.contains(ExportColumn.note)) headers.add('Note');
    if (cols.contains(ExportColumn.id)) headers.add('ID');
    if (cols.contains(ExportColumn.createdAt)) headers.add('Created At');

    final csvRows = <List<dynamic>>[
      headers,
      ...rows.map((r) {
        final row = <dynamic>[];
        if (cols.contains(ExportColumn.date)) row.add(r.date.substring(0, 10));
        if (cols.contains(ExportColumn.time)) {
          final dt = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
          row.add('${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}');
        }
        if (cols.contains(ExportColumn.amount)) row.add(r.amount);
        if (cols.contains(ExportColumn.kind)) row.add(r.kind);
        if (cols.contains(ExportColumn.account)) row.add(r.accountName);
        if (cols.contains(ExportColumn.category)) row.add(r.categoryName);
        if (cols.contains(ExportColumn.mode)) row.add(r.modeName);
        if (cols.contains(ExportColumn.note)) row.add(r.note ?? '');
        if (cols.contains(ExportColumn.id)) row.add(r.id);
        if (cols.contains(ExportColumn.createdAt)) {
          row.add(DateTime.fromMillisecondsSinceEpoch(r.createdAt)
              .toIso8601String());
        }
        return row;
      }),
    ];

    final csv = const ListToCsvConverter().convert(csvRows);
    final dir = await getTemporaryDirectory();
    final stamp = _stamp(config);
    final file = File('${dir.path}/spendwise_$stamp.csv');
    await file.writeAsString(csv);
    return file.path;
  }

  static String _stamp(ExportConfig c) =>
      '${c.fromIso.substring(0, 10)}_${c.toIso.substring(0, 10)}';
}
