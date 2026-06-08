import 'package:csv/csv.dart';
import 'import_models.dart';

class CsvImporter {
  static List<ParsedRow> parse(String content) {
    // Normalise line endings
    final normalised = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Split into raw lines so we can strip comment/blank lines before CSV parsing
    final lines = normalised.split('\n');
    final dataLines = lines.where((l) {
      final t = l.trim();
      return t.isNotEmpty && !t.startsWith('#');
    }).toList();

    if (dataLines.isEmpty) return [];

    final csvContent = dataLines.join('\n');
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(csvContent);

    if (rows.isEmpty) return [];

    // First row is header
    final header =
        rows[0].map((e) => e.toString().trim().toLowerCase()).toList();

    int colIdx(String name) => header.indexOf(name);

    final dateIdx = colIdx('date');
    final timeIdx = colIdx('time');
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
      // Missing required header columns — return a single error row
      return [
        const ParsedRow(
          rowIndex: 0,
          rawDate: null,
          note: '__HEADER_ERROR__',
        ),
      ];
    }

    String? cellStr(List<dynamic> row, int idx) {
      if (idx < 0 || idx >= row.length) return null;
      final v = row[idx].toString().trim();
      return v.isEmpty ? null : v;
    }

    final result = <ParsedRow>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      // Skip EXAMPLE rows (sample data from the template)
      final note = cellStr(row, noteIdx) ?? '';
      if (note.toLowerCase().startsWith('example')) continue;

      result.add(ParsedRow(
        rowIndex: i,
        rawDate: cellStr(row, dateIdx),
        rawTime: cellStr(row, timeIdx),
        rawAmount: cellStr(row, amountIdx),
        kind: cellStr(row, kindIdx),
        account: cellStr(row, accountIdx),
        category: cellStr(row, categoryIdx),
        mode: cellStr(row, modeIdx),
        note: cellStr(row, noteIdx),
      ));
    }
    return result;
  }
}
