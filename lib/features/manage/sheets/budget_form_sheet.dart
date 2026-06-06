import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/app_database.dart';
import '../../../state/home_providers.dart';
import '../../../state/manage_providers.dart';

Future<void> showBudgetFormSheet(
  BuildContext context, {
  Budget? editing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BudgetFormSheet(editing: editing),
  );
}

class _BudgetFormSheet extends ConsumerStatefulWidget {
  const _BudgetFormSheet({this.editing});
  final Budget? editing;

  @override
  ConsumerState<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<_BudgetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  String? _categoryId;
  String? _accountId;
  String _period = 'month';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _amountCtrl = TextEditingController(
        text: e != null ? e.amount.toStringAsFixed(2) : '');
    _categoryId = e?.categoryId;
    _accountId = e?.accountId;
    _period = e?.period ?? 'month';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a category')));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(budgetsRepositoryProvider);
    try {
      final amount = double.tryParse(
              _amountCtrl.text.trim().replaceAll(',', '')) ??
          0;
      if (widget.editing == null) {
        await repo.create(
          categoryId: _categoryId!,
          amount: amount,
          period: _period,
          accountId: _accountId,
        );
      } else {
        await repo.update(
          widget.editing!,
          amount: amount,
          period: _period,
          accountId: _accountId,
        );
      }
      if (mounted) Navigator.of(context).pop();
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
    final cs = Theme.of(context).colorScheme;
    final isEditing = widget.editing != null;
    final catsAsync = ref.watch(categoriesStreamProvider);
    final accsAsync = ref.watch(accountsStreamProvider);

    final expenseCategories = (catsAsync.valueOrNull ?? <Category>[])
        .where((c) =>
            (c.kind == 'expense' || c.kind == 'both') && !c.isArchived)
        .toList();
    final accounts = (accsAsync.valueOrNull ?? <Account>[])
        .where((a) => !a.isArchived)
        .toList();

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
                isEditing ? 'Edit Budget' : 'New Budget',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration:
                    const InputDecoration(labelText: 'Category *'),
                hint: const Text('Select category'),
                items: expenseCategories
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.icon} ${c.name}'),
                        ))
                    .toList(),
                onChanged:
                    isEditing ? null : (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Budget Amount *',
                  prefixText: '₹ ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final n =
                      double.tryParse(v?.replaceAll(',', '') ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text('Period',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'month', label: Text('Monthly')),
                  ButtonSegment(value: 'week', label: Text('Weekly')),
                ],
                selected: {_period},
                onSelectionChanged: (s) =>
                    setState(() => _period = s.first),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _accountId,
                decoration: const InputDecoration(
                  labelText: 'Account (optional)',
                  helperText: 'Leave empty to budget across all accounts',
                ),
                hint: const Text('All accounts'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All accounts')),
                  ...accounts.map((a) => DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text('${a.icon} ${a.name}'),
                      )),
                ],
                onChanged: (v) => setState(() => _accountId = v),
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
                    : Text(isEditing ? 'Save Changes' : 'Create Budget'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
