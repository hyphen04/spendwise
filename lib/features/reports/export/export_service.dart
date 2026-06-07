import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/db/app_database.dart';
import '../../../state/manage_providers.dart';
import 'csv_exporter.dart';
import 'json_exporter.dart';
import 'pdf_exporter.dart';
import 'xlsx_exporter.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum ExportFormat { pdf, xlsx, csv, json }

enum ExportDateRange { thisMonth, lastMonth, last3Months, last6Months, thisYear, custom }

enum ExportColumn {
  date,
  time,
  title,
  amount,
  kind,
  account,
  category,
  mode,
  note,
  id,
  createdAt,
}

// ── ExportConfig ──────────────────────────────────────────────────────────────

class ExportConfig {
  ExportConfig({
    this.dateRange = ExportDateRange.thisMonth,
    this.customFrom,
    this.customTo,
    this.kindFilter,
    this.accountIds,
    Set<ExportColumn>? columns,
    this.format = ExportFormat.csv,
    this.presetAccountId,
    this.presetAccountName,
    DateTime? referenceDate,
  })  : columns = columns ?? _defaultColumns,
        _ref = referenceDate ?? DateTime.now();

  ExportDateRange dateRange;
  DateTime? customFrom;
  DateTime? customTo;
  String? kindFilter;          // null = all, 'income', 'expense'
  Set<String>? accountIds;     // null = all accounts
  Set<ExportColumn> columns;
  ExportFormat format;
  final String? presetAccountId;
  final String? presetAccountName;
  final DateTime _ref;

  static const _defaultColumns = {
    ExportColumn.date,
    ExportColumn.amount,
    ExportColumn.kind,
    ExportColumn.account,
    ExportColumn.category,
    ExportColumn.note,
  };

  String get fromIso {
    switch (dateRange) {
      case ExportDateRange.thisMonth:
        return DateTime(_ref.year, _ref.month).toIso8601String();
      case ExportDateRange.lastMonth:
        final d = DateTime(_ref.year, _ref.month - 1);
        return DateTime(d.year, d.month).toIso8601String();
      case ExportDateRange.last3Months:
        return DateTime(_ref.year, _ref.month - 2).toIso8601String();
      case ExportDateRange.last6Months:
        return DateTime(_ref.year, _ref.month - 5).toIso8601String();
      case ExportDateRange.thisYear:
        return DateTime(_ref.year).toIso8601String();
      case ExportDateRange.custom:
        return (customFrom ?? DateTime(_ref.year, _ref.month)).toIso8601String();
    }
  }

  String get toIso {
    switch (dateRange) {
      case ExportDateRange.thisMonth:
        return DateTime(_ref.year, _ref.month + 1).toIso8601String();
      case ExportDateRange.lastMonth:
        final d = DateTime(_ref.year, _ref.month - 1);
        return DateTime(d.year, d.month + 1).toIso8601String();
      case ExportDateRange.last3Months:
        return DateTime(_ref.year, _ref.month + 1).toIso8601String();
      case ExportDateRange.last6Months:
        return DateTime(_ref.year, _ref.month + 1).toIso8601String();
      case ExportDateRange.thisYear:
        return DateTime(_ref.year + 1).toIso8601String();
      case ExportDateRange.custom:
        return (customTo != null
                ? DateTime(customTo!.year, customTo!.month, customTo!.day + 1)
                : DateTime(_ref.year, _ref.month + 1))
            .toIso8601String();
    }
  }

