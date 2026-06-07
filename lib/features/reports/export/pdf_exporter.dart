import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../data/db/app_database.dart';
import '../../../data/repositories/reports_repository.dart';
import 'export_service.dart';

class PdfExporter {
  static Future<String> export(AppDatabase db, ExportConfig config) async {
    final repo = ReportsRepository(db);
    final rows = await repo.transactionsForExport(
      from: config.fromIso,
      to: config.toIso,
      kind: config.kindFilter,
      accountIds: config.accountIds,
    );

    double totalIncome = 0, totalExpense = 0;
    for (final r in rows) {
      if (r.kind == 'income') totalIncome += r.amount;
      if (r.kind == 'expense') totalExpense += r.amount;
    }

    final cols = config.columns;

    // Build ordered column definitions for the table
    final colDefs = <({String header, String Function(dynamic r) value})>[];
    if (cols.contains(ExportColumn.date)) {
      colDefs.add((
        header: 'Date',
        value: (r) => (r.date as String).substring(0, 10),
      ));
    }
    if (cols.contains(ExportColumn.time)) {
      colDefs.add((
        header: 'Time',
        value: (r) {
          final dt = DateTime.fromMillisecondsSinceEpoch(r.createdAt as int);
          return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        },
      ));
    }
    if (cols.contains(ExportColumn.title)) {
      colDefs.add((
        header: 'Title',
        value: (r) {
          final s = r.title as String;
          return s.length > 25 ? '${s.substring(0, 23)}…' : s;
        },
      ));
    }
    if (cols.contains(ExportColumn.note)) {
      colDefs.add((
        header: 'Note',
        value: (r) {
          final s = (r.note as String?) ?? '';
          return s.length > 28 ? '${s.substring(0, 26)}…' : s;
        },
      ));
    }
    if (cols.contains(ExportColumn.category)) {
      colDefs.add((header: 'Category', value: (r) => r.categoryName as String));
    }
    if (cols.contains(ExportColumn.account)) {
      colDefs.add((header: 'Account', value: (r) => r.accountName as String));
    }
    if (cols.contains(ExportColumn.mode)) {
      colDefs.add((header: 'Mode', value: (r) => r.modeName as String));
    }
    if (cols.contains(ExportColumn.kind)) {
      colDefs.add((header: 'Type', value: (r) => r.kind as String));
    }
    if (cols.contains(ExportColumn.amount)) {
      colDefs.add((
        header: 'Amount',
        value: (r) => '₹${_fmt(r.amount as double)}',
      ));
    }
    if (cols.contains(ExportColumn.id)) {
      colDefs.add((
        header: 'ID',
        value: (r) {
          final s = r.id as String;
          return s.length > 8 ? s.substring(0, 8) : s;
        },
      ));
    }

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context ctx) => [
        pw.Text(
          config.presetAccountName != null
              ? 'SpendWise — ${config.presetAccountName} Statement'
              : 'SpendWise — Transaction Report',
          style:
              pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Period: ${config.fromIso.substring(0, 10)} to ${config.toIso.substring(0, 10)}',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        if (config.kindFilter != null)
          pw.Text(
            'Type: ${config.kindFilter}',
            style:
                const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        pw.Text(
          'Generated: ${DateTime.now().toString().substring(0, 16)}',
          style:
              const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 16),

        // Summary banner
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _summaryCol('Income', '₹${_fmt(totalIncome)}', PdfColors.green700),
              _summaryCol('Expense', '₹${_fmt(totalExpense)}', PdfColors.red700),
              _summaryCol(
                'Net',
                '₹${_fmt(totalIncome - totalExpense)}',
                totalIncome >= totalExpense
                    ? PdfColors.green700
                    : PdfColors.red700,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),

        pw.Text(
          'Transactions (${rows.length})',
          style:
              pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),

        if (colDefs.isNotEmpty)
          pw.TableHelper.fromTextArray(
            headers: colDefs.map((c) => c.header).toList(),
            data: rows
                .map((r) => colDefs.map((c) => c.value(r)).toList())
                .toList(),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            oddRowDecoration:
                const pw.BoxDecoration(color: PdfColors.grey100),
          ),
      ],
    ));

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final stamp = _stamp(config);
    final file = File('${dir.path}/spendwise_$stamp.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static pw.Widget _summaryCol(
          String label, String value, PdfColor color) =>
      pw.Column(
        children: [
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
          pw.SizedBox(height: 2),
          pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700)),
        ],
      );

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  static String _stamp(ExportConfig c) =>
      '${c.fromIso.substring(0, 10)}_${c.toIso.substring(0, 10)}';
}
