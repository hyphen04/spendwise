import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../data/db/app_database.dart';
import '../../../data/repositories/reports_repository.dart';

class PdfExporter {
  static Future<String> export(
      AppDatabase db, String from, String to) async {
    final repo = ReportsRepository(db);
    final rows = await repo.transactionsForExport(from: from, to: to);

    double totalIncome = 0, totalExpense = 0;
    for (final r in rows) {
      if (r.kind == 'income') totalIncome += r.amount;
      if (r.kind == 'expense') totalExpense += r.amount;
    }

    final doc = pw.Document();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context ctx) => [
        // Header
        pw.Text('SpendWise — Transaction Report',
            style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
            'Period: ${from.substring(0, 10)} to ${to.substring(0, 10)}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        pw.Text(
            'Generated: ${DateTime.now().toString().substring(0, 16)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 16),

        // Summary
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _summaryCol('Income', 'Rs.${_fmt(totalIncome)}', PdfColors.green700),
              _summaryCol('Expense', 'Rs.${_fmt(totalExpense)}', PdfColors.red700),
              _summaryCol(
                  'Net',
                  'Rs.${_fmt(totalIncome - totalExpense)}',
                  totalIncome >= totalExpense
                      ? PdfColors.green700
                      : PdfColors.red700),
            ],
          ),
        ),
        pw.SizedBox(height: 20),

        // Table
        pw.Text('Transactions (${rows.length})',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Note', 'Category', 'Account', 'Kind', 'Amount'],
          data: rows
              .map((r) {
                    final note = r.note != null && r.note!.isNotEmpty
                        ? r.note!
                        : r.title;
                    return [
                      r.date.substring(0, 10),
                      note.length > 30 ? '${note.substring(0, 28)}...' : note,
                      r.categoryName,
                      r.accountName,
                      r.kind,
                      'Rs.${_fmt(r.amount)}',
                    ];
                  })
              .toList(),
          headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey300),
          rowDecoration: const pw.BoxDecoration(),
          oddRowDecoration:
              const pw.BoxDecoration(color: PdfColors.grey100),
          columnWidths: const {
            0: pw.FixedColumnWidth(60),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1.5),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FixedColumnWidth(55),
            5: pw.FixedColumnWidth(70),
          },
        ),
      ],
    ));

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final stamp = '${from.substring(0, 10)}_${to.substring(0, 10)}';
    final file = File('${dir.path}/spendwise_$stamp.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static pw.Widget _summaryCol(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: color)),
        pw.SizedBox(height: 2),
        pw.Text(label,
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey700)),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(2);
}
