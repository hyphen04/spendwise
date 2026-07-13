import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/utils/feedback.dart';
import '../../../data/db/app_database.dart';
import '../../../state/goals_providers.dart';
import '../../../state/manage_providers.dart';
import '../../../utils/amount_input_formatter.dart';
import '../../../app/widgets/spendwise_sheet.dart';

Future<void> showGoalFormSheet(
  BuildContext context, {
  Goal? editing,
}) {
  return showSpendWiseSheet(
    context,
    builder: (_) => _GoalFormSheet(editing: editing),
  );
}

class _GoalFormSheet extends ConsumerStatefulWidget {
  const _GoalFormSheet({this.editing});
  final Goal? editing;

  @override
  ConsumerState<_GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends ConsumerState<_GoalFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _commitmentCtrl;
  String _icon = '🎯';
  String _color = '#2563EB';
  DateTime? _targetDate;
  String? _linkedAccountId;
  bool _saving = false;

  static const _iconChoices = <String>[
    '🎯', '📱', '💻', '🚗', '🏠', '✈️', '🎓', '💍', '👶', '🛵', '🎁', '🛟',
  ];
  static const _colorChoices = <String>[
    '#2563EB', // blue
    '#16A34A', // green
    '#F59E0B', // amber
    '#DC2626', // red
    '#9333EA', // purple
    '#0EA5E9', // sky
    '#DB2777', // pink
    '#475569', // slate
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _targetCtrl =
        TextEditingController(text: e != null ? e.targetAmount.toStringAsFixed(2) : '');
    _commitmentCtrl = TextEditingController(
        text: e?.monthlyCommitment != null
            ? e!.monthlyCommitment!.toStringAsFixed(0)
            : '');
    _icon = e?.icon ?? '🎯';
    _color = e?.color ?? '#2563EB';
    if (e?.targetDate != null) {
      _targetDate = DateTime.tryParse(e!.targetDate!);
    }
    _linkedAccountId = e?.linkedAccountId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    _commitmentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final initial = _targetDate ?? DateTime.now().add(const Duration(days: 90));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final repo = ref.read(goalsRepositoryProvider);
    try {
      final target =
          double.tryParse(_targetCtrl.text.trim().replaceAll(',', '')) ?? 0;
      final commitment = double.tryParse(
          _commitmentCtrl.text.trim().replaceAll(',', ''));
      final name = _nameCtrl.text.trim();
      if (widget.editing == null) {
        await repo.create(
          name: name,
          targetAmount: target,
          icon: _icon,
          color: _color,
          targetDate: _targetDate,
          linkedAccountId: _linkedAccountId,
          monthlyCommitment: commitment,
        );
      } else {
        await repo.update(
          widget.editing!,
          name: name,
          targetAmount: target,
          icon: _icon,
          color: _color,
          targetDate: _targetDate,
          linkedAccountId: _linkedAccountId,
          monthlyCommitment: commitment,
        );
      }
      if (mounted) {
        showFeedbackSnackBar(
            context, widget.editing == null ? 'Goal added' : 'Goal updated');
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
    final cs = Theme.of(context).colorScheme;
    final isEditing = widget.editing != null;
    final accounts = (ref.watch(accountsStreamProvider).valueOrNull ?? <Account>[])
        .where((a) => !a.isArchived)
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isEditing ? 'Edit Goal' : 'New Goal',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Goal name *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              // Icon picker
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _iconChoices.map((e) {
                  final sel = e == _icon;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _icon = e),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: sel ? cs.primaryContainer : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: sel
                            ? Border.all(color: cs.primary, width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Color picker
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: _colorChoices.map((c) {
                  final sel = c == _color;
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _hex(c),
                        shape: BoxShape.circle,
                        border: sel
                            ? Border.all(color: cs.onSurface, width: 2.5)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _targetCtrl,
                decoration: const InputDecoration(
                  labelText: 'Target amount *',
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
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Target date (optional)',
                    helperText: 'When you\'d like to reach it',
                    suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                  ),
                  child: Text(_targetDate == null
                      ? 'No deadline'
                      : _fmtDate(_targetDate!)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _commitmentCtrl,
                decoration: const InputDecoration(
                  labelText: 'Monthly commitment (optional)',
                  prefixText: '₹ ',
                  helperText: 'A "Save More Tomorrow" pledge — your number to '
                      'set aside each month. The app won\'t move money.',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: amountInputFormatters,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _linkedAccountId,
                decoration: const InputDecoration(
                  labelText: 'Linked account (optional)',
                  helperText: 'Where you\'re saving toward this',
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
                onChanged: (v) => setState(() => _linkedAccountId = v),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isEditing ? 'Save Changes' : 'Add Goal'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _hex(String hex) => Color(int.parse(hex.substring(1), radix: 16))
      .withAlpha(255);

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} '
      '${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} '
      '${d.year}';
}