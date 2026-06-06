import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/reports_repository.dart';

class XlsxExporter {
  static Future<String> export(
      AppDatabase db, String from, String to) async {
    final repo = ReportsRepository(db);
    final rows = await repo.transactionsForExport(from: from, to: to);

    final excel = Excel.createExcel();
    final sheet = excel['Transactions'];

    // Header row
    final headers = [
      'Date', 'Title', 'Amount', 'Kind', 'Account', 'Category', 'Mode', 'Note',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final r in rows) {
      sheet.appendRow([
        TextCellValue(r.date.substring(0, 10)),
        TextCellValue(r.title),
        DoubleCellValue(r.amount),
        TextCellValue(r.kind),
        TextCellValue(r.accountName),
        TextCellValue(r.categoryName),
        TextCellValue(r.modeName),
        TextCellValue(r.note ?? ''),
      ]);
    }

    // Auto-width hint (excel package doesn't auto-size, but we set column widths)
    for (int i = 0; i < headers.length; i++) {
      sheet.setColumnWidth(i, 18.0);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode XLSX');

    final dir = await getTemporaryDirectory();
    final stamp = '${from.substring(0, 10)}_${to.substring(0, 10)}';
    final file = File('${dir.path}/spendwise_$stamp.xlsx');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
