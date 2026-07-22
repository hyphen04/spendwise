import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/utils/feedback.dart';
import '../../../data/db/app_database.dart';
import '../../../state/bills_providers.dart';
import '../../../state/manage_providers.dart';
import '../../../utils/amount_input_formatter.dart';
import '../../../app/widgets/spendwise_sheet.dart';

Future<void> showRecurringFormSheet(
  BuildContext context, {
  RecurringItem? editing,
}) {
  return showSpendWiseSheet(
    context,
    builder: (_) => _RecurringFormSheet(editing: editing),
  );
}

class _RecurringFormSheet extends ConsumerStatefulWidget {
  const _RecurringFormSheet({this.editing});
  final RecurringItem? editing;

  @override
  ConsumerState<_RecurringFormSheet> createState() => _RecurringFormSheetState();
}

class _RecurringFormSheetState extends ConsumerState<_RecurringFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _noteCtrl;
  String? _categoryId;
  String? _accountId;
  String? _modeId;
  String _cadence = 'monthly';
  DateTime _nextDue = DateTime.now().add(const Duration(days: 1));
  bool _saving = false;

  static const _cadences = {
    'weekly': 'Weekly',
    'fortnightly': 'Fortnightly',
    'monthly': 'Monthly',
    'quarterly': 'Quarterly',
    'yearly': 'Yearly',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _amountCtrl =
        TextEditingController(text: e != null ? e.amount.toStringAsFixed(2) : '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _categoryId = e?.categoryId;
    _accountId = e?.accountId;
    _modeId = e?.modeId;
    _cadence = e?.cadence ?? 'monthly';
    if (e != null) {
      final parsed = DateTime.tryParse(e.nextDueDate);
      if (parsed != null) _nextDue = parsed;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDue,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _nextDue = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a category')));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(recurringRepositoryProvider);
    try {
      final amount =
          double.tryParse(_amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
      final name = _nameCtrl.text.trim();
      if (widget.editing == null) {
        await repo.create(
          name: name,
          amount: amount,
          categoryId: _categoryId!,
          accountId: _accountId,
          modeId: _modeId,
          cadence: _cadence,
          nextDueDate: _nextDue,
          note: _noteCtrl.text.trim(),
        );
      } else {
        await repo.update(
          widget.editing!,
          name: name,
          amount: amount,
          categoryId: _categoryId!,
          accountId: _accountId,
          modeId: _modeId,
          cadence: _cadence,
          nextDueDate: _nextDue,
          note: _noteCtrl.text.trim(),
        );
      }
      if (mounted) {
        showFeedbackSnackBar(
            context, widget.editing == null ? 'Bill added' : 'Bill updated');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editing != null;
    final catsAsync = ref.watch(categoriesStreamProvider);
    final accsAsync = ref.watch(accountsStreamProvider);
    final modesAsync = ref.watch(modesStreamProvider);

    final expenseCategories = (catsAsync.valueOrNull ?? <Category>[])
        .where((c) => (c.kind == 'expense' || c.kind == 'both') && !c.isArchived)
        .toList();
    final accounts =
        (accsAsync.valueOrNull ?? <Account>[]).where((a) => !a.isArchived).toList();
    final modes =
        (modesAsync.valueOrNull ?? <Mode>[]).where((m) => !m.isArchived).toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isEditing ? 'Edit Bill' : 'New Bill',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category *'),
                hint: const Text('Select category'),
                items: expenseCategories
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.icon} ${c.name}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Amount *',
                  prefixText: '₹ ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: amountInputFormatters,
                validator: (v) {
                  final n = double.tryParse(v?.replaceAll(',', '') ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _cadence,
                decoration: const InputDecoration(labelText: 'Repeats'),
                items: [
                  // The detector emits a free-form "every N days" cadence for
                  // gaps that don't fit a clean bucket. Keep it as a selectable
                  // item when editing such a row so the dropdown's value matches
                  // exactly one entry (otherwise DropdownButton asserts). The
                  // engine's _addCadence handles "every N days" via regex.
                  if (_cadence.isNotEmpty && !_cadences.containsKey(_cadence))
                    DropdownMenuItem(value: _cadence, child: Text(_cadence)),
                  for (final e in _cadences.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ),
                ],
                onChanged: (v) => setState(() => _cadence = v ?? 'monthly'),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Next due date *',
                    suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                  ),
                  child: Text(_fmtDate(_nextDue)),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _accountId,
                decoration: const InputDecoration(
                  labelText: 'Account (optional)',
                  helperText: 'Where it\'s paid from',
                ),
                hint: const Text('Any account'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Any account')),
                  ...accounts.map((a) => DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text('${a.icon} ${a.name}',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _modeId,
                decoration: const InputDecoration(labelText: 'Mode (optional)'),
                hint: const Text('Any mode'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Any mode')),
                  ...modes.map((m) => DropdownMenuItem<String?>(
                        value: m.id,
                        child: Text('${m.icon} ${m.name}',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _modeId = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  helperText: 'Stays on this device — never sent to the AI.',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isEditing ? 'Save Changes' : 'Add Bill'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} '
      '${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} '
      '${d.year}';
}