import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../../../data/db/app_database.dart';
import 'csv_importer.dart';
import 'import_models.dart';
import 'import_preview_sheet.dart';
import 'json_importer.dart';
import 'template_generator.dart';
import 'xlsx_importer.dart';

// ── Public entry point ─────────────────────────────────────────────────────

class ImportService {
  static Future<void> showImportSheet(
      BuildContext context, AppDatabase db) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ImportOptionsSheet(db: db),
    );
  }
}

// ── Options sheet ──────────────────────────────────────────────────────────

class _ImportOptionsSheet extends StatefulWidget {
  const _ImportOptionsSheet({required this.db});
  final AppDatabase db;

  @override
  State<_ImportOptionsSheet> createState() => _ImportOptionsSheetState();
}

enum _Step { options, loading }

class _ImportOptionsSheetState extends State<_ImportOptionsSheet> {
  ImportFormat _format = ImportFormat.xlsx;
  _Step _step = _Step.options;
  String _loadingMessage = 'Parsing file…';

  // ── Template download ───────────────────────────────────────────────────

  Future<void> _downloadTemplate() async {
    setState(() {
      _step = _Step.loading;
      _loadingMessage = 'Generating template…';
    });
    try {
      final String path;
      switch (_format) {
        case ImportFormat.csv:
          path = await TemplateGenerator.generateCsv(widget.db);
        case ImportFormat.xlsx:
          path = await TemplateGenerator.generateXlsx(widget.db);
        case ImportFormat.json:
          path = await TemplateGenerator.generateJson(widget.db);
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: 'SpendWise Import Template',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template generation failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _step = _Step.options);
    }
  }

  // ── File picker + parse + import ────────────────────────────────────────

