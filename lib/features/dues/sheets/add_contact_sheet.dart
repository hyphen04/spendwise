import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/db/app_database.dart';
import '../../../state/dues_providers.dart';
import '../../../state/manage_providers.dart';

Future<void> showAddContactSheet(BuildContext context, {DueContact? existingContact}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddContactSheet(existingContact: existingContact),
  );
}

class _AddContactSheet extends ConsumerStatefulWidget {
  const _AddContactSheet({this.existingContact});
  final DueContact? existingContact;

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amtCtrl;
  late final TextEditingController _noteCtrl;
  
  late String _type;
  late String _icon;
  late String _color;
  String? _defaultCategoryId;

  final _icons = ['👤', '🍱', '🚗', '🏠', '🛒', '🍻', '☕', '🎮', '💼'];
  final _colors = [
    '#E91E63', '#9C27B0', '#673AB7', '#3F51B5', '#2196F3',
    '#00BCD4', '#009688', '#4CAF50', '#8BC34A', '#FF9800',
    '#FF5722', '#795548', '#607D8B'
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.existingContact;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _amtCtrl = TextEditingController(text: c?.defaultAmount?.toStringAsFixed(0) ?? '');
    _noteCtrl = TextEditingController(text: c?.defaultNote ?? '');
    _type = c?.type ?? 'person';
    _icon = c?.icon ?? '👤';
    _color = c?.color ?? _colors[0];
    _defaultCategoryId = c?.defaultCategoryId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final amt = double.tryParse(_amtCtrl.text);
    final note = _noteCtrl.text.trim();

    final repo = ref.read(duesRepositoryProvider);
    if (widget.existingContact != null) {
      await repo.updateContact(
        widget.existingContact!,
        name: name,
        icon: _icon,
        color: _color,
        type: _type,
        defaultAmount: amt,
        defaultNote: note.isEmpty ? null : note,
        defaultCategoryId: _defaultCategoryId,
      );
    } else {
      await repo.createContact(
        name: name,
        icon: _icon,
        color: _color,
        type: _type,
        defaultAmount: amt,
        defaultNote: note.isEmpty ? null : note,
        defaultCategoryId: _defaultCategoryId,
      );
    }
    
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final repo = ref.read(duesRepositoryProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact?'),
        content: const Text('Are you sure you want to delete this contact? You cannot undo this action.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await repo.deleteContact(widget.existingContact!.id);
      if (mounted) {
        nav.pop(); // close sheet
        nav.pop(); // close detail screen
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: const Text('Cannot delete contact. Settle or delete their entries first.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final botPad = MediaQuery.viewInsetsOf(context).bottom;
    final isUpdate = widget.existingContact != null;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + botPad),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isUpdate ? 'Edit Contact' : 'New Contact',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20, 
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            
            // Type toggle
            Row(
              children: [
                Expanded(
                  child: _TypeToggle(
                    label: 'Person',
                    icon: Icons.person_rounded,
                    isSelected: _type == 'person',
                    onTap: () => setState(() => _type = 'person'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeToggle(
                    label: 'Vendor',
                    icon: Icons.storefront_rounded,
                    isSelected: _type == 'vendor',
                    onTap: () => setState(() {
                      _type = 'vendor';
                      if (_icon == '👤') _icon = '🍱';
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                prefixIcon: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Text(_icon, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Icon Picker
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _icons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final icon = _icons[i];
                  final isSelected = icon == _icon;
                  return GestureDetector(
                    onTap: () => setState(() => _icon = icon),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: cs.primary, width: 2) : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(icon, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Color Picker
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _colors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final colorHex = _colors[i];
                  final color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
                  final isSelected = colorHex == _color;
                  return GestureDetector(
                    onTap: () => setState(() => _color = colorHex),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: cs.onSurface, width: 2) : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Default Amount (Optional)',
                prefixText: '₹ ',
                helperText: 'Quick-fill for recurring entries (e.g. tiffin cost)',
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _noteCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Default Note (Optional)',
                helperText: 'Quick-fill for recurring entries (e.g. "Dinner")',
              ),
            ),
            const SizedBox(height: 16),
            
            Builder(
              builder: (context) {
                final categories = (ref.watch(categoriesStreamProvider).valueOrNull ?? [])
                    .where((c) => !c.isArchived)
                    .toList();
                
                // Ensure selected ID still exists in the list
                if (categories.isNotEmpty && _defaultCategoryId != null && !categories.any((c) => c.id == _defaultCategoryId)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _defaultCategoryId = null);
                  });
                }
                
                return DropdownButtonFormField<String>(
                  initialValue: _defaultCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Default Category (Optional)',
                    helperText: 'Auto-selects this category when settling dues',
                  ),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('None')),
                    ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setState(() => _defaultCategoryId = v),
                );
              },
            ),
            const SizedBox(height: 32),
            
            FilledButton(
              onPressed: _nameCtrl.text.trim().isNotEmpty ? _save : null,
              child: Text(isUpdate ? 'Save Changes' : 'Create Contact'),
            ),
            if (isUpdate) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _delete,
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                ),
                child: const Text('Delete Contact'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
