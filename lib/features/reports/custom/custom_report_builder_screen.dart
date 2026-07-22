import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import '../../../app/themes/app_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../app/themes/app_colors.dart';
import '../../../app/utils/feedback.dart';
import '../../../app/widgets/confirm_delete_dialog.dart';
import '../../../app/widgets/spendwise_sheet.dart';
import '../../../data/db/app_database.dart';
import '../../../state/custom_report_providers.dart';
import '../../../state/manage_providers.dart';
import 'custom_report_chart.dart';
import 'custom_report_executor.dart';
import 'custom_report_spec.dart';

/// The custom-report builder: pick a group-by dimension, metric, kind filter,
/// date range, optional account/category/mode filters, and a chart type —
/// with a **live fl_chart preview** that re-runs as you toggle. Save writes a
/// `custom_reports` row via the DAO (replaces if editing an existing id).
///
/// On open, the builder primes the shared `customReportSpecProvider` from the
/// saved row (when [existingId] is set) or a fresh default (when creating) — so
/// the live preview and the name field always start from the right state.
///
/// The spec never leaves the device and is never sent to the LLM. See
/// [CustomReportExecutor] for the on-device execution + privacy constraints.
class CustomReportBuilderScreen extends ConsumerStatefulWidget {
  const CustomReportBuilderScreen({super.key, this.existingId});

  /// If non-null, the builder loads this saved report for editing.
  final String? existingId;

  @override
  ConsumerState<CustomReportBuilderScreen> createState() =>
      _CustomReportBuilderScreenState();
}

