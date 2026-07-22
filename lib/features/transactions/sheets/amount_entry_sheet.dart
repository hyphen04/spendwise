import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/themes/app_fonts.dart';
import '../../../app/widgets/amount_numpad_step.dart';
import '../../../app/widgets/date_strip.dart';
import '../../../app/widgets/mono_numpad.dart';
import '../../../app/widgets/mono_pill.dart';
import '../../../app/widgets/spendwise_sheet.dart';
import '../../../data/db/app_database.dart';
import '../../../state/manage_providers.dart';
import '../../../state/prefs_providers.dart';
import '../../../state/transactions_providers.dart';
import 'mode_auto_select.dart';
Future<void> showAmountEntrySheet(
  BuildContext context, {
  String initialKind = 'expense',
  // Optional prefill — used by the Home quick-add "edit full form" escape
  // hatch so the amount/category/date the user already entered carry over.
  // All default to unset, so existing callers see no behavior change.
  String? prefillCategoryId,
  String? prefillAccountId,
  String? prefillModeId,
  double? prefillAmount,
  DateTime? prefillDate,
}) {
  return showSpendWiseSheet(
    context,
    builder: (_) => _AmountEntrySheet(
      initialKind: initialKind,
      prefillCategoryId: prefillCategoryId,
      prefillAccountId: prefillAccountId,
      prefillModeId: prefillModeId,
      prefillAmount: prefillAmount,
      prefillDate: prefillDate,
    ),
  );
}

class _AmountEntrySheet extends ConsumerStatefulWidget {
  const _AmountEntrySheet({
    required this.initialKind,
    this.prefillCategoryId,
    this.prefillAccountId,
    this.prefillModeId,
    this.prefillAmount,
    this.prefillDate,
  });
  final String initialKind;
  final String? prefillCategoryId;
  final String? prefillAccountId;
  final String? prefillModeId;
  final double? prefillAmount;
  final DateTime? prefillDate;

  @override
  ConsumerState<_AmountEntrySheet> createState() => _AmountEntrySheetState();
}

class _AmountEntrySheetState extends ConsumerState<_AmountEntrySheet> {
  int _step = 0; // 0 = numpad, 1 = details
  String _raw = ''; // digit string e.g. "1250.50"
  late String _kind;
  String? _fromAccountId;
  String? _toAccountId;

  // Details form state
  final _noteCtrl = TextEditingController();
  String? _accountId;
  String? _categoryId;
  String? _modeId;
  DateTime _selectedDate = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    // Apply optional prefill values immediately (amount/date/category/account).
    if (widget.prefillAmount != null && widget.prefillAmount! > 0) {
      _raw = widget.prefillAmount! == widget.prefillAmount!.truncateToDouble()
          ? widget.prefillAmount!.toInt().toString()
          : widget.prefillAmount!.toStringAsFixed(2);
    }
    if (widget.prefillDate != null) {
      _selectedDate = widget.prefillDate!;
    }
    _categoryId = widget.prefillCategoryId;
    _accountId = widget.prefillAccountId;
    _modeId = widget.prefillModeId;
    // Pre-fill default account (if set) after first frame so providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final defaultId = ref.read(defaultAccountIdProvider);
      if (defaultId != null && _accountId == null) {
        setState(() => _accountId = defaultId);
        // Trigger mode auto-selection for the default account.
        final accounts = ref.read(accountsStreamProvider).valueOrNull ?? [];
        final modes = ref.read(modesStreamProvider).valueOrNull ?? [];
        final cashMode = _cashMode(modes);
        _autoSetMode(defaultId, accounts, cashMode, modes);
      } else if (_accountId != null) {
        // A pre-filled account still needs its mode resolved.
        final accounts = ref.read(accountsStreamProvider).valueOrNull ?? [];
        final modes = ref.read(modesStreamProvider).valueOrNull ?? [];
        final cashMode = _cashMode(modes);
        _autoSetMode(_accountId, accounts, cashMode, modes);
      }
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _amount => parseAmount(_raw);
  bool get _canContinue => _amount > 0;
  bool get _isTransfer => _kind == 'transfer';

  void _onDigit(String d) {
    setState(() => _raw = appendDigit(_raw, d));
  }

  void _onBackspace() {
    setState(() => _raw = backspaceDigit(_raw));
  }

  void _goToDetails() {
    if (!_canContinue) return;
    if (_isTransfer) {
      if (_fromAccountId == null || _toAccountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select both accounts before continuing.'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      if (_fromAccountId == _toAccountId) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Source and destination accounts must differ.'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    }
    setState(() => _step = 1);
  }

  Future<void> _save() async {
    final accounts = ref.read(accountsStreamProvider).valueOrNull ?? [];
    final modes = ref.read(modesStreamProvider).valueOrNull ?? [];
    final modeSourceId = _isTransfer ? _fromAccountId : _accountId;
    final effectiveModeId = _isCashAccount(modeSourceId, accounts) ? _cashMode(modes)?.id : _modeId;

    if (_isTransfer) {
      if (_fromAccountId == null) {
        _showError('Please select a From Account.');
        return;
      }
      if (_toAccountId == null) {
        _showError('Please select a To Account.');
        return;
      }
      if (_fromAccountId == _toAccountId) {
        _showError('From and To accounts cannot be the same.');
        return;
      }
      if (effectiveModeId == null) {
        _showError('Please select a Payment Mode.');
        return;
      }
    } else {
      if (_accountId == null) {
        _showError('Please select an Account.');
        return;
      }
      if (_categoryId == null) {
        _showError('Please select a Category.');
        return;
      }
      if (effectiveModeId == null) {
        _showError('Please select a Payment Mode.');
        return;
      }
    }

    final date = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    ).toIso8601String();

    setState(() => _saving = true);
    final repo = ref.read(transactionsRepositoryProvider);
    try {
      if (_isTransfer) {
        await repo.createTransfer(
          amount: _amount,
          transactionDate: date,
          fromAccountId: _fromAccountId!,
          toAccountId: _toAccountId!,
          modeId: effectiveModeId,
          note: _noteCtrl.text.trim(),
        );
      } else {
        await repo.create(
          amount: _amount,
          transactionDate: date,
          accountId: _accountId!,
          categoryId: _categoryId!,
          modeId: effectiveModeId,
          kind: _kind,
          note: _noteCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(_step == 1 ? 0.05 : -0.05, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _step == 0
          ? KeyedSubtree(key: const ValueKey('numpad'), child: _buildNumpad())
          : KeyedSubtree(
              key: const ValueKey('details'), child: _buildDetails()),
    );
  }

  // ── Step 1: Numpad ───────────────────────────────────────────────────────────

  Widget _buildNumpad() {
    final cs = Theme.of(context).colorScheme;
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final botPad = MediaQuery.paddingOf(context).bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Kind toggle — MonoPill row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final kind in ['expense', 'income', 'transfer']) ...[
                MonoPill(
                  label: kind[0].toUpperCase() + kind.substring(1),
                  selected: _kind == kind,
                  dense: true,
                  onTap: () => setState(() {
                    _kind = kind;
                    _categoryId = null;
                  }),
                ),
                if (kind != 'transfer') const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 7-day date strip
        DateStrip(
          selected: _selectedDate,
          onSelect: (d) => setState(() => _selectedDate = d),
        ),
        const SizedBox(height: 20),

        // Big amount + backspace (the numpad itself doesn't have a ⌫ in
        // confirm mode — that slot is the decimal point. The ⌫ lives here
        // next to the amount for one-tap correction.) Shared [AmountDisplay]
        // — the Home quick-add sheet renders the exact same amount row.
        AmountDisplay(raw: _raw, onBackspace: _onBackspace),
        const SizedBox(height: 16),

        // Transfer account selectors (compact)
        if (_isTransfer)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    isDense: true,
                    initialValue: _fromAccountId,
                    decoration: const InputDecoration(labelText: 'From', isDense: true),
                    items: accounts.map((a) => DropdownMenuItem(
                      value: a.id, child: Text('${a.icon} ${a.name}', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _fromAccountId = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.arrow_forward_rounded, size: 18, color: cs.onSurfaceVariant),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    isDense: true,
                    initialValue: _toAccountId,
                    decoration: const InputDecoration(labelText: 'To', isDense: true),
                    items: accounts.map((a) => DropdownMenuItem(
                      value: a.id, child: Text('${a.icon} ${a.name}', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _toAccountId = v),
                  ),
                ),
              ],
            ),
          ),

        // MonoNumpad — circular, ✓ as confirm
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MonoNumpad(
            onDigit: _onDigit,
            onBackspace: _onBackspace,
            onConfirm: _canContinue ? _goToDetails : null,
            showDecimal: true,
            bottomRightAction: NumpadAction.confirm,
            confirmEnabled: _canContinue,
          ),
        ),

        SizedBox(height: botPad + 12),
      ],
    );
  }

  // ── Step 2: Details form ─────────────────────────────────────────────────────

  // ── Mode auto-selection on account change ────────────────────────────────

  void _autoSetMode(String? accountId, List<Account> accounts, Mode? cashMode, List<Mode> allModes) {
    _modeId = autoSelectMode(
      accountId: accountId,
      accounts: accounts,
      cashMode: cashMode,
      allModes: allModes,
      currentModeId: _modeId,
      defaultModeId: ref.read(defaultModeIdProvider),
    );
  }

  // ── Mode filtering helpers ────────────────────────────────────────────────

  /// True when the account with [accountId] is a cash-type account (name
  /// contains "cash", case-insensitive).  No schema change needed.
  bool _isCashAccount(String? accountId, List<Account> accounts) =>
      isCashAccount(accountId, accounts);

  /// The "Cash" payment mode, or null if not seeded yet.
  Mode? _cashMode(List<Mode> modes) => cashMode(modes);

  /// Modes visible for a non-cash account (excludes the "Cash" mode).
  List<Mode> _digitalModes(List<Mode> modes) => digitalModes(modes);

  Widget _buildDetails() {
    final cs = Theme.of(context).colorScheme;
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final categories = ref
            .watch(categoriesByKindProvider(
                _kind == 'income' ? 'income' : 'expense'))
            .valueOrNull ??
        [];
    final modes = ref.watch(modesStreamProvider).valueOrNull ?? [];

    final modeSourceId = _isTransfer ? _fromAccountId : _accountId;
    final cashAccount = _isCashAccount(modeSourceId, accounts);
    final cashMode = _cashMode(modes);
    final visibleModes = cashAccount ? (cashMode != null ? [cashMode] : modes) : _digitalModes(modes);

    bool isValid = _amount > 0;
    if (_isTransfer) {
      isValid = isValid && _fromAccountId != null && _toAccountId != null && _fromAccountId != _toAccountId && _modeId != null;
    } else {
      isValid = isValid && _accountId != null && _categoryId != null && _modeId != null;
    }
    final effectiveModeId = (cashAccount && cashMode != null) ? cashMode.id : _modeId;
    isValid = isValid && effectiveModeId != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Amount chip — tap to edit ──────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _step = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kind[0].toUpperCase() + _kind.substring(1),
                          style: plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
                        ),
                        Text(
                          '₹$_raw',
                          style: plusJakartaSans(
                            fontSize: 28, fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Icon(Icons.edit_rounded, size: 16, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Date ──────────────────────────────────────────────────────
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(_formatDate(_selectedDate)),
              ),
            ),
            const SizedBox(height: 16),

            // ── Account + Category (or From/To) ────────────────────────────
            if (_isTransfer) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _fromAccountId,
                decoration: const InputDecoration(labelText: 'From Account *'),
                items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.icon} ${a.name}', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() {
                  _fromAccountId = v;
                  _autoSetMode(v, accounts, cashMode, modes);
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _toAccountId,
                decoration: const InputDecoration(labelText: 'To Account *'),
                items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.icon} ${a.name}', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _toAccountId = v),
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _accountId,
                decoration: const InputDecoration(labelText: 'Account *'),
                items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.icon} ${a.name}', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() {
                  _accountId = v;
                  _autoSetMode(v, accounts, cashMode, modes);
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category *'),
                items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.icon} ${c.name}', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],

            // ── Payment Mode ───────────────────────────────────────────────
            const SizedBox(height: 16),
            _ModeField(
              cashAccount: cashAccount,
              cashMode: cashMode,
              visibleModes: visibleModes,
              modeId: _modeId,
              onChanged: (v) => setState(() => _modeId = v),
            ),
            const SizedBox(height: 16),

            // ── Note ───────────────────────────────────────────────────────
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'Any extra detail…',
              ),
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: 24),

            // ── Save ──────────────────────────────────────────────────────
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: (!_saving && isValid) ? _save : null,
                child: _saving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Add Transaction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mode field (context-aware) ────────────────────────────────────────────────

class _ModeField extends StatelessWidget {
  const _ModeField({
    required this.cashAccount,
    required this.cashMode,
    required this.visibleModes,
    required this.modeId,
    required this.onChanged,
  });

  final bool cashAccount;
  final Mode? cashMode;
  final List<Mode> visibleModes;
  final String? modeId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cm = cashMode;

    if (cashAccount && cm != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(cm.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(cm.name, style: Theme.of(context).textTheme.bodyLarge),
            ),
            Text(
              'auto',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: modeId,
      decoration: const InputDecoration(labelText: 'Payment Mode *'),
      hint: const Text('How was this paid?'),
      items: visibleModes
          .map((m) => DropdownMenuItem(
                value: m.id,
                child: Text('${m.icon} ${m.name}'),
              ))
          .toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? 'Select a payment mode.' : null,
    );
  }
}

// ── Date strip ─────────────────────────────────────────────────────────────────


String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final d = DateTime(dt.year, dt.month, dt.day);
  if (d == today) return 'Today';
  if (d == yesterday) return 'Yesterday';
  return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
