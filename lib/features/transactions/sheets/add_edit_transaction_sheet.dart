import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/app_database.dart';
import '../../../data/validators.dart';
import '../../../state/manage_providers.dart';
import '../../../state/transactions_providers.dart';
import 'amount_entry_sheet.dart';

// ── Mode filtering helpers ────────────────────────────────────────────────────

bool _isCashAccount(String? id, List<Account> accounts) {
  if (id == null) return false;
  final m = accounts.where((a) => a.id == id);
  return m.isNotEmpty && m.first.name.toLowerCase().contains('cash');
}

Mode? _cashMode(List<Mode> modes) {
  final m = modes.where((m) => m.name.toLowerCase() == 'cash');
  return m.isEmpty ? null : m.first;
}

List<Mode> _digitalModes(List<Mode> modes) =>
    modes.where((m) => m.name.toLowerCase() != 'cash').toList();

Future<void> showAddEditTransactionSheet(
  BuildContext context, {
  Transaction? editing,
  String initialKind = 'expense',
}) {
  if (editing == null) {
    return showAmountEntrySheet(context, initialKind: initialKind);
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddEditSheet(editing: editing, initialKind: initialKind),
  );
}

class _AddEditSheet extends ConsumerStatefulWidget {
  const _AddEditSheet({this.editing, required this.initialKind});
  final Transaction? editing;
  final String initialKind;

  @override
  ConsumerState<_AddEditSheet> createState() => _AddEditSheetState();
}

