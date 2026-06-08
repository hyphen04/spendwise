import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/db/app_database.dart';

/// Generates downloadable import templates pre-populated with the user's
/// current accounts, categories, and modes as reference data.
class TemplateGenerator {
  static const _exampleNote = 'EXAMPLE — delete before importing';

  // ── XLSX ───────────────────────────────────────────────────────────────────

  static Future<String> generateXlsx(AppDatabase db) async {
    final accounts = await db.accountsDao.getAllActive();
    final categories = await db.categoriesDao.getAllActive();
    final modes = await db.modesDao.getAllActive();

    final excel = Excel.createExcel();
    // Rename the default sheet to Transactions
    excel.rename('Sheet1', 'Transactions');

    // ── Sheet 1: Transactions ─────────────────────────────────────────────
    final txSheet = excel['Transactions'];
    txSheet.appendRow([
      'date', 'time', 'amount', 'kind', 'account', 'category', 'mode', 'note',
    ].map(TextCellValue.new).toList());

    final firstAccount = accounts.isNotEmpty ? accounts.first.name : 'Cash';
    final firstExpenseCat = categories
        .where((c) => c.kind == 'expense' || c.kind == 'both')
        .firstOrNull
        ?.name ?? 'Food & Dining';
    final firstIncomeCat = categories
        .where((c) => c.kind == 'income' || c.kind == 'both')
        .firstOrNull
        ?.name ?? 'Income';
    final firstMode = modes.isNotEmpty ? modes.first.name : 'Cash';

    txSheet.appendRow([
      TextCellValue('2026-06-01'),
      TextCellValue('14:30'),
      TextCellValue('250'),
      TextCellValue('expense'),
      TextCellValue(firstAccount),
      TextCellValue(firstExpenseCat),
      TextCellValue(firstMode),
      TextCellValue(_exampleNote),
    ]);
    txSheet.appendRow([
      TextCellValue('2026-06-01'),
      TextCellValue('09:00'),
      TextCellValue('50000'),
      TextCellValue('income'),
      TextCellValue(firstAccount),
      TextCellValue(firstIncomeCat),
      TextCellValue(firstMode),
      TextCellValue(_exampleNote),
    ]);

    // ── Sheet 2: Accounts (reference) ────────────────────────────────────
    final accSheet = excel['Accounts (Reference)'];
    accSheet.appendRow(
      ['name', 'icon', 'currency', 'opening_balance']
          .map(TextCellValue.new)
          .toList(),
    );
    for (final a in accounts) {
      accSheet.appendRow([
        TextCellValue(a.name),
        TextCellValue(a.icon),
        TextCellValue(a.currency),
        TextCellValue(a.openingBalance.toStringAsFixed(2)),
      ]);
    }

    // ── Sheet 3: Categories (reference) ───────────────────────────────────
    final catSheet = excel['Categories (Reference)'];
    catSheet.appendRow(
      ['name', 'icon', 'kind'].map(TextCellValue.new).toList(),
    );
    for (final c in categories) {
      catSheet.appendRow([
        TextCellValue(c.name),
        TextCellValue(c.icon),
        TextCellValue(c.kind),
      ]);
    }

    // ── Sheet 4: Modes (reference) ────────────────────────────────────────
    final modeSheet = excel['Modes (Reference)'];
    modeSheet.appendRow(
      ['name', 'icon'].map(TextCellValue.new).toList(),
    );
    for (final m in modes) {
      modeSheet.appendRow([
        TextCellValue(m.name),
        TextCellValue(m.icon),
      ]);
    }

    // Column widths for the Transactions sheet
    for (var i = 0; i < 8; i++) {
      txSheet.setColumnWidth(i, i == 7 ? 28.0 : 16.0);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode template XLSX');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/spendwise_import_template.xlsx');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ── CSV ────────────────────────────────────────────────────────────────────

  static Future<String> generateCsv(AppDatabase db) async {
    final accounts = await db.accountsDao.getAllActive();
    final categories = await db.categoriesDao.getAllActive();
    final modes = await db.modesDao.getAllActive();

    final firstAccount = accounts.isNotEmpty ? accounts.first.name : 'Cash';
    final firstExpenseCat = categories
        .where((c) => c.kind == 'expense' || c.kind == 'both')
        .firstOrNull
        ?.name ?? 'Food & Dining';
    final firstIncomeCat = categories
        .where((c) => c.kind == 'income' || c.kind == 'both')
        .firstOrNull
        ?.name ?? 'Income';
    final firstMode = modes.isNotEmpty ? modes.first.name : 'Cash';

    final rows = <List<dynamic>>[
      ['date', 'time', 'amount', 'kind', 'account', 'category', 'mode', 'note'],
      ['2026-06-01', '14:30', 250, 'expense', firstAccount, firstExpenseCat, firstMode, _exampleNote],
      ['2026-06-01', '09:00', 50000, 'income', firstAccount, firstIncomeCat, firstMode, _exampleNote],
    ];

    final csv = const ListToCsvConverter().convert(rows);

    final buffer = StringBuffer(csv);
    buffer.writeln();
    buffer.writeln();
    buffer.writeln('# ── Reference: Accounts ──────────────────────────────────────────');
    buffer.writeln('# ${accounts.map((a) => a.name).join(', ')}');
    buffer.writeln();
    buffer.writeln('# ── Reference: Categories ────────────────────────────────────────');
    for (final kind in ['expense', 'income', 'both']) {
      final names = categories
          .where((c) => c.kind == kind)
          .map((c) => c.name)
          .join(', ');
      if (names.isNotEmpty) buffer.writeln('# $kind: $names');
    }
    buffer.writeln();
    buffer.writeln('# ── Reference: Modes ─────────────────────────────────────────────');
    buffer.writeln('# ${modes.map((m) => m.name).join(', ')}');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/spendwise_import_template.csv');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  // ── JSON ───────────────────────────────────────────────────────────────────

  static Future<String> generateJson(AppDatabase db) async {
    final accounts = await db.accountsDao.getAllActive();
    final categories = await db.categoriesDao.getAllActive();
    final modes = await db.modesDao.getAllActive();

    final firstAccount = accounts.isNotEmpty ? accounts.first.name : 'Cash';
    final firstExpenseCat = categories
        .where((c) => c.kind == 'expense' || c.kind == 'both')
        .firstOrNull
        ?.name ?? 'Food & Dining';
    final firstMode = modes.isNotEmpty ? modes.first.name : 'Cash';

    final data = {
      'spendwise_template_version': 1,
      'generated_at': DateTime.now().toIso8601String(),
      'reference': {
        'accounts': accounts
            .map((a) => {'name': a.name, 'icon': a.icon, 'currency': a.currency})
            .toList(),
        'categories': categories
            .map((c) => {'name': c.name, 'icon': c.icon, 'kind': c.kind})
            .toList(),
        'modes': modes
            .map((m) => {'name': m.name, 'icon': m.icon})
            .toList(),
      },
      'transactions': [
        {
          'date': '2026-06-01',
          'time': '14:30',
          'amount': 250,
          'kind': 'expense',
          'account': firstAccount,
          'category': firstExpenseCat,
          'mode': firstMode,
          'note': _exampleNote,
        },
      ],
    };

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/spendwise_import_template.json');
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data));
    return file.path;
  }
}