class _CustomReportBuilderScreenState
    extends ConsumerState<CustomReportBuilderScreen> {
  /// The report name lives here, NOT in `customReportSpecProvider`. The name
  /// doesn't affect the on-device query, so syncing it into the spec on every
  /// keystroke would re-key `customReportDataProvider` and reload the live
  /// preview each character — the flicker. It's folded into the spec only at
  /// save time.
  late final TextEditingController _nameController;

  /// Re-entry guard so a double-tap on Save can't create two uuid-keyed rows.
  bool _saving = false;

  /// Baseline (loaded / default) spec + name for the "dirty" check. The Update
  /// button stays hidden until the user actually changes something.
  CustomReportSpec? _originalSpec;
  String _originalName = '';
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    // Seed from the current spec so the field isn't blank on the first frame;
    // the post-frame prime below corrects it to the real (possibly async)
    // loaded / default name.
    _nameController =
        TextEditingController(text: ref.read(customReportSpecProvider).name);
    _nameController.addListener(_onNameChanged);
    // Prime the in-flight spec: load the saved row when editing, otherwise
    // reset to a fresh default so a previous session's spec doesn't leak in.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = widget.existingId;
      final notifier = ref.read(customReportSpecProvider.notifier);
      if (id != null) {
        final row = await ref.read(customReportsDaoProvider).getById(id);
        if (row != null && mounted) {
          final spec = CustomReportSpec.fromJsonString(row.specJson);
          _originalSpec = spec;
          _originalName = spec.name;
          notifier.state = spec;
          _setName(spec.name);
        }
      } else {
        final spec = CustomReportSpec(
          name: 'Untitled report',
          groupBy: CustomGroupBy.category,
          metric: CustomMetric.sum,
          kind: CustomKind.expense,
          dateRange: CustomDateRange.thisMonth,
          chartType: CustomChartType.bar,
        );
        _originalSpec = spec;
        _originalName = 'Untitled report';
        notifier.state = spec;
        _setName('Untitled report');
      }
    });
  }

  void _setName(String name) {
    _nameController.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  /// Rebuild only when the dirty state flips — so typing doesn't rebuild the
  /// whole builder on every keystroke (and never re-keys the preview, since the
  /// name isn't in `customReportSpecProvider`).
  void _onNameChanged() {
    if (!mounted || _originalSpec == null) return;
    final newDirty = _computeDirty(ref.read(customReportSpecProvider));
    if (newDirty != _dirty) setState(() {});
  }

  bool _computeDirty(CustomReportSpec spec) {
    final original = _originalSpec;
    if (original == null) return false;
    return spec != original || _nameController.text != _originalName;
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = ref.watch(customReportSpecProvider);
    final preview = ref.watch(customReportDataProvider(spec));
    final savedAsync = ref.watch(customReportsStreamProvider);

    final isEdit = widget.existingId != null;
    _dirty = _computeDirty(spec);
    // New report: always show Save. Editing: hide Update until something
    // actually changed vs. the loaded row.
    final showButton = !isEdit || _dirty;
    final buttonLabel = isEdit ? 'Update report' : 'Save report';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(isEdit ? 'Edit report' : 'New custom report',
            style: plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // ── Name ──────────────────────────────────────────────────────────
          _NameField(controller: _nameController),
          const SizedBox(height: 20),

          // ── Live preview ──────────────────────────────────────────────────
          _PreviewCard(spec: spec, preview: preview),
          const SizedBox(height: 24),

          // ── Group by ──────────────────────────────────────────────────────
          _Label('Group by', cs),
          _ChipGroup<CustomGroupBy>(
            values: CustomGroupBy.values,
            selected: spec.groupBy,
            labels: const {
              CustomGroupBy.category: 'Category',
              CustomGroupBy.account: 'Account',
              CustomGroupBy.mode: 'Mode',
              CustomGroupBy.day: 'Day',
              CustomGroupBy.month: 'Month',
            },
            onSelected: (v) => _update(ref, spec.copy()..groupBy = v),
          ),
          const SizedBox(height: 18),

          // ── Metric ────────────────────────────────────────────────────────
          _Label('Metric', cs),
          _ChipGroup<CustomMetric>(
            values: CustomMetric.values,
            selected: spec.metric,
            labels: const {
              CustomMetric.sum: 'Sum',
              CustomMetric.count: 'Count',
              CustomMetric.avg: 'Average',
            },
            onSelected: (v) => _update(ref, spec.copy()..metric = v),
          ),
          const SizedBox(height: 18),

          // ── Kind ──────────────────────────────────────────────────────────
          _Label('Transaction type', cs),
          _ChipGroup<CustomKind>(
            values: CustomKind.values,
            selected: spec.kind,
            labels: const {
              CustomKind.expense: 'Expense',
              CustomKind.income: 'Income',
              CustomKind.all: 'All',
            },
            onSelected: (v) => _update(ref, spec.copy()..kind = v),
          ),
          const SizedBox(height: 18),

          // ── Date range ────────────────────────────────────────────────────
          _Label('Date range', cs),
          _ChipGroup<CustomDateRange>(
            values: CustomDateRange.values,
            selected: spec.dateRange,
            labels: const {
              CustomDateRange.thisMonth: 'This month',
              CustomDateRange.last3: 'Last 3 months',
              CustomDateRange.thisYear: 'This year',
              CustomDateRange.custom: 'Custom',
            },
            onSelected: (v) => _update(ref, spec.copy()..dateRange = v),
          ),
          if (spec.dateRange == CustomDateRange.custom) ...[
            const SizedBox(height: 12),
            _CustomRangePicker(spec: spec),
          ],
          const SizedBox(height: 18),

          // ── Filters ───────────────────────────────────────────────────────
          _Label('Filters', cs),
          _FilterRow(spec: spec),
          const SizedBox(height: 18),

          // ── Chart type ────────────────────────────────────────────────────
          _Label('Chart type', cs),
          _ChipGroup<CustomChartType>(
            values: CustomChartType.values,
            selected: spec.chartType,
            labels: const {
              CustomChartType.bar: 'Bar',
              CustomChartType.pie: 'Pie',
              CustomChartType.line: 'Line',
              CustomChartType.list: 'List',
              CustomChartType.stat: 'Stat',
            },
            onSelected: (v) => _update(ref, spec.copy()..chartType = v),
          ),
          const SizedBox(height: 28),

          // ── Saved reports (inline list, with delete) ──────────────────────
          if (savedAsync.hasValue) ...[
            _Label('Your saved reports', cs),
            _SavedReportsList(rows: savedAsync.value!),
            const SizedBox(height: 24),
          ],
        ],
      ),
      // ── Sticky save / update bar ────────────────────────────────────────
      // Fixed at the bottom. When editing, it's hidden entirely until the user
      // changes something (showButton == false → no bottom bar).
      bottomNavigationBar: showButton
          ? SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _save(context, ref),
                icon: const Icon(Icons.save_outlined),
                label: Text(buttonLabel),
              ),
            )
          : null,
    );
  }

  /// `spec` is expected to be a fresh copy (call sites do
  /// `spec.copy()..field=v`) so the watched instance is never mutated in place
  /// — mutating it would change its hash while it's the live
  /// `customReportDataProvider` family key.
  void _update(WidgetRef ref, CustomReportSpec spec) {
    ref.read(customReportSpecProvider.notifier).state = spec;
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showFeedbackSnackBar(context, 'Give your report a name first', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      // Fold the (possibly renamed) name into the spec at the last moment. The
      // spec provider holds only the query-affecting fields; the name lives in
      // the controller so typing it never re-runs the preview.
      final spec = ref.read(customReportSpecProvider).copy()..name = name;
      final dao = ref.read(customReportsDaoProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = widget.existingId ?? const Uuid().v4();
      if (widget.existingId == null) {
        // Fresh insert — every NOT NULL column (incl. createdAt) must be present
        // because `upsert` validates the INSERT statement.
        await dao.upsert(CustomReportsCompanion(
          id: Value(id),
          name: Value(name),
          specJson: Value(spec.toJsonString()),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
      } else {
        // Edit — a real UPDATE leaves createdAt untouched (insertOnConflictUpdate
        // can't do this: it validates the INSERT and rejects an absent createdAt).
        await dao.updateFields(
          id,
          name: name,
          specJson: spec.toJsonString(),
          updatedAt: now,
        );
      }
      if (!context.mounted) return;
      showFeedbackSnackBar(context,
          widget.existingId == null ? 'Report saved' : 'Report updated');
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ── Name field ────────────────────────────────────────────────────────────────

class _NameField extends StatelessWidget {
  const _NameField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: 'Report name',
        prefixIcon: const Icon(Icons.label_outline),
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
      ),
      // No onChanged: the name is owned by the parent controller and only
      // folded into the spec at save time, so typing never re-runs the preview.
    );
  }
}

// ── Live preview card ────────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.spec, required this.preview});
  final CustomReportSpec spec;
  final AsyncValue<List<CustomReportRow>> preview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Live preview',
                  style: plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                '${spec.metric.name} • ${spec.kind.name}',
                style: plusJakartaSans(
                    fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          preview.when(
            loading: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SizedBox(
              height: 120,
              child: Center(
                  child: Text('Could not run: $e',
                      style: TextStyle(color: cs.onSurfaceVariant))),
            ),
            data: (rows) => CustomReportChart(spec: spec, rows: rows),
          ),
        ],
      ),
    );
  }
}

