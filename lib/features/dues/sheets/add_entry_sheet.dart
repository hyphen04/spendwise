import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/db/app_database.dart';
import '../../../state/dues_providers.dart';
import '../../../app/widgets/mono_numpad.dart';
import '../../../app/widgets/mono_pill.dart';
import '../../../app/widgets/date_strip.dart';

Future<void> showAddDueEntrySheet(
  BuildContext context, {
  DueContact? prefilledContact,
  DueEntry? existingEntry,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _AddEntrySheet(
      prefilledContact: prefilledContact,
      existingEntry: existingEntry,
    ),
  );
}

class _AddEntrySheet extends ConsumerStatefulWidget {
  const _AddEntrySheet({this.prefilledContact, this.existingEntry});
  final DueContact? prefilledContact;
  final DueEntry? existingEntry;

  @override
  ConsumerState<_AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends ConsumerState<_AddEntrySheet> {
  DueContact? _selectedContact;
  String _amount = '0';
  String _direction = 'payable'; // 'payable' (I owe them) or 'receivable' (They owe me)
  DateTime _date = DateTime.now();
  String? _mealSlot;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _selectedContact = widget.prefilledContact;
    
    if (widget.existingEntry != null) {
      final e = widget.existingEntry!;
      _amount = e.amount.toStringAsFixed(0);
      _direction = e.direction;
      _date = DateTime.parse(e.entryDate);
      _mealSlot = e.mealSlot;
      _noteCtrl = TextEditingController(text: e.note);
    } else {
      _noteCtrl = TextEditingController(text: _selectedContact?.defaultNote ?? '');
      if (_selectedContact != null && _selectedContact!.defaultAmount != null) {
        _amount = _selectedContact!.defaultAmount!.toStringAsFixed(0);
      }
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _onNumpadTap(String val) {
    setState(() {
      if (_amount == '0' && val != '00') {
        _amount = val;
      } else if (_amount.length < 9) {
        _amount += val;
      }
    });
  }

  void _onNumpadBackspace() {
    setState(() {
      if (_amount.length > 1) {
        _amount = _amount.substring(0, _amount.length - 1);
      } else {
        _amount = '0';
      }
    });
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amount) ?? 0;
    if (amt <= 0 || _selectedContact == null) return;

    final repo = ref.read(duesRepositoryProvider);
    if (widget.existingEntry != null) {
      await repo.updateEntry(
        widget.existingEntry!,
        amount: amt,
        direction: _direction,
        date: _date,
        mealSlot: _selectedContact!.type == 'vendor' ? _mealSlot : null,
        note: _noteCtrl.text.trim(),
      );
    } else {
      await repo.addEntry(
        contactId: _selectedContact!.id,
        amount: amt,
        direction: _direction,
        date: _date,
        mealSlot: _selectedContact!.type == 'vendor' ? _mealSlot : null,
        note: _noteCtrl.text.trim(),
      );
    }
    
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amtVal = double.tryParse(_amount) ?? 0;
    final isValid = amtVal > 0 && _selectedContact != null;
    
    final isVendor = _selectedContact?.type == 'vendor';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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

            // Contact
            if (_selectedContact != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_selectedContact!.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(
                    _selectedContact!.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, 
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // Direction Toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MonoPill(
                    label: 'I owe them',
                    selected: _direction == 'payable',
                    dense: true,
                    onTap: () => setState(() => _direction = 'payable'),
                  ),
                  const SizedBox(width: 8),
                  MonoPill(
                    label: 'They owe me',
                    selected: _direction == 'receivable',
                    dense: true,
                    onTap: () => setState(() => _direction = 'receivable'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Date Strip
            DateStrip(
              selected: _date,
              onSelect: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 20),

            if (isVendor) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    MonoPill(
                      label: 'Lunch',
                      leadingIcon: Icons.wb_sunny_rounded,
                      selected: _mealSlot == 'lunch',
                      dense: true,
                      onTap: () => setState(() => _mealSlot = _mealSlot == 'lunch' ? null : 'lunch'),
                    ),
                    const SizedBox(width: 12),
                    MonoPill(
                      label: 'Dinner',
                      leadingIcon: Icons.nights_stay_rounded,
                      selected: _mealSlot == 'dinner',
                      dense: true,
                      onTap: () => setState(() => _mealSlot = _mealSlot == 'dinner' ? null : 'dinner'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Note
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _noteCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (Optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Amount
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '₹',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withValues(alpha: 0.35),
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      _amount.isEmpty ? '0' : _amount,
                      style: GoogleFonts.plusJakartaSans(
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
                  const SizedBox(width: 8),
                  if (_amount != '0')
                    IconButton(
                      onPressed: _onNumpadBackspace,
                      icon: const Icon(Icons.backspace_outlined),
                      color: cs.onSurfaceVariant,
                      tooltip: 'Delete last digit',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Numpad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: MonoNumpad(
                onDigit: _onNumpadTap,
                onBackspace: _onNumpadBackspace,
                onConfirm: isValid ? _save : null,
                bottomRightAction: NumpadAction.confirm,
                confirmEnabled: isValid,
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