  String get rangeLabel {
    switch (dateRange) {
      case ExportDateRange.thisMonth:
        return 'This Month';
      case ExportDateRange.lastMonth:
        return 'Last Month';
      case ExportDateRange.last3Months:
        return 'Last 3 Months';
      case ExportDateRange.last6Months:
        return 'Last 6 Months';
      case ExportDateRange.thisYear:
        return 'This Year';
      case ExportDateRange.custom:
        final f = customFrom;
        final t = customTo;
        if (f != null && t != null) {
          return '${_fmtDate(f)} – ${_fmtDate(t)}';
        }
        return 'Custom';
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

// ── ExportService ─────────────────────────────────────────────────────────────

class ExportService {
  static Future<void> showExportSheet(
    BuildContext context,
    AppDatabase db, {
    required String defaultFrom,
    required String defaultTo,
    String? presetAccountId,
    String? presetAccountName,
  }) async {
    final now = DateTime.now();
    final initialConfig = ExportConfig(
      referenceDate: now,
      presetAccountId: presetAccountId,
      presetAccountName: presetAccountName,
      accountIds: presetAccountId != null ? {presetAccountId} : null,
    );

    final config = await showModalBottomSheet<ExportConfig>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExportOptionsSheet(config: initialConfig),
    );
    if (config == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await _export(db, config);
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

  static Future<String> _export(AppDatabase db, ExportConfig config) {
    return switch (config.format) {
      ExportFormat.json => JsonExporter.export(db, config),
      ExportFormat.csv => CsvExporter.export(db, config),
      ExportFormat.xlsx => XlsxExporter.export(db, config),
      ExportFormat.pdf => PdfExporter.export(db, config),
    };
  }
}

// ── Export Options Sheet ──────────────────────────────────────────────────────

class _ExportOptionsSheet extends ConsumerStatefulWidget {
  const _ExportOptionsSheet({required this.config});
  final ExportConfig config;

  @override
  ConsumerState<_ExportOptionsSheet> createState() =>
      _ExportOptionsSheetState();
}

class _ExportOptionsSheetState extends ConsumerState<_ExportOptionsSheet> {
  late ExportConfig _cfg;

  @override
  void initState() {
    super.initState();
    _cfg = widget.config;
  }

  // Chip with explicit label color based on selected state — FilterChip in
  // Flutter 3.x ignores ChipThemeData.secondaryLabelStyle, so we must pass
  // labelStyle directly.
  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback? onSelected,
    Widget? avatar,
  }) {
    final cs = Theme.of(context).colorScheme;
    final labelColor = selected ? cs.onPrimary : cs.onSurface;
    return FilterChip(
      avatar: avatar,
      label: Text(label),
      labelStyle: TextStyle(
        color: labelColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      selected: selected,
      onSelected: onSelected == null ? null : (_) => onSelected(),
    );
  }

  Future<void> _pickCustomFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _cfg.customFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _cfg.customFrom = picked);
  }

  Future<void> _pickCustomTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _cfg.customTo ?? DateTime.now(),
      firstDate: _cfg.customFrom ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _cfg.customTo = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accounts = (ref.watch(accountsStreamProvider).valueOrNull ?? [])
        .where((a) => !a.isArchived)
        .toList();

    final isAccountLocked = _cfg.presetAccountId != null;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          // Sheet title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              isAccountLocked
                  ? 'Export — ${_cfg.presetAccountName ?? 'Account Statement'}'
                  : 'Export Transactions',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                // ── Date Range ──────────────────────────────────────────
                _sectionLabel('Date Range', cs, tt),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ExportDateRange.values.map((r) {
                    final label = switch (r) {
                      ExportDateRange.thisMonth => 'This Month',
                      ExportDateRange.lastMonth => 'Last Month',
                      ExportDateRange.last3Months => 'Last 3M',
                      ExportDateRange.last6Months => 'Last 6M',
                      ExportDateRange.thisYear => 'This Year',
                      ExportDateRange.custom => 'Custom',
                    };
                    return _chip(
                      label: label,
                      selected: _cfg.dateRange == r,
                      onSelected: () => setState(() => _cfg.dateRange = r),
                    );
                  }).toList(),
                ),
                if (_cfg.dateRange == ExportDateRange.custom) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined,
                              size: 16),
                          label: Text(_cfg.customFrom != null
                              ? _fmtDate(_cfg.customFrom!)
                              : 'From'),
                          onPressed: _pickCustomFrom,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined,
                              size: 16),
                          label: Text(_cfg.customTo != null
                              ? _fmtDate(_cfg.customTo!)
                              : 'To'),
                          onPressed: _pickCustomTo,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                // ── Transaction Type ────────────────────────────────────
                _sectionLabel('Transaction Type', cs, tt),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in [
                      (null, 'All'),
                      ('income', 'Income'),
                      ('expense', 'Expense'),
                    ])
                      _chip(
                        label: entry.$2,
                        selected: _cfg.kindFilter == entry.$1,
                        onSelected: () =>
                            setState(() => _cfg.kindFilter = entry.$1),
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Accounts ────────────────────────────────────────────
                if (accounts.isNotEmpty) ...[
                  _sectionLabel('Accounts', cs, tt),
                  const SizedBox(height: 4),
                  if (!isAccountLocked) ...[
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('All accounts'),
                      value: _cfg.accountIds == null,
                      onChanged: (_) =>
                          setState(() => _cfg.accountIds = null),
                    ),
                    ...accounts.map((a) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          secondary:
                              Text(a.icon, style: const TextStyle(fontSize: 18)),
                          title: Text(a.name),
                          value: _cfg.accountIds?.contains(a.id) ?? false,
                          onChanged: (v) {
                            setState(() {
                              final current =
                                  Set<String>.from(_cfg.accountIds ?? {});
                              if (v == true) {
                                current.add(a.id);
                              } else {
                                current.remove(a.id);
                              }
                              _cfg.accountIds =
                                  current.isEmpty ? null : current;
                            });
                          },
                        )),
                  ] else
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Text(
                        accounts
                                .where((a) =>
                                    a.id == _cfg.presetAccountId)
                                .firstOrNull
                                ?.icon ??
                            '🏦',
                        style: const TextStyle(fontSize: 18),
                      ),
                      title: Text(_cfg.presetAccountName ?? ''),
                      trailing: Icon(Icons.lock_outline,
                          size: 16, color: cs.onSurfaceVariant),
                    ),
                  const SizedBox(height: 20),
                ],

                // ── Columns ─────────────────────────────────────────────
                _sectionLabel('Columns', cs, tt),
                const SizedBox(height: 4),
                Text(
                  'Tap to toggle. At least one required.',
                  style: tt.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ExportColumn.values.map((col) {
                    final label = switch (col) {
                      ExportColumn.date => 'Date',
                      ExportColumn.time => 'Time',
                      ExportColumn.title => 'Title',
                      ExportColumn.amount => 'Amount',
                      ExportColumn.kind => 'Type',
                      ExportColumn.account => 'Account',
                      ExportColumn.category => 'Category',
                      ExportColumn.mode => 'Mode',
                      ExportColumn.note => 'Note',
                      ExportColumn.id => 'ID',
                      ExportColumn.createdAt => 'Created At',
                    };
                    final selected = _cfg.columns.contains(col);
                    final isOnlyOne = _cfg.columns.length == 1 && selected;
                    return _chip(
                      label: label,
                      selected: selected,
                      onSelected: isOnlyOne
                          ? null
                          : () => setState(() {
                                if (selected) {
                                  _cfg.columns.remove(col);
                                } else {
                                  _cfg.columns.add(col);
                                }
                              }),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // ── Format ──────────────────────────────────────────────
                _sectionLabel('Format', cs, tt),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in [
                      (ExportFormat.csv, 'CSV', Icons.view_list_outlined),
                      (ExportFormat.xlsx, 'Excel', Icons.table_chart_outlined),
                      (ExportFormat.pdf, 'PDF', Icons.picture_as_pdf_outlined),
                      (ExportFormat.json, 'JSON', Icons.data_object_outlined),
                    ])
                      _chip(
                        label: entry.$2,
                        selected: _cfg.format == entry.$1,
                        onSelected: () =>
                            setState(() => _cfg.format = entry.$1),
                        avatar: Icon(
                          entry.$3,
                          size: 16,
                          color: _cfg.format == entry.$1
                              ? cs.onPrimary
                              : cs.onSurface,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),

          // ── Export button ──────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.paddingOf(context).bottom + 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.ios_share_outlined),
                label: Text('Export · ${_cfg.rangeLabel}'),
                onPressed: () => Navigator.pop(context, _cfg),
              ),
            ),
          ),
        ],
      ),
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

  static String _fmtDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
