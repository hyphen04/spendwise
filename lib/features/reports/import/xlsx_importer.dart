import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';
import 'import_models.dart';

class XlsxImporter {
  // ---------------------------------------------------------------------------
  // Public entry point
  // ---------------------------------------------------------------------------

  static List<ParsedRow> parse(List<int> bytes) {
    // Sanitize the xlsx zip before passing to the excel package.
    // The excel-4.0.6 parser throws when styles.xml contains a <numFmt> with
    // numFmtId < 164 (the built-in range). Some generators (Google Sheets,
    // Numbers, LibreOffice) legally write those IDs as redeclarations —
    // we simply drop them because the excel package already knows about them.
    final sanitized = _sanitizeBytes(bytes);

    final excel = Excel.decodeBytes(sanitized);

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

    // ---------- robust cell-value extractor ----------
    //
    // Fix 1: TextCellValue wraps a TextSpan — access .value.text, NOT
    //         .value.toString() which would give "TextSpan(text: …)".
    //
    // Fix 2: DateCellValue / DateTimeCellValue — the excel package returns
    //         these for date-formatted numeric cells. Convert them to an
    //         ISO-8601 string so _parseDate() can handle them.
    //
    // Fix 3: BoolCellValue — unlikely in our template but handle cleanly.
    String? cellStr(Data? cell) {
      final v = cell?.value;
      if (v == null) return null;
      if (v is TextCellValue) {
        // TextCellValue.value is a TextSpan; .text is the raw string.
        return v.value.text?.trim();
      }
      if (v is IntCellValue) return v.value.toString();
      if (v is DoubleCellValue) return v.value.toString();
      if (v is DateCellValue) {
        // Reconstruct as YYYY-MM-DD so _parseDate can parse it.
        final y = v.year.toString().padLeft(4, '0');
        final m = v.month.toString().padLeft(2, '0');
        final d = v.day.toString().padLeft(2, '0');
        return '$y-$m-$d';
      }
      if (v is DateTimeCellValue) {
        return DateTime(v.year, v.month, v.day, v.hour, v.minute, v.second)
            .toIso8601String();
      }
      if (v is BoolCellValue) return v.value.toString();
      if (v is FormulaCellValue) {
        // formula result — the formula text itself is not useful; return null
        // so the cell is treated as missing (better UX than a formula string).
        return null;
      }
      return v.toString().trim();
    }

    // ---------- row accessor ----------
    //
    // Fix 4: sheet.rows relies on _maxRows > 0 AND _maxColumns > 0. If the
    //         xlsx file was saved by an app that omits the 'r' attribute on
    //         row/cell XML elements (e.g. some Google Sheets / Numbers
    //         exports), _sheetData is wiped and sheet.rows returns [].
    //
    //         We therefore iterate sheet.row(i) for i in 0..<sheet.maxRows
    //         AND fall back to sheet.rows when maxRows is 0 (the template
    //         generator path, which always produces valid 'r' attributes).
    List<List<Data?>> getAllRows() {
      final maxRows = sheet.maxRows;
      if (maxRows > 0) {
        return List.generate(maxRows, (i) => sheet.row(i));
      }
      return sheet.rows;
    }

    final allRows = getAllRows();
    if (allRows.isEmpty) return [];

    // Extract header (row 0)
    final header = allRows[0]
        .map((c) => (cellStr(c) ?? '').toLowerCase())
        .toList();

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
    var skippedAsExample = 0;
    for (var i = 1; i < allRows.length; i++) {
      final row = allRows[i];

      // Skip entirely empty rows
      if (row.every((c) => c == null || c.value == null)) continue;

      // Skip EXAMPLE rows (template placeholder rows)
      final note = getCell(row, noteIdx) ?? '';
      if (note.toLowerCase().startsWith('example')) {
        skippedAsExample++;
        continue;
      }

      result.add(ParsedRow(
        rowIndex: i + 1, // 1-based for user-facing messages
        rawDate: getCell(row, dateIdx),
        rawTime: getCell(row, timeIdx),
        rawAmount: getCell(row, amountIdx),
        kind: getCell(row, kindIdx),
        account: getCell(row, accountIdx),
        category: getCell(row, categoryIdx),
        mode: getCell(row, modeIdx),
        note: getCell(row, noteIdx),
      ));
    }

    // If every non-empty row was an example row, give a specific sentinel
    // so the UI can show a helpful "delete the example rows" message.
    if (result.isEmpty && skippedAsExample > 0) {
      return [
        const ParsedRow(
          rowIndex: 0,
          note: '__ONLY_EXAMPLE_ROWS__',
        ),
      ];
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Sanitize xlsx bytes
  //
  // The excel-4.0.6 package throws when xl/styles.xml contains a <numFmt>
  // element whose numFmtId attribute is < 164. Built-in format IDs (0–163)
  // are part of the OOXML spec and should never appear in the custom <numFmts>
  // section, but several generators write them anyway. We strip those nodes
  // before decoding so the excel package never sees them.
  // ---------------------------------------------------------------------------

  static List<int> _sanitizeBytes(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      const stylesPath = 'xl/styles.xml';

      final stylesFile = archive.findFile(stylesPath);
      if (stylesFile == null) return bytes; // no styles.xml — leave unchanged

      final stylesXml = utf8.decode(stylesFile.content as List<int>);
      final doc = XmlDocument.parse(stylesXml);

      // Find all <numFmt> elements whose numFmtId is in the built-in range
      // (0–163) and remove them from their parent <numFmts> node.
      bool changed = false;
      for (final numFmts in doc.findAllElements('numFmts')) {
        final toRemove = numFmts.childElements
            .where((el) {
              if (el.name.local != 'numFmt') return false;
              final id = int.tryParse(el.getAttribute('numFmtId') ?? '');
              return id != null && id < 164;
            })
            .toList();

        for (final node in toRemove) {
          node.remove();
          changed = true;
        }
      }

      if (!changed) return bytes; // nothing was stripped — skip repack

      // Repack the archive with the patched styles.xml
      final newStylesBytes = utf8.encode(doc.toXmlString());
      final newArchive = Archive();
      for (final file in archive) {
        if (file.name == stylesPath) {
          newArchive.addFile(
            ArchiveFile(stylesPath, newStylesBytes.length, newStylesBytes),
          );
        } else {
          newArchive.addFile(file);
        }
      }
      return ZipEncoder().encode(newArchive) ?? bytes;
    } catch (_) {
      // If anything goes wrong during sanitization, fall back to the original
      // bytes and let the excel package throw its own error.
      return bytes;
    }
  }
}
