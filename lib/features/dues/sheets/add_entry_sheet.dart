import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/db/app_database.dart';
import '../../../state/dues_providers.dart';
import '../../../app/utils/feedback.dart';
import '../../../app/widgets/mono_numpad.dart';
import '../../../app/widgets/mono_pill.dart';
import '../../../app/widgets/date_strip.dart';
import '../../../app/widgets/spendwise_sheet.dart';

Future<void> showAddDueEntrySheet(
  BuildContext context, {
  DueContact? prefilledContact,
  DueEntry? existingEntry,
}) {
  return showSpendWiseSheet(
    context,
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
  // The numpad is on-demand: the sheet opens in a short compact form (contact,
  // direction, date, note, a tappable amount, Save). Tapping the amount
  // expands just the numpad; confirming saves, the chevron collapses it back.
  // This keeps the default sheet short so it never crowds the status bar.
  bool _numpadOpen = false;

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

  /// [_amount] grouped Indian-style (last 3, then pairs) so large figures are
  /// readable, e.g. 10000000 → "1,00,00,000". A decimal part (from the numpad's
  /// `.` key) is preserved untouched after the point. Used by both the compact
  /// amount row and the on-demand numpad header, paired with a FittedBox so the
  /// figure always shrinks to fit instead of being cut off with an ellipsis.
  String _groupedAmount() {
    final raw = _amount.isEmpty ? '0' : _amount;
    final dot = raw.indexOf('.');
    if (dot < 0) return _groupInt(raw);
    final intPart = dot == 0 ? '0' : raw.substring(0, dot);
    final frac = raw.substring(dot + 1);
    return frac.isEmpty ? '${_groupInt(intPart)}.' : '${_groupInt(intPart)}.$frac';
  }

  String _groupInt(String digits) {
    final only = digits.replaceAll(RegExp(r'[^0-9]'), '');
    if (only.length <= 3) return digits.isEmpty ? '0' : digits;
    final head = only.substring(0, only.length - 3);
    final tail = only.substring(only.length - 3);
    final sb = StringBuffer();
    var i = 0;
    if (head.length % 2 == 1) {
      sb.write(head[0]);
      i = 1;
    }
    for (; i < head.length; i += 2) {
      if (sb.isNotEmpty) sb.write(',');
      sb.write(head.substring(i, i + 2));
    }
    sb.write(',');
    sb.write(tail);
    return sb.toString();
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
    
    if (mounted) {
      showFeedbackSnackBar(
          context, widget.existingEntry != null ? 'Entry updated' : 'Entry added');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amtVal = double.tryParse(_amount) ?? 0;
    final isValid = amtVal > 0 && _selectedContact != null;
    final isVendor = _selectedContact?.type == 'vendor';
    final isUpdate = widget.existingEntry != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _numpadOpen
          ? _buildNumpadView(cs, isValid)
          : _buildCompactView(cs, isValid, isVendor, isUpdate),
    );
  }

  // Default, short form: everything except the numpad. A tap on the amount
  // row is what opens the on-demand numpad. If the prefilled defaults are
  // fine, the user just taps Save without ever opening the numpad.
  Widget _buildCompactView(
      ColorScheme cs, bool isValid, bool isVendor, bool isUpdate) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 20),

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
                    onTap: () =>
                        setState(() => _mealSlot = _mealSlot == 'lunch' ? null : 'lunch'),
                  ),
                  const SizedBox(width: 12),
                  MonoPill(
                    label: 'Dinner',
                    leadingIcon: Icons.nights_stay_rounded,
                    selected: _mealSlot == 'dinner',
                    dense: true,
                    onTap: () => setState(
                        () => _mealSlot = _mealSlot == 'dinner' ? null : 'dinner'),
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
          const SizedBox(height: 20),

          // Tappable amount — opens the on-demand numpad.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: InkWell(
              onTap: () => setState(() => _numpadOpen = true),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text(
                      'Amount',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '₹${_groupedAmount()}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.keyboard_outlined, size: 20, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Save
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FilledButton(
              onPressed: isValid ? _save : null,
              child: Text(isUpdate ? 'Save Changes' : 'Add Entry'),
            ),
          ),
        ],
      ),
    );
  }

  // On-demand numpad: focused amount entry. The chevron collapses back to the
  // compact form (close-without-saving); the green confirm key saves. A
  // backspace icon next to the amount handles deletions (the numpad's
  // bottom-right is the confirm key in this mode).
  Widget _buildNumpadView(ColorScheme cs, bool isValid) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: centered amount, with clear (backspace) + hide-keypad on
        // the right. Left is a balancing spacer so the amount stays centered.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              const SizedBox(width: 96), // balances the two right-side buttons
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
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
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _groupedAmount(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              height: 1.0,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Right — clear last digit, then hide the keypad.
              IconButton(
                onPressed: _amount != '0' ? _onNumpadBackspace : null,
                icon: const Icon(Icons.backspace_outlined),
                color: cs.onSurfaceVariant,
                tooltip: 'Delete last digit',
              ),
              IconButton(
                onPressed: () => setState(() => _numpadOpen = false),
                icon: const Icon(Icons.keyboard_hide_outlined),
                tooltip: 'Hide keypad',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 16),
      ],
    );
  }
}
