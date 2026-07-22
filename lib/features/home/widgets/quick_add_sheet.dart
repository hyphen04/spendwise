import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/themes/app_fonts.dart';
import '../../../app/utils/feedback.dart';
import '../../../app/widgets/amount_numpad_step.dart';
import '../../../app/widgets/date_strip.dart';
import '../../../app/widgets/mono_numpad.dart';
import '../../../app/widgets/mono_pill.dart';
import '../../../app/widgets/spendwise_sheet.dart';
import '../../../data/db/app_database.dart';
import '../../transactions/sheets/amount_entry_sheet.dart';
import '../../transactions/sheets/mode_auto_select.dart';
import '../../../state/manage_providers.dart';
import '../../../state/prefs_providers.dart';
import '../../../state/quick_add_providers.dart';
import '../../../state/transactions_providers.dart';

/// The Home quick-add sheet. The user picks a frequently-used category on the
/// Home rail; this sheet opens with that category locked in, so adding a
/// transaction is just: type the amount → ✓. The default account/mode are
/// shown as a compact summary row (with an "edit full form" escape hatch that
/// opens the full amount-entry sheet carrying the amount/category/date over).
///
/// Reuses [MonoNumpad], [DateStrip], [AmountDisplay] and the shared
/// [autoSelectMode] helper — no duplicated numpad or mode-selection logic.
Future<void> showQuickAddSheet(
  BuildContext context, {
  required String categoryId,
}) {
  return showSpendWiseSheet(
    context,
    builder: (_) => _QuickAddSheet(categoryId: categoryId),
  );
}

class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet({required this.categoryId});
  final String categoryId;

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet> {
  String _raw = '';
  DateTime _selectedDate = DateTime.now();
  String? _accountId;
  String? _modeId;
  // Null = derive from the category's kind. Toggled only for 'both' categories.
  String? _kindOverride;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Prefill the amount with the last amount the user logged for this
    // category, so a repeat purchase is just open → ✓. Synchronous so the
    // amount is already showing on the first frame.
    final last = ref.read(lastAmountForCategoryProvider(widget.categoryId));
    if (last != null && last > 0) {
      _raw = _formatPrefill(last);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final defaultId = ref.read(defaultAccountIdProvider);
      if (defaultId != null) {
        setState(() => _accountId = defaultId);
        final accounts = ref.read(accountsStreamProvider).valueOrNull ?? [];
        final modes = ref.read(modesStreamProvider).valueOrNull ?? [];
        setState(() {
          _modeId = autoSelectMode(
            accountId: defaultId,
            accounts: accounts,
            cashMode: cashMode(modes),
            allModes: modes,
            currentModeId: _modeId,
            defaultModeId: ref.read(defaultModeIdProvider),
          );
        });
      }
    });
  }

  double get _amount => parseAmount(_raw);
  bool get _canConfirm => _amount > 0 && _accountId != null && _modeId != null;

  void _onDigit(String d) => setState(() => _raw = appendDigit(_raw, d));
  void _onBackspace() => setState(() => _raw = backspaceDigit(_raw));

  /// Format a prefilled amount as a clean digit string the numpad can continue
  /// from: integers without a decimal ("250"), fractional values with their
  /// trailing zeros trimmed ("250.5", not "250.50").
  String _formatPrefill(double v) {
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  String _kindFor(Category c) {
    if (_kindOverride != null) return _kindOverride!;
    if (c.kind == 'income') return 'income';
    return 'expense'; // 'expense' or 'both' (default to expense for 'both').
  }

  Future<void> _save() async {
    if (!_canConfirm || _saving) return;
    final date = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    ).toIso8601String();

    setState(() => _saving = true);
    try {
      final repo = ref.read(transactionsRepositoryProvider);
      final c = _category;
      if (c == null) {
        _showError('Category not found.');
        return;
      }
      await repo.create(
        amount: _amount,
        transactionDate: date,
        accountId: _accountId!,
        categoryId: c.id,
        modeId: _modeId!,
        kind: _kindFor(c),
        note: '',
      );
      if (mounted) {
        Navigator.of(context).pop();
        showFeedbackSnackBar(context, 'Transaction added');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Category? get _category {
    final cats = ref.read(categoriesStreamProvider).valueOrNull ?? [];
    return cats.where((c) => c.id == widget.categoryId).firstOrNull;
  }

  Account? get _account {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    return accounts.where((a) => a.id == _accountId).firstOrNull;
  }

  Mode? get _mode {
    final modes = ref.watch(modesStreamProvider).valueOrNull ?? [];
    return modes.where((m) => m.id == _modeId).firstOrNull;
  }

  /// Open the full amount-entry sheet carrying the amount/category/date over,
  /// then close this quick sheet so the user finishes in the full form.
  void _editFullForm() {
    final c = _category;
    final amount = _amount;
    Navigator.of(context).pop();
    showAmountEntrySheet(
      context,
      initialKind: c == null ? 'expense' : _kindFor(c),
      prefillCategoryId: widget.categoryId,
      prefillAccountId: _accountId,
      prefillModeId: _modeId,
      prefillAmount: amount > 0 ? amount : null,
      prefillDate: _selectedDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final botPad = MediaQuery.paddingOf(context).bottom;
    final c = _category;

    if (c == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Text('Category not found.',
            style: plusJakartaSans(fontSize: 14, color: cs.onSurfaceVariant)),
      );
    }

    final canToggleKind = c.kind == 'both';
    final account = _account;
    final mode = _mode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Category header chip ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.icon, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(
                      c.name,
                      style: plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (canToggleKind) ...[
                MonoPill(
                  label: 'Expense',
                  selected: _kindFor(c) == 'expense',
                  dense: true,
                  onTap: () => setState(() => _kindOverride = 'expense'),
                ),
                const SizedBox(width: 6),
                MonoPill(
                  label: 'Income',
                  selected: _kindFor(c) == 'income',
                  dense: true,
                  onTap: () => setState(() => _kindOverride = 'income'),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                icon: const Icon(Icons.close_rounded),
                color: cs.onSurfaceVariant,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Date strip ───────────────────────────────────────────────────
        DateStrip(
          selected: _selectedDate,
          onSelect: (d) => setState(() => _selectedDate = d),
        ),
        const SizedBox(height: 20),

        // ── Amount ───────────────────────────────────────────────────────
        AmountDisplay(raw: _raw, onBackspace: _onBackspace),
        const SizedBox(height: 16),

        // ── Account / mode summary row + "edit full form" ────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: _editFullForm,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _SummaryChip(
                    icon: account?.icon ?? '🏦',
                    label: account?.name ?? 'No account',
                    subLabel: 'account',
                  ),
                  Container(
                      width: 1, height: 30, color: cs.outlineVariant),
                  _SummaryChip(
                    icon: mode?.icon ?? '💳',
                    label: mode?.name ?? 'No mode',
                    subLabel: 'mode',
                  ),
                  const Spacer(),
                  Icon(Icons.edit_rounded,
                      size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'full form',
                    style: plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Numpad ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MonoNumpad(
            onDigit: _onDigit,
            onBackspace: _onBackspace,
            onConfirm: _canConfirm ? _save : null,
            showDecimal: true,
            bottomRightAction: NumpadAction.confirm,
            confirmEnabled: _canConfirm,
          ),
        ),
        SizedBox(height: botPad + 12),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label, required this.subLabel});
  final String icon;
  final String label;
  final String subLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                subLabel,
                style: plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                label,
                style: plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}