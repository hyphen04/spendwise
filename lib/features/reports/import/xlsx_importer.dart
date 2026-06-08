import 'package:excel/excel.dart';
import 'import_models.dart';

class XlsxImporter {
  static List<ParsedRow> parse(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);

    // Find the 'Transactions' sheet (case-insensitive)
    String? sheetName;
    for (final k in excel.tables.keys) {
      if (k.toLowerCase() == 'transactions') {
        sheetName = k;
        break;
      }
    }
    if (sheetName == null) {
      return [
        const ParsedRow(
          rowIndex: 0,
          note: '__NO_TRANSACTIONS_SHEET__',
        ),
      ];
    }

    final sheet = excel.tables[sheetName]!;
    final allRows = sheet.rows;
    if (allRows.isEmpty) return [];

    // Extract header
    String? cellStr(Data? cell) {
      final v = cell?.value;
      if (v == null) return null;
      if (v is TextCellValue) return v.value.toString().trim();
      if (v is IntCellValue) return v.value.toString();
      if (v is DoubleCellValue) return v.value.toString();
      return v.toString().trim();
    }

    final header = allRows[0]
        .map((c) => (cellStr(c) ?? '').toLowerCase())
        .toList();

    int colIdx(String name) => header.indexOf(name);

    final dateIdx = colIdx('date');
    final timeIdx = colIdx('time');
    final titleIdx = colIdx('title');
    final amountIdx = colIdx('amount');
    final kindIdx = colIdx('kind');
    final accountIdx = colIdx('account');
    final categoryIdx = colIdx('category');
    final modeIdx = colIdx('mode');
    final noteIdx = colIdx('note');

    if (dateIdx < 0 ||
        amountIdx < 0 ||
        kindIdx < 0 ||
        accountIdx < 0 ||
        categoryIdx < 0 ||
        modeIdx < 0) {
      return [
        const ParsedRow(
          rowIndex: 0,
          note: '__HEADER_ERROR__',
        ),
      ];
    }

    String? getCell(List<Data?> row, int idx) {
      if (idx < 0 || idx >= row.length) return null;
      final v = cellStr(row[idx]);
      return (v == null || v.isEmpty) ? null : v;
    }

    final result = <ParsedRow>[];
    for (var i = 1; i < allRows.length; i++) {
      final row = allRows[i];

      // Skip entirely empty rows
      if (row.every((c) => c == null || (c.value == null))) continue;

      // Skip EXAMPLE rows
      final note = getCell(row, noteIdx) ?? '';
      if (note.toLowerCase().startsWith('example')) continue;

      result.add(ParsedRow(
        rowIndex: i + 1, // 1-based for user-facing messages
        rawDate: getCell(row, dateIdx),
        rawTime: getCell(row, timeIdx),
        title: getCell(row, titleIdx),
        rawAmount: getCell(row, amountIdx),
        kind: getCell(row, kindIdx),
        account: getCell(row, accountIdx),
        category: getCell(row, categoryIdx),
        mode: getCell(row, modeIdx),
        note: getCell(row, noteIdx),
      ));
    }
    return result;
  }
}
