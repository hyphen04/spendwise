import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/app_database.dart';
import '../../../data/validators.dart';
import '../../../state/manage_providers.dart';
import '../widgets/color_picker_row.dart';

Future<void> showAccountFormSheet(
  BuildContext context, {
  Account? editing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AccountFormSheet(editing: editing),
  );
}

class _AccountFormSheet extends ConsumerStatefulWidget {
  const _AccountFormSheet({this.editing});
  final Account? editing;

  @override
  ConsumerState<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<_AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _iconCtrl;
  late final TextEditingController _balanceCtrl;
  late String _selectedColor;
  late String _currency;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _iconCtrl = TextEditingController(text: e?.icon ?? '🏦');
    _balanceCtrl = TextEditingController(
        text: e?.openingBalance.toStringAsFixed(2) ?? '0.00');
    _selectedColor = e?.color ?? '#0284C7';
    _currency = e?.currency ?? 'INR';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _iconCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final repo = ref.read(accountsRepositoryProvider);
    try {
      final balance = double.tryParse(
              _balanceCtrl.text.trim().replaceAll(',', '')) ??
          0.0;
      if (widget.editing == null) {
        await repo.create(
          name: _nameCtrl.text.trim(),
          icon: _iconCtrl.text.trim(),
          color: _selectedColor,
          openingBalance: balance,
          currency: _currency,
        );
      } else {
        await repo.update(
          widget.editing!,
          name: _nameCtrl.text.trim(),
          icon: _iconCtrl.text.trim(),
          color: _selectedColor,
          openingBalance: balance,
          currency: _currency,
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

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                isEditing ? 'Edit Account' : 'New Account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: TextFormField(
                      controller: _iconCtrl,
                      decoration: const InputDecoration(
                        hintText: '🏦',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 14),
                      ),
                      style: const TextStyle(fontSize: 24),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name *'),
                      textCapitalization: TextCapitalization.words,
                      validator: AppValidators.entityName,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _balanceCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Opening Balance'),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                ],
              ),
              if (isEditing) ...[
                const SizedBox(height: 8),
                Consumer(
                  builder: (context, ref, _) {
                    final netAsync = ref.watch(accountNetBalanceProvider(widget.editing!));
                    final curBal = netAsync.valueOrNull ?? widget.editing!.openingBalance;
                    return Text(
                      'Current Balance: $_currency ${curBal.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 20),
              Text('Color', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 10),
              ColorPickerRow(
                selected: _selectedColor,
                onChanged: (c) => setState(() => _selectedColor = c),
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
                    : Text(isEditing ? 'Save Changes' : 'Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