// ── Section label ────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text, this.cs);
  final String text;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.4)),
    );
  }
}

// ── Chip group ───────────────────────────────────────────────────────────────

class _ChipGroup<T extends Enum> extends StatelessWidget {
  const _ChipGroup({
    required this.values,
    required this.selected,
    required this.labels,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final Map<T, String> labels;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(labels[v] ?? v.name),
            selected: v == selected,
            onSelected: (_) => onSelected(v),
          ),
      ],
    );
  }
}

// ── Custom date range picker row ─────────────────────────────────────────────

class _CustomRangePicker extends ConsumerWidget {
  const _CustomRangePicker({required this.spec});
  final CustomReportSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _DateTile(
            label: 'From',
            value: spec.customFrom,
            onTap: () async {
              final initial = DateTime.tryParse(spec.customFrom ?? '') ??
                  DateTime.now().subtract(const Duration(days: 30));
              final d = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) {
                ref.read(customReportSpecProvider.notifier).state =
                    spec.copy()..customFrom = d.toIso8601String();
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DateTile(
            label: 'To',
            value: spec.customTo,
            onTap: () async {
              final initial =
                  DateTime.tryParse(spec.customTo ?? '') ?? DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) {
                ref.read(customReportSpecProvider.notifier).state =
                    spec.copy()..customTo = d.toIso8601String();
              }
            },
          ),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.value, required this.onTap});
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final display = value == null
        ? 'Pick date'
        : (value!.length >= 10 ? value!.substring(0, 10) : value!);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: plusJakartaSans(
                    fontSize: 10, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(display,
                style: plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Filter row (account / category / mode pickers) ─────────────────────

class _FilterRow extends ConsumerWidget {
  const _FilterRow({required this.spec});
  final CustomReportSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? const [];
    final categories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    final modes = ref.watch(modesStreamProvider).valueOrNull ?? const [];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChip(
          label: 'Account',
          icon: Icons.account_balance_wallet_outlined,
          display: _nameFor(accounts, spec.accountId, (a) => a.name),
          onClear: spec.accountId == null
              ? null
              : () => _set(ref, spec.copy()..accountId = null),
          onTap: () => _pickAccount(context, ref, spec, accounts),
        ),
        _FilterChip(
          label: 'Category',
          icon: Icons.category_outlined,
          display: _nameFor(categories, spec.categoryId, (c) => c.name),
          onClear: spec.categoryId == null
              ? null
              : () => _set(ref, spec.copy()..categoryId = null),
          onTap: () => _pickCategory(context, ref, spec, categories),
        ),
        _FilterChip(
          label: 'Mode',
          icon: Icons.credit_card_outlined,
          display: _nameFor(modes, spec.modeId, (m) => m.name),
          onClear: spec.modeId == null
              ? null
              : () => _set(ref, spec.copy()..modeId = null),
          onTap: () => _pickMode(context, ref, spec, modes),
        ),
      ],
    );
  }

  /// `s` is expected to be a fresh copy (call sites do `spec.copy()..field=v`)
  /// so the watched instance is never mutated in place.
  void _set(WidgetRef ref, CustomReportSpec s) =>
      ref.read(customReportSpecProvider.notifier).state = s;

  String _nameFor<T>(List<T> items, String? id, String Function(T) name) {
    if (id == null) return 'All';
    final i = items.where((x) => (x as dynamic).id == id).firstOrNull;
    return i == null ? 'All' : name(i);
  }

  Future<void> _pickAccount(BuildContext context, WidgetRef ref,
      CustomReportSpec spec, List<Account> items) async {
    final id = await _showPicker<Account>(context, 'Account', items,
        (a) => a.name, (a) => a.id, spec.accountId);
    if (id != null) {
      _set(ref, spec.copy()..accountId = id == '__all' ? null : id);
    }
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref,
      CustomReportSpec spec, List<Category> items) async {
    final id = await _showPicker<Category>(context, 'Category', items,
        (c) => c.name, (c) => c.id, spec.categoryId);
    if (id != null) {
      _set(ref, spec.copy()..categoryId = id == '__all' ? null : id);
    }
  }

  Future<void> _pickMode(BuildContext context, WidgetRef ref,
      CustomReportSpec spec, List<Mode> items) async {
    final id = await _showPicker<Mode>(context, 'Mode', items,
        (m) => m.name, (m) => m.id, spec.modeId);
    if (id != null) {
      _set(ref, spec.copy()..modeId = id == '__all' ? null : id);
    }
  }

  /// A simple bottom-sheet picker rendered via [showSpendWiseSheet]. Returns
  /// the selected id, or '__all' for the "All" reset entry, or null if dismissed.
  Future<String?> _showPicker<T>(
    BuildContext context,
    String title,
    List<T> items,
    String Function(T) name,
    String Function(T) id,
    String? selectedId,
  ) async {
    return showSpendWiseSheet<String>(
      context,
      constraints: const BoxConstraints(maxHeight: 520),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Filter by $title',
                  style: plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  ListTile(
                    leading: Icon(Icons.clear_all, color: cs.onSurfaceVariant),
                    title: const Text('All'),
                    selected: selectedId == null,
                    onTap: () => Navigator.pop(ctx, '__all'),
                  ),
                  for (final item in items)
                    ListTile(
                      leading: const Icon(Icons.circle, size: 10),
                      title: Text(name(item)),
                      selected: id(item) == selectedId,
                      onTap: () => Navigator.pop(ctx, id(item)),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.display,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final IconData icon;
  final String display;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = onClear != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? cs.primaryContainer
              : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: plusJakartaSans(
                        fontSize: 9,
                        color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
                Text(display,
                    style: plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? cs.onPrimaryContainer : cs.onSurface)),
              ],
            ),
            if (onClear != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClear,
                child: Icon(Icons.close, size: 14,
                    color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Saved reports list (swipe-to-edit/delete per List Row Interaction Rules) ─

class _SavedReportsList extends ConsumerWidget {
  const _SavedReportsList({required this.rows});
  final List<CustomReport> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No saved reports yet. Build one and tap Save.',
            style: plusJakartaSans(
                fontSize: 12, color: cs.onSurfaceVariant)),
      );
    }
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Slidable(
              key: ValueKey(row.id),
              startActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                children: [
                  SlidableAction(
                    onPressed: (_) => context.push(
                        '/reports/custom-builder?id=${row.id}'),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                  ),
                ],
              ),
              endActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                children: [
                  SlidableAction(
                    onPressed: (_) =>
                        _confirmDelete(context, ref, row),
                    backgroundColor: appColors.expense,
                    foregroundColor: appColors.onExpense,
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                  ),
                ],
              ),
              child: InkWell(
                // Tap = open the edit form prefilled (List Row Interaction Rules).
                onTap: () =>
                    context.push('/reports/custom-builder?id=${row.id}'),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.insights_outlined, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(row.name,
                            style: plusJakartaSans(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 20, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, CustomReport row) async {
    final ok = await showConfirmDeleteDialog(context,
        title: 'Delete report',
        message: 'Delete "${row.name}"? This cannot be undone.');
    if (!ok || !context.mounted) return;
    await ref.read(customReportsDaoProvider).deleteById(row.id);
    if (!context.mounted) return;
    showFeedbackSnackBar(context, 'Report deleted');
  }
}