import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/db/app_database.dart';
import 'csv_exporter.dart';
import 'json_exporter.dart';
import 'pdf_exporter.dart';
import 'xlsx_exporter.dart';

enum ExportFormat { json, csv, xlsx, pdf }

class ExportService {
  static Future<void> showExportSheet(
    BuildContext context,
    AppDatabase db, {
    required String from,
    required String to,
  }) async {
    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      builder: (_) => const _ExportFormatSheet(),
    );
    if (format == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await _export(db, format, from, to);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: 'SpendWise Export',
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  static Future<String> _export(
      AppDatabase db, ExportFormat format, String from, String to) {
    return switch (format) {
      ExportFormat.json => JsonExporter.export(db, from, to),
      ExportFormat.csv => CsvExporter.export(db, from, to),
      ExportFormat.xlsx => XlsxExporter.export(db, from, to),
      ExportFormat.pdf => PdfExporter.export(db, from, to),
    };
  }
}

class _ExportFormatSheet extends StatelessWidget {
  const _ExportFormatSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('Export as',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          ..._formats.map((f) => ListTile(
                leading: Icon(f.$3),
                title: Text(f.$1),
                subtitle: Text(f.$2),
                onTap: () => Navigator.pop(context, f.$4),
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static const _formats = [
    ('PDF Report', 'Formatted report with summary table', Icons.picture_as_pdf_outlined, ExportFormat.pdf),
    ('Excel (.xlsx)', 'Multi-column spreadsheet', Icons.table_chart_outlined, ExportFormat.xlsx),
    ('CSV', 'Comma-separated values', Icons.view_list_outlined, ExportFormat.csv),
    ('JSON', 'Full data for re-import', Icons.data_object_outlined, ExportFormat.json),
  ];
}
