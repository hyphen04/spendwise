import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../app/themes/app_colors.dart';

import '../../../data/db/app_database.dart';
import '../../../state/dues_providers.dart';
import '../../../widgets/swipe_action_button.dart';
import '../../../state/manage_providers.dart';
import '../../../state/prefs_providers.dart';

Future<void> showSettleSheet(
  BuildContext context, {
  required DueContact contact,
  required List<DueEntry> entries,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _SettleSheet(contact: contact, entries: entries),
  );
}

class _SettleSheet extends ConsumerStatefulWidget {
  const _SettleSheet({required this.contact, required this.entries});
  final DueContact contact;
  final List<DueEntry> entries;

  @override
  ConsumerState<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<_SettleSheet> {
  late Set<String> _selectedEntryIds;
  bool _createExpense = false;
  late final TextEditingController _noteCtrl;

  /// The settlement date — also the posting date of the linked transaction, so
  /// reports count that transaction on this date. Defaults to today; the user
  /// can back-date it (e.g. recording a settlement that happened yesterday).
  late DateTime _selectedDate;

  String? _accountId;
  String? _categoryId;
  String? _modeId;

  int _step = 0;

  @override
  void initState() {
    super.initState();
    _selectedEntryIds = widget.entries.map((e) => e.id).toSet();
    _createExpense = true; // default enabled
    _noteCtrl = TextEditingController(text: 'Settled dues for ${widget.contact.name}');
    _selectedDate = DateTime.now();

    // Set default account, mode, and category
    _accountId = ref.read(defaultAccountIdProvider);
    _modeId = ref.read(defaultModeIdProvider);
    _categoryId = widget.contact.defaultCategoryId;
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

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('d MMM yyyy').format(d);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _totalAmount {
    double total = 0;
    for (final e in widget.entries) {
      if (_selectedEntryIds.contains(e.id)) {
        if (e.direction == 'receivable') {
          total += e.amount;
        } else {
          total -= e.amount; // payable is negative for total
        }
      }
    }
    return total;
  }

  Future<void> _settle() async {
    if (_selectedEntryIds.isEmpty) return;
    
    final amt = _totalAmount;
    if (amt == 0) return; // Cannot settle a 0 balance

    final repo = ref.read(duesRepositoryProvider);
    
    // If it's a vendor, payable implies expense. If friend, receivable implies income.
    String? kind;
    if (_createExpense) {
      if (amt < 0) {
        kind = 'expense';
      } else {
        kind = 'income';
      }
    }

    await repo.settleEntries(
      contactId: widget.contact.id,
      entryIds: _selectedEntryIds.toList(),
      totalAmount: amt.abs(),
      note: _noteCtrl.text.trim(),
      // Day-only normalization (drops any time component) — this date is used
      // for both the settlement's settledDate and the linked transaction's
      // posting date, which reports group by.
      date: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
      createLinkedTransaction: _createExpense,
      accountId: _accountId,
      categoryId: _categoryId,
      modeId: _modeId,
      transactionKind: kind,
    );
    
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final botPad = MediaQuery.viewInsetsOf(context).bottom;
    
    final total = _totalAmount;
    final isPayable = total < 0;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + botPad),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_step == 1) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => setState(() => _step = 0),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(widget.contact.icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Settle ${widget.contact.name}',
                      style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              if (_step == 0) ...[
                Text(
                  'Select entries to settle (${_selectedEntryIds.length}/${widget.entries.length}):',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.entries.length,
                    separatorBuilder: (c, i) => Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (context, i) {
                      final e = widget.entries[i];
                      final selected = _selectedEntryIds.contains(e.id);
                      return CheckboxListTile(
                        value: selected,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedEntryIds.add(e.id);
                            } else {
                              _selectedEntryIds.remove(e.id);
                            }
                          });
                        },
                        title: Text(
                          '₹${e.amount.toStringAsFixed(0)} • ${e.note.isEmpty ? 'Entry' : e.note}',
                          style: GoogleFonts.plusJakartaSans(
                            decoration: selected ? null : TextDecoration.lineThrough,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          DateFormat('dd MMM').format(DateTime.parse(e.entryDate)),
                          style: GoogleFonts.plusJakartaSans(),
                        ),
                        secondary: Icon(
                          e.direction == 'payable' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          color: e.direction == 'payable' ? appColors.expense : appColors.income,
                          size: 16,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),
                
                FilledButton.icon(
                  onPressed: _selectedEntryIds.isEmpty ? null : () => setState(() => _step = 1),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(
                    'Next (₹${total.abs().toStringAsFixed(0)}) • ${_selectedEntryIds.length} entries',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],

              if (_step == 1) ...[
                // Settlement date — always shown, since it sets the
                // settlement's settledDate regardless of whether a linked
                // transaction is created. Tapping opens the date picker
                // (back-dateable to 2000, ≤ today, matching the rest of the app).
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Settlement date',
                      suffixIcon: const Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_formatDate(_selectedDate),
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Add to Transactions'),
                  subtitle: const Text('Creates a linked income/expense'),
                  value: _createExpense,
                  onChanged: (v) => setState(() => _createExpense = v),
                  contentPadding: EdgeInsets.zero,
                ),
                
                if (_createExpense) ...[
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final accounts = (ref.watch(accountsStreamProvider).valueOrNull ?? [])
                          .where((a) => !a.isArchived)
                          .toList();
                      if (accounts.isNotEmpty && !accounts.any((a) => a.id == _accountId)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _accountId = accounts.first.id);
                        });
                      }
                      return _PickerRow(
                        label: 'Account',
                        child: DropdownButtonFormField<String>(
                          initialValue: _accountId,
                          items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                          onChanged: (v) => setState(() => _accountId = v),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final modes = (ref.watch(modesStreamProvider).valueOrNull ?? [])
                          .where((m) => !m.isArchived)
                          .toList();
                      if (modes.isNotEmpty && !modes.any((m) => m.id == _modeId)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _modeId = modes.first.id);
                        });
                      }
                      return _PickerRow(
                        label: 'Mode',
                        child: DropdownButtonFormField<String>(
                          initialValue: _modeId,
                          items: modes.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
                          onChanged: (v) => setState(() => _modeId = v),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final categories = (ref.watch(categoriesStreamProvider).valueOrNull ?? [])
                          .where((c) => !c.isArchived)
                          .toList();
                      if (categories.isNotEmpty && _categoryId != null && !categories.any((c) => c.id == _categoryId)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _categoryId = categories.first.id);
                        });
                      }
                      return _PickerRow(
                        label: 'Category',
                        child: DropdownButtonFormField<String>(
                          initialValue: _categoryId,
                          items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                          onChanged: (v) => setState(() => _categoryId = v),
                        ),
                      );
                    },
                  ),
                ],
                
                const SizedBox(height: 24),
                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(labelText: 'Settlement Note'),
                ),
                const SizedBox(height: 32),
                
                SwipeActionButton(
                  label: 'Swipe to Settle ₹${total.abs().toStringAsFixed(0)} (${_selectedEntryIds.length})',
                  color: isPayable ? appColors.expense : appColors.income,
                  enabled: _selectedEntryIds.isNotEmpty,
                  onAction: _settle,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: child),
      ],
    );
  }
}
