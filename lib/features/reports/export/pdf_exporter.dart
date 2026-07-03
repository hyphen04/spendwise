import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../data/db/app_database.dart';
import '../../../data/repositories/reports_repository.dart';
import 'export_service.dart';

class PdfExporter {
  static Future<String> export(AppDatabase db, ExportConfig config) async {
    final entity = config.entities.first;
    if (entity == ExportEntity.dues) {
      return _exportDues(db, config);
    } else if (entity == ExportEntity.transactions) {
      return _exportTransactions(db, config);
    } else {
      throw Exception('PDF format is only supported for Transactions and Dues & Tabs.');
    }
  }

  static Future<String> _exportTransactions(AppDatabase db, ExportConfig config) async {
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
        value: (r) => 'Rs${_fmt(r.amount as double)}',
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
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Period: ${config.fromIso.substring(0, 10)} to ${config.toIso.substring(0, 10)}',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        if (config.kindFilter != null)
          pw.Text(
            'Type: ${config.kindFilter}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Income: Rs${_fmt(totalIncome)}',
                style: pw.TextStyle(color: PdfColors.green700)),
            pw.Text('Expense: Rs${_fmt(totalExpense)}',
                style: pw.TextStyle(color: PdfColors.red700)),
            pw.Text(
              'Net: Rs${_fmt(totalIncome - totalExpense)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: colDefs.map((d) => d.header).toList(),
          data: rows.map((r) => colDefs.map((d) => d.value(r)).toList()).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Generated on ${DateTime.now().toIso8601String().substring(0, 16).replaceAll('T', ' ')}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
        ),
      ],
    ));

    return _write(config, doc, 'transactions');
  }

  static Future<String> _exportDues(AppDatabase db, ExportConfig config) async {
    final entries = await db.duesDao.getAllEntriesWithContact();

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context ctx) => [
        pw.Text(
          'SpendWise — Dues & Tabs',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Contact', 'Amount', 'Type', 'Date', 'Note', 'Settled'],
          data: entries.map((e) => [
            e.contact.name,
            'Rs${_fmt(e.entry.amount)}',
            e.entry.direction == 'payable' ? 'You Owe' : 'They Owe',
            e.entry.entryDate.substring(0, 10),
            e.entry.note,
            e.entry.isSettled ? 'Yes' : 'No',
          ]).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Generated on ${DateTime.now().toIso8601String().substring(0, 16).replaceAll('T', ' ')}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
        ),
      ],
    ));

    return _write(config, doc, 'dues');
  }

  static Future<String> _write(ExportConfig config, pw.Document doc, String suffix) async {
    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final stamp = _stamp(config);
    final file = File('${dir.path}/spendwise_${suffix}_$stamp.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  static String _stamp(ExportConfig c) =>
      '${c.fromIso.substring(0, 10)}_${c.toIso.substring(0, 10)}';
}