  Future<void> _pickAndImport() async {
    // 1. Pick file
    final ext = switch (_format) {
      ImportFormat.csv => 'csv',
      ImportFormat.xlsx => 'xlsx',
      ImportFormat.json => 'json',
    };

    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [ext],
        withData: true,
        allowMultiple: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file picker: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;

    // 2. Parse
    setState(() {
      _step = _Step.loading;
      _loadingMessage = 'Parsing file…';
    });

    List<ParsedRow> parsed;
    try {
      parsed = await _parse(picked);
    } catch (e) {
      if (mounted) {
        setState(() => _step = _Step.options);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Parse error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Check for structural errors (bad file format)
    if (parsed.length == 1 && (parsed.first.note?.startsWith('__') ?? false)) {
      if (mounted) {
        setState(() => _step = _Step.options);
        final msg = switch (parsed.first.note) {
          '__HEADER_ERROR__' =>
            'Missing required columns. Expected: date, amount, kind, account, category, mode.',
          '__NO_TRANSACTIONS_SHEET__' =>
            'No "Transactions" sheet found. Download the template and fill that sheet.',
          '__JSON_PARSE_ERROR__' => 'Invalid JSON file.',
          '__JSON_NOT_OBJECT__' => 'JSON must be an object with a "transactions" array.',
          '__NO_TRANSACTIONS_KEY__' =>
            'JSON must contain a "transactions" array.',
          _ => 'Unrecognised file format.',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    if (parsed.isEmpty) {
      if (mounted) {
        setState(() => _step = _Step.options);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No data rows found in the file.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // 3. Resolve + validate
    setState(() => _loadingMessage = 'Resolving references…');
    final accounts = await widget.db.accountsDao.getAllActive();
    final categories = await widget.db.categoriesDao.getAllActive();
    final modes = await widget.db.modesDao.getAllActive();
    final preview = _resolveAndValidate(parsed, accounts, categories, modes);

    if (!mounted) return;
    setState(() => _step = _Step.options);

    // 4. Show preview sheet
    final confirmed = await ImportPreviewSheet.show(context, preview);
    if (confirmed != true || !mounted) return;

    // 5. Perform import
    if (!mounted) return;
    setState(() {
      _step = _Step.loading;
      _loadingMessage = 'Importing…';
    });

    int count = 0;
    try {
      count = await _performImport(widget.db, preview);
    } catch (e) {
      if (mounted) {
        setState(() => _step = _Step.options);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported $count transaction${count == 1 ? '' : 's'} successfully.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Parse dispatch ──────────────────────────────────────────────────────

  Future<List<ParsedRow>> _parse(PlatformFile picked) async {
    switch (_format) {
      case ImportFormat.csv:
        final bytes = picked.bytes;
        final String content;
        if (bytes != null) {
          content = String.fromCharCodes(bytes);
        } else {
          content = await File(picked.path!).readAsString();
        }
        return CsvImporter.parse(content);

      case ImportFormat.xlsx:
        final bytes = picked.bytes;
        final List<int> data;
        if (bytes != null) {
          data = bytes;
        } else {
          data = await File(picked.path!).readAsBytes();
        }
        return XlsxImporter.parse(data);

      case ImportFormat.json:
        final bytes = picked.bytes;
        final String content;
        if (bytes != null) {
          content = String.fromCharCodes(bytes);
        } else {
          content = await File(picked.path!).readAsString();
        }
        return JsonImporter.parse(content);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.75,
      builder: (_, controller) {
        if (_step == _Step.loading) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_loadingMessage,
                  style: tt.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          );
        }

        return ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          children: [
            // Title
            Text(
              'Import Transactions',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick a file format, download the template, fill it in, then import.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            // ── Format ───────────────────────────────────────────────────
            _sectionLabel('Format', cs, tt),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (fmt, label, icon) in [
                  (ImportFormat.xlsx, 'Excel', Icons.table_chart_outlined),
                  (ImportFormat.csv, 'CSV', Icons.view_list_outlined),
                  (ImportFormat.json, 'JSON', Icons.data_object_outlined),
                ])
                  _chip(
                    label: label,
                    icon: Icon(icon, size: 16),
                    selected: _format == fmt,
                    onSelected: () => setState(() => _format = fmt),
                    cs: cs,
                    tt: tt,
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Format hint
            Text(
              switch (_format) {
                ImportFormat.xlsx =>
                  'Recommended. 4 sheets: Transactions (editable) + Accounts, Categories, Modes (reference, pre-populated with your data).',
                ImportFormat.csv =>
                  'Single sheet. Includes your accounts, categories, and modes as comments at the bottom for reference.',
                ImportFormat.json =>
                  'Full envelope format with a reference section. Great for round-tripping data.',
              },
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),

            const SizedBox(height: 24),

            // ── Actions ───────────────────────────────────────────────────
            _sectionLabel('Actions', cs, tt),
            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Download Template'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _pickAndImport,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('Pick File & Import'),
            ),

            const SizedBox(height: 20),
            Text(
              '• Required columns: date, amount, kind, account, category, mode\n'
              '• kind must be "expense" or "income"\n'
              '• date format: YYYY-MM-DD or ISO-8601\n'
              '• Missing accounts/categories/modes are created automatically',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionLabel(String title, ColorScheme cs, TextTheme tt) => Text(
        title.toUpperCase(),
        style: tt.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      );

  Widget _chip({
    required String label,
    required Widget icon,
    required bool selected,
    required VoidCallback onSelected,
    required ColorScheme cs,
    required TextTheme tt,
  }) {
    final labelColor = selected ? cs.onPrimary : cs.onSurface;
    return FilterChip(
      avatar: icon,
      label: Text(label),
      labelStyle: TextStyle(
        color: labelColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

// ── Resolution + validation ────────────────────────────────────────────────

ImportPreview _resolveAndValidate(
  List<ParsedRow> parsed,
  List<Account> accounts,
  List<Category> categories,
  List<Mode> modes,
) {
  // Build case-insensitive name → id lookup maps
  final accountMap = {
    for (final a in accounts) a.name.trim().toLowerCase(): a.id
  };
  final categoryMap = {
    for (final c in categories) c.name.trim().toLowerCase(): c.id
  };
  final modeMap = {
    for (final m in modes) m.name.trim().toLowerCase(): m.id
  };

  final validRows = <ResolvedRow>[];
  final errors = <ImportError>[];
  final newAccountNames = <String>{};
  final newCategoryNames = <String>{};
  final newModeNames = <String>{};
  // categoryLowerName → {kind: count} for inferring kind of new categories
  final categoryKindUsage = <String, Map<String, int>>{};

  for (final row in parsed) {
    final rawDate = row.rawDate?.trim() ?? '';
    final rawAmount = row.rawAmount?.trim() ?? '';
    final kind = row.kind?.trim().toLowerCase() ?? '';
    final account = row.account?.trim() ?? '';
    final category = row.category?.trim() ?? '';
    final mode = row.mode?.trim() ?? '';

    // ── Required field checks ──────────────────────────────────────────
    if (rawDate.isEmpty) {
      errors.add(ImportError(rowIndex: row.rowIndex, message: 'Missing date'));
      continue;
    }
    if (rawAmount.isEmpty) {
      errors.add(ImportError(rowIndex: row.rowIndex, message: 'Missing amount'));
      continue;
    }
    if (account.isEmpty) {
      errors.add(ImportError(rowIndex: row.rowIndex, message: 'Missing account'));
      continue;
    }
    if (category.isEmpty) {
      errors.add(ImportError(rowIndex: row.rowIndex, message: 'Missing category'));
      continue;
    }
    if (mode.isEmpty) {
      errors.add(ImportError(rowIndex: row.rowIndex, message: 'Missing mode'));
      continue;
    }

    // ── Date ──────────────────────────────────────────────────────────
    final parsedDate = _parseDate(rawDate, row.rawTime?.trim());
    if (parsedDate == null) {
      errors.add(ImportError(
          rowIndex: row.rowIndex,
          message: 'Invalid date "$rawDate". Use YYYY-MM-DD.'));
      continue;
    }

    // ── Amount ────────────────────────────────────────────────────────
    final amount = double.tryParse(rawAmount.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      errors.add(ImportError(
          rowIndex: row.rowIndex,
          message: 'Invalid amount "$rawAmount".'));
      continue;
    }
    if (amount > 10000000) {
      errors.add(ImportError(
          rowIndex: row.rowIndex,
          message: 'Amount $amount exceeds the maximum (10,000,000).'));
      continue;
    }

    // ── Kind ──────────────────────────────────────────────────────────
    if (kind == 'transfer') {
      errors.add(ImportError(
          rowIndex: row.rowIndex,
          message: 'Transfer transactions are not supported in import.'));
      continue;
    }
    if (kind != 'expense' && kind != 'income') {
      errors.add(ImportError(
          rowIndex: row.rowIndex,
          message: 'Invalid kind "$kind". Must be "expense" or "income".'));
      continue;
    }

    // ── Resolve entity references ─────────────────────────────────────
    final accountId = accountMap[account.toLowerCase()];
    if (accountId == null) newAccountNames.add(account);

    final categoryId = categoryMap[category.toLowerCase()];
    if (categoryId == null) {
      newCategoryNames.add(category);
      final usage = categoryKindUsage
          .putIfAbsent(category.toLowerCase(), () => {});
      usage[kind] = (usage[kind] ?? 0) + 1;
    }

    final modeId = modeMap[mode.toLowerCase()];
    if (modeId == null) newModeNames.add(mode);

    // title falls back to category name when blank
    final title = (row.title?.trim().isNotEmpty == true)
        ? row.title!.trim()
        : category;

    validRows.add(ResolvedRow(
      rowIndex: row.rowIndex,
      existingAccountId: accountId,
      accountName: account,
      existingCategoryId: categoryId,
      categoryName: category,
      existingModeId: modeId,
      modeName: mode,
      title: title,
      amount: amount,
      kind: kind,
      transactionDate: parsedDate.toIso8601String(),
      note: row.note?.trim() ?? '',
    ));
  }

  // Infer kind for new categories
  final categoryKindHint = <String, String>{
    for (final e in categoryKindUsage.entries)
      e.key: e.value.length == 1 ? e.value.keys.first : 'both',
  };

  return ImportPreview(
    validRows: validRows,
    errors: errors,
    newAccountNames: newAccountNames,
    newCategoryNames: newCategoryNames,
    newModeNames: newModeNames,
    categoryKindHint: categoryKindHint,
  );
}

DateTime? _parseDate(String rawDate, String? rawTime) {
  var dt = DateTime.tryParse(rawDate);
  if (dt == null) return null;

  if (rawTime != null && rawTime.isNotEmpty) {
    final parts = rawTime.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      dt = DateTime(dt.year, dt.month, dt.day, hour, minute);
    }
  } else {
    dt = DateTime(dt.year, dt.month, dt.day);
  }
  return dt;
}

// ── Atomic bulk insert ─────────────────────────────────────────────────────

const _accountColors = [
  '#0284C7', '#059669', '#DC2626', '#D97706', '#7C3AED', '#EC4899'
];
const _categoryColors = [
  '#DC2626', '#D97706', '#059669', '#0284C7', '#7C3AED', '#EC4899'
];

Future<int> _performImport(AppDatabase db, ImportPreview preview) async {
  const uuid = Uuid();
  final now = DateTime.now().millisecondsSinceEpoch;

  await db.transaction(() async {
    // Create new accounts
    final newAccountIds = <String, String>{}; // lowercased name → id
    var colorIdx = 0;
    for (final name in preview.newAccountNames) {
      final id = uuid.v4();
      await db.accountsDao.upsert(AccountsCompanion.insert(
        id: id,
        name: name,
        icon: '🏦',
        color: _accountColors[colorIdx % _accountColors.length],
        openingBalance: const Value(0.0),
        currency: const Value('INR'),
        createdAt: now,
        updatedAt: now,
      ));
      newAccountIds[name.toLowerCase()] = id;
      colorIdx++;
    }

    // Create new categories
    final newCategoryIds = <String, String>{};
    colorIdx = 0;
    for (final name in preview.newCategoryNames) {
      final id = uuid.v4();
      final kind = preview.categoryKindHint[name.toLowerCase()] ?? 'expense';
      final icon = kind == 'income' ? '💰' : '💸';
      await db.categoriesDao.upsert(CategoriesCompanion.insert(
        id: id,
        name: name,
        icon: icon,
        color: Value(_categoryColors[colorIdx % _categoryColors.length]),
        kind: Value(kind),
        createdAt: now,
        updatedAt: now,
      ));
      newCategoryIds[name.toLowerCase()] = id;
      colorIdx++;
    }

    // Create new modes
    final newModeIds = <String, String>{};
    for (final name in preview.newModeNames) {
      final id = uuid.v4();
      await db.modesDao.upsert(ModesCompanion.insert(
        id: id,
        name: name,
        icon: '💳',
        createdAt: now,
        updatedAt: now,
      ));
      newModeIds[name.toLowerCase()] = id;
    }

    // Insert transactions
    for (final row in preview.validRows) {
      final accountId = row.existingAccountId ??
          newAccountIds[row.accountName.toLowerCase()]!;
      final categoryId = row.existingCategoryId ??
          newCategoryIds[row.categoryName.toLowerCase()]!;
      final modeId =
          row.existingModeId ?? newModeIds[row.modeName.toLowerCase()]!;

      await db.transactionsDao.upsert(TransactionsCompanion.insert(
        id: uuid.v4(),
        title: row.title,
        amount: row.amount,
        transactionDate: row.transactionDate,
        accountId: accountId,
        categoryId: categoryId,
        modeId: modeId,
        kind: Value(row.kind),
        note: Value(row.note),
        createdAt: now,
        updatedAt: now,
      ));
    }
  });

  return preview.validRows.length;
}
