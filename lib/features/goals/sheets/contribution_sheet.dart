import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/utils/feedback.dart';
import '../../../app/utils/money_format.dart';
import '../../../data/db/app_database.dart';
import '../../../state/goals_providers.dart';
import '../../../utils/amount_input_formatter.dart';
import '../../../app/widgets/spendwise_sheet.dart';

Future<void> showContributionSheet(
  BuildContext context, {
  required Goal goal,
}) {
  return showSpendWiseSheet(
    context,
    builder: (_) => _ContributionSheet(goal: goal),
  );
}

class _ContributionSheet extends ConsumerStatefulWidget {
  const _ContributionSheet({required this.goal});
  final Goal goal;

  @override
  ConsumerState<_ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends ConsumerState<_ContributionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final amount =
          double.tryParse(_amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
      await ref.read(goalsRepositoryProvider).contribute(widget.goal, amount);
      if (mounted) {
        showFeedbackSnackBar(context, 'Contribution added');
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
    final g = widget.goal;
    final saved = g.savedAmount;
    final target = g.targetAmount;
    final pct = target > 0 ? (saved / target * 100).clamp(0, 100000) : 0.0;

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
              Text('Add to ${g.name}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '${fmtMoney(saved)} of ${fmtMoney(target)} saved · ${pct.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _amountCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Contribution *',
                  prefixText: '₹ ',
                  helperText: 'Enter a negative amount to adjust down.',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: amountInputFormatters,
                validator: (v) {
                  final n = double.tryParse(v?.replaceAll(',', '') ?? '');
                  if (n == null) return 'Enter an amount';
                  return null;
                },
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add Contribution'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}