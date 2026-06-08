import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/widgets/mono_numpad.dart';
import '../../../app/widgets/mono_pill.dart';
import '../../../data/db/app_database.dart';
import '../../../state/manage_providers.dart';
import '../../../state/prefs_providers.dart';
import '../../../state/transactions_providers.dart';

Future<void> showAmountEntrySheet(
  BuildContext context, {
  String initialKind = 'expense',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AmountEntrySheet(initialKind: initialKind),
  );
}

class _AmountEntrySheet extends ConsumerStatefulWidget {
  const _AmountEntrySheet({required this.initialKind});
  final String initialKind;

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
      }
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_raw) ?? 0;
  bool get _canContinue => _amount > 0;
  bool get _isTransfer => _kind == 'transfer';

  void _onDigit(String d) {
    setState(() {
      if (d == '.') {
        if (_raw.contains('.')) return;
        _raw = _raw.isEmpty ? '0.' : '$_raw.';
        return;
      }
      final dotIdx = _raw.indexOf('.');
      if (dotIdx != -1 && _raw.length - dotIdx > 2) return;
      if (_raw == '0') {
        _raw = d;
      } else {
        _raw = '$_raw$d';
      }
    });
  }

  void _onBackspace() {
    if (_raw.isEmpty) return;
    setState(() => _raw = _raw.substring(0, _raw.length - 1));
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

  bool get _canSave => _isTransfer
      ? (_fromAccountId != null && _toAccountId != null && _modeId != null)
      : (_accountId != null && _categoryId != null && _modeId != null);

  Future<void> _save() async {
    if (!_canSave) return;
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
          modeId: _modeId!,
          note: _noteCtrl.text.trim(),
        );
      } else {
        await repo.create(
          amount: _amount,
          transactionDate: date,
          accountId: _accountId!,
          categoryId: _categoryId!,
          modeId: _modeId!,
          kind: _kind,
          note: _noteCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        // Drag handle
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

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
        _DateStrip(
          selected: _selectedDate,
          onSelect: (d) => setState(() => _selectedDate = d),
        ),
        const SizedBox(height: 20),

        // Big amount
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '₹',
                style: GoogleFonts.manrope(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withValues(alpha: 0.35),
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  _raw.isEmpty ? '0' : _raw,
                  style: GoogleFonts.manrope(
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
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
    final isCash = _isCashAccount(accountId, accounts);
    if (isCash) {
      _modeId = cashMode?.id;
    } else {
      // For bank accounts: keep existing digital mode or default to preferred/first digital.
      if (_modeId == null || _modeId == cashMode?.id) {
        final digital = _digitalModes(allModes);
        final preferredId = ref.read(defaultModeIdProvider);
        final isPreferredDigital =
            preferredId != null && digital.any((m) => m.id == preferredId);
        _modeId = isPreferredDigital
            ? preferredId
            : (digital.isNotEmpty ? digital.first.id : null);
      }
    }
  }

  // ── Mode filtering helpers ────────────────────────────────────────────────

  /// True when the account with [accountId] is a cash-type account (name
  /// contains "cash", case-insensitive).  No schema change needed.
  bool _isCashAccount(String? accountId, List<Account> accounts) {
    if (accountId == null) return false;
    final matches = accounts.where((a) => a.id == accountId);
    if (matches.isEmpty) return false;
    return matches.first.name.toLowerCase().contains('cash');
  }

  /// The "Cash" payment mode, or null if not seeded yet.
  Mode? _cashMode(List<Mode> modes) {
    final m = modes.where((m) => m.name.toLowerCase() == 'cash');
    return m.isEmpty ? null : m.first;
  }

  /// Modes visible for a non-cash account (excludes the "Cash" mode).
  List<Mode> _digitalModes(List<Mode> modes) =>
      modes.where((m) => m.name.toLowerCase() != 'cash').toList();

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

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

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
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
                        ),
                        Text(
                          '₹$_raw',
                          style: GoogleFonts.manrope(
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
            FilledButton(
              onPressed: (_saving || !_canSave) ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add Transaction'),
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

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selected, required this.onSelect});
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const dayLabels = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

    // Show the last 7 days (oldest to newest)
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final selDay = DateTime(selected.year, selected.month, selected.day);

    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: days.length,
        itemBuilder: (_, i) {
          final day = days[i];
          final active = day == selDay;
          // weekday: 1=Mon … 7=Sun
          final label = '${day.day}\n${dayLabels[day.weekday - 1]}';

          return GestureDetector(
            onTap: () => onSelect(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: active ? null : Border.all(color: cs.outline),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? cs.onPrimary : cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

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