class _AddEditSheetState extends ConsumerState<_AddEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late String _kind;
  late DateTime _selectedDate;
  String? _accountId;
  String? _toAccountId; // for transfers
  String? _categoryId;
  String? _modeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _kind = e?.kind ?? widget.initialKind;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _amountCtrl = TextEditingController(
        text: e != null ? _fmtAmt(e.amount) : '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _selectedDate = e != null
        ? DateTime.tryParse(e.transactionDate) ?? DateTime.now()
        : DateTime.now();
    _accountId = e?.accountId;
    _categoryId = e?.categoryId == AppDatabase.kTransferCategoryId
        ? null
        : e?.categoryId;
    _modeId = e?.modeId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _isTransfer => _kind == 'transfer';
  bool get _isEditing => widget.editing != null;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.parse(
        _amountCtrl.text.trim().replaceAll(',', ''));
    final date = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    ).toIso8601String();

    setState(() => _saving = true);
    final repo = ref.read(transactionsRepositoryProvider);
    try {
      if (_isTransfer) {
        if (_accountId == null || _toAccountId == null) {
          _showError('Select both source and destination accounts.');
          return;
        }
        if (_accountId == _toAccountId) {
          _showError('Source and destination accounts must be different.');
          return;
        }
        if (_isEditing) {
          await repo.updateTransfer(
            widget.editing!,
            title: _titleCtrl.text.trim(),
            amount: amount,
            transactionDate: date,
            fromAccountId: _accountId!,
            toAccountId: _toAccountId!,
            modeId: _modeId!,
            note: _noteCtrl.text.trim(),
          );
        } else {
          await repo.createTransfer(
            title: _titleCtrl.text.trim(),
            amount: amount,
            transactionDate: date,
            fromAccountId: _accountId!,
            toAccountId: _toAccountId!,
            modeId: _modeId!,
            note: _noteCtrl.text.trim(),
          );
        }
      } else {
        if (_accountId == null) {
          _showError('Select an account.');
          return;
        }
        if (_categoryId == null) {
          _showError('Select a category.');
          return;
        }
        if (_modeId == null) {
          _showError('Select a payment mode.');
          return;
        }
        if (_isEditing) {
          await repo.update(
            widget.editing!,
            title: _titleCtrl.text.trim(),
            amount: amount,
            transactionDate: date,
            accountId: _accountId!,
            categoryId: _categoryId!,
            modeId: _modeId!,
            kind: _kind,
            note: _noteCtrl.text.trim(),
          );
        } else {
          await repo.create(
            title: _titleCtrl.text.trim(),
            amount: amount,
            transactionDate: date,
            accountId: _accountId!,
            categoryId: _categoryId!,
            modeId: _modeId!,
            kind: _kind,
            note: _noteCtrl.text.trim(),
          );
        }
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

  void _autoSetMode(String? accountId, List<Account> accounts, List<Mode> modes) {
    final cashM = _cashMode(modes);
    if (_isCashAccount(accountId, accounts)) {
      _modeId = cashM?.id;
    } else if (cashM != null && _modeId == cashM.id) {
      _modeId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final categories = ref.watch(
          categoriesByKindProvider(_kind == 'income' ? 'income' : 'expense'),
        ).valueOrNull ??
        [];
    final modes = ref.watch(modesStreamProvider).valueOrNull ?? [];

    final modeSourceId = _isTransfer ? null : _accountId;
    final cashAccount = _isCashAccount(modeSourceId, accounts);
    final cashM = _cashMode(modes);
    final visibleModes = cashAccount ? (cashM != null ? [cashM] : modes) : _digitalModes(modes);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isEditing ? 'Edit Transaction' : 'New Transaction',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              // Kind selector
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                  ButtonSegment(value: 'income', label: Text('Income')),
                  ButtonSegment(value: 'transfer', label: Text('Transfer')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 20),

              // Amount
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Amount *',
                  prefixText: '₹ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                validator: AppValidators.amount,
                autofocus: !_isEditing,
              ),
              const SizedBox(height: 16),

              // Date
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(_formatDate(_selectedDate)),
                ),
              ),
              const SizedBox(height: 16),

              if (_isTransfer) ...[
                // From account
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration:
                      const InputDecoration(labelText: 'From Account *'),
                  items: accounts
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text('${a.icon} ${a.name}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _accountId = v),
                  validator: (v) =>
                      v == null ? 'Select a source account.' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _toAccountId,
                  decoration:
                      const InputDecoration(labelText: 'To Account *'),
                  items: accounts
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text('${a.icon} ${a.name}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _toAccountId = v),
                  validator: (v) =>
                      v == null ? 'Select a destination account.' : null,
                ),
              ] else ...[
                // Account
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration:
                      const InputDecoration(labelText: 'Account *'),
                  items: accounts
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text('${a.icon} ${a.name}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _accountId = v;
                    _autoSetMode(v, accounts, modes);
                  }),
                  validator: (v) =>
                      v == null ? 'Select an account.' : null,
                ),
                const SizedBox(height: 16),
                // Category
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration:
                      const InputDecoration(labelText: 'Category *'),
                  items: categories
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.icon} ${c.name}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _categoryId = v),
                  validator: (v) =>
                      v == null ? 'Select a category.' : null,
                ),
              ],
              const SizedBox(height: 16),

              // Mode — context-aware based on account type
              if (cashAccount && cashM != null)
                _ReadOnlyModeRow(cashMode: cashM)
              else
                DropdownButtonFormField<String>(
                  initialValue: _modeId,
                  decoration: const InputDecoration(labelText: 'Payment Mode *'),
                  hint: const Text('How was this paid?'),
                  items: visibleModes
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text('${m.icon} ${m.name}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _modeId = v),
                  validator: (v) => v == null ? 'Select a payment mode.' : null,
                ),
              const SizedBox(height: 16),

              // Note
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Optional note…',
                ),
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                validator: AppValidators.note,
              ),

              const SizedBox(height: 28),

              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? 'Save Changes' : 'Add Transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyModeRow extends StatelessWidget {
  const _ReadOnlyModeRow({required this.cashMode});
  final Mode cashMode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(cashMode.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(cashMode.name,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
          Text(
            'auto',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

String _fmtAmt(double v) {
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
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
