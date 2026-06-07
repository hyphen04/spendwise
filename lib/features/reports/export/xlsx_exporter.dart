import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/reports_repository.dart';
import 'export_service.dart';

class XlsxExporter {
  static Future<String> export(AppDatabase db, ExportConfig config) async {
    final repo = ReportsRepository(db);
    final rows = await repo.transactionsForExport(
      from: config.fromIso,
      to: config.toIso,
      kind: config.kindFilter,
      accountIds: config.accountIds,
    );

    final cols = config.columns;
    final excel = Excel.createExcel();
    final sheet = excel['Transactions'];

    final headers = <String>[];
    if (cols.contains(ExportColumn.date)) headers.add('Date');
    if (cols.contains(ExportColumn.time)) headers.add('Time');
    if (cols.contains(ExportColumn.title)) headers.add('Title');
    if (cols.contains(ExportColumn.amount)) headers.add('Amount');
    if (cols.contains(ExportColumn.kind)) headers.add('Type');
    if (cols.contains(ExportColumn.account)) headers.add('Account');
    if (cols.contains(ExportColumn.category)) headers.add('Category');
    if (cols.contains(ExportColumn.mode)) headers.add('Mode');
    if (cols.contains(ExportColumn.note)) headers.add('Note');
    if (cols.contains(ExportColumn.id)) headers.add('ID');
    if (cols.contains(ExportColumn.createdAt)) headers.add('Created At');

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final r in rows) {
      final row = <CellValue>[];
      if (cols.contains(ExportColumn.date)) {
        row.add(TextCellValue(r.date.substring(0, 10)));
      }
      if (cols.contains(ExportColumn.time)) {
        final dt = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
        row.add(TextCellValue(
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'));
      }
      if (cols.contains(ExportColumn.title)) row.add(TextCellValue(r.title));
      if (cols.contains(ExportColumn.amount)) row.add(DoubleCellValue(r.amount));
      if (cols.contains(ExportColumn.kind)) row.add(TextCellValue(r.kind));
      if (cols.contains(ExportColumn.account)) row.add(TextCellValue(r.accountName));
      if (cols.contains(ExportColumn.category)) row.add(TextCellValue(r.categoryName));
      if (cols.contains(ExportColumn.mode)) row.add(TextCellValue(r.modeName));
      if (cols.contains(ExportColumn.note)) row.add(TextCellValue(r.note ?? ''));
      if (cols.contains(ExportColumn.id)) row.add(TextCellValue(r.id));
      if (cols.contains(ExportColumn.createdAt)) {
        row.add(TextCellValue(
            DateTime.fromMillisecondsSinceEpoch(r.createdAt).toIso8601String()));
      }
      sheet.appendRow(row);
    }

    for (int i = 0; i < headers.length; i++) {
      sheet.setColumnWidth(i, 18.0);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode XLSX');

    final dir = await getTemporaryDirectory();
    final stamp = _stamp(config);
    final file = File('${dir.path}/spendwise_$stamp.xlsx');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static String _stamp(ExportConfig c) =>
      '${c.fromIso.substring(0, 10)}_${c.toIso.substring(0, 10)}';
}
