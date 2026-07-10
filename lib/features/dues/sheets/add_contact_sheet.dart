import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/utils/feedback.dart';
import '../../../app/utils/phone_utils.dart';
import '../../../app/widgets/contact_avatar.dart';
import '../../../data/db/app_database.dart';
import '../../../state/dues_providers.dart';
import '../../../state/manage_providers.dart';
import '../../../state/prefs_providers.dart';

Future<void> showAddContactSheet(BuildContext context, {DueContact? existingContact}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: cs.surface,
    // Keep the sheet compact so it never grows under the status bar — content
    // scrolls internally within this cap instead of filling the screen.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
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

  // Device-contact enrichment (nullable; only set via "Import from phone").
  String? _phone; // primary, stored normalized (last-10-digit key)
  List<ContactPhone> _phones = const []; // every imported number (primary + extras)
  String? _photoPath; // app-local cached photo file
  String? _deviceContactId;

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
    _phone = c?.phone;
    _photoPath = c?.photoPath;
    _deviceContactId = c?.deviceContactId;
    // On edit, load the full number set (decodes the `phones` JSON, falls back
    // to the legacy `phone` column) so the chooser at call time keeps working.
    if (c != null) {
      _phones = ref.read(duesRepositoryProvider).getContactPhones(c);
    }
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

    // Dedup guard: if any number was imported, check whether another contact
    // already holds it (as its primary or in its `phones` list). The
    // messy-contact safeguard — offer to open the existing one instead of
    // silently creating a duplicate. Check every imported number, not just the
    // primary, so a match on a secondary number is caught too.
    if (_phones.isNotEmpty) {
      DueContact? existing;
      for (final p in _phones) {
        existing = await repo.findContactByPhone(
          p.number,
          excludeId: widget.existingContact?.id,
        );
        if (existing != null) break;
      }
      if (existing != null && mounted) {
        final openExisting = await _confirmOpenExisting(existing.name);
        if (openExisting != true) return;
        if (!mounted) return;
        // Pop this sheet, then navigate to the existing contact's detail.
        Navigator.of(context).pop();
        context.push('/dues/${existing.id}');
        return;
      }
    }

    if (widget.existingContact != null) {
      // On edit, rename a temp photo file to the contact id for a stable path.
      final photoPath = await _finalizePhotoPath(widget.existingContact!.id);
      await repo.updateContact(
        widget.existingContact!,
        name: name,
        icon: _icon,
        color: _color,
        type: _type,
        defaultAmount: amt,
        defaultNote: note.isEmpty ? null : note,
        defaultCategoryId: _defaultCategoryId,
        phone: _phone,
        photoPath: photoPath,
        deviceContactId: _deviceContactId,
        phones: _phones,
      );
    } else {
      final id = await repo.createContact(
        name: name,
        icon: _icon,
        color: _color,
        type: _type,
        defaultAmount: amt,
        defaultNote: note.isEmpty ? null : note,
        defaultCategoryId: _defaultCategoryId,
        phone: _phone,
        photoPath: _photoPath,
        deviceContactId: _deviceContactId,
        phones: _phones,
      );
      // Rename the temp photo file to the new contact's id and persist the
      // stable path. setContactPhotoPath avoids re-passing every field.
      if (_photoPath != null) {
        final finalized = await _renamePhotoTo(_photoPath!, id);
        if (finalized != null) {
          await repo.setContactPhotoPath(id, finalized);
        }
      }
    }

    if (mounted) {
      showFeedbackSnackBar(
          context, widget.existingContact != null ? 'Contact updated' : 'Contact added');
      Navigator.pop(context);
    }
  }

  /// On edit, ensure the cached photo lives at a stable, id-based path so
  /// future edits don't orphan temp files. Returns the path to persist.
  Future<String?> _finalizePhotoPath(String contactId) async {
    final current = _photoPath;
    if (current == null) return null;
    final basename = p.basename(current);
    if (basename.startsWith(contactId)) return current; // already stable
    return _renamePhotoTo(current, contactId);
  }

  Future<String?> _renamePhotoTo(String oldPath, String contactId) async {
    try {
      final dir = await _photoDir();
      final newPath = p.join(dir.path, '$contactId.jpg');
      if (oldPath == newPath) return newPath;
      await File(oldPath).rename(newPath);
      setState(() => _photoPath = newPath);
      return newPath;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _photoDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'contact_photos'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Returns true = open existing, false = stay and create anyway, null = cancel.
  Future<bool?> _confirmOpenExisting(String existingName) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Contact already exists'),
          content: Text(
            'A contact named "$existingName" already uses this phone number. '
            'Open it instead of creating a duplicate?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open existing'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _importFromPhone() async {
    // Gate on the user-intent toggle (Settings → Contact Access). The OS
    // permission is still requested at pick time; this just keeps the
    // affordance off until the user opts in.
    if (!ref.read(contactAccessProvider)) {
      showFeedbackSnackBar(
          context, 'Enable Contact Access in Settings first');
      return;
    }

    // Request contacts access via flutter_contacts' own native API. This drives
    // CNContactStore on iOS directly (needs only NSContactsUsageDescription) and
    // READ_CONTACTS on Android — no permission_handler compile-flag required,
    // which was failing to prompt on iOS. request() shows the system dialog only
    // if not already granted/limited.
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    final granted = status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
    if (!granted) {
      if (status == PermissionStatus.permanentlyDenied ||
          status == PermissionStatus.restricted) {
        if (!mounted) return;
        showFeedbackSnackBar(context, 'Contact permission needed — opening settings');
        await FlutterContacts.permissions.openSettings();
      } else {
        if (!mounted) return;
        showFeedbackSnackBar(context, 'Contact permission denied', error: true);
      }
      return;
    }

    final Contact? picked = await FlutterContacts.native.showPicker(
      properties: const {ContactProperty.phone, ContactProperty.photoThumbnail},
    );
    if (picked == null) return; // user cancelled the picker

    final name = picked.displayName?.trim() ?? '';
    if (name.isNotEmpty && _nameCtrl.text.trim().isEmpty) {
      // Only fill an empty name — never clobber an edit in progress.
      _nameCtrl.text = name;
    }

    // A device contact can have several numbers (mobile / home / work). Keep
    // ALL of them — normalized, de-duplicated by key, with their labels — so the
    // user can pick which to call/WhatsApp at action time rather than committing
    // to one at import. The primary (`phone` column) is the first number, but
    // mobiles are preferred over landlines so the default dial target is sane.
    final all = <ContactPhone>[];
    final seen = <String>{};
    // Put mobiles first so the primary is a mobile when available.
    final ordered = [...picked.phones]..sort((a, b) {
        final am = a.label.label == PhoneLabel.mobile ? 0 : 1;
        final bm = b.label.label == PhoneLabel.mobile ? 0 : 1;
        return am.compareTo(bm);
      });
    for (final ph in ordered) {
      final key = normalizePhone(ph.number);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      all.add(ContactPhone(number: key, label: _phoneLabel(ph.label)));
    }
    final newPhone = all.isEmpty ? null : all.first.number;

    // Cache the thumbnail to the app docs dir under a temp name (renamed to
    // the contact id once saved). Falls back gracefully if there's no photo.
    String? newPhotoPath = _photoPath;
    final thumb = picked.photo?.thumbnail;
    if (thumb != null && thumb.isNotEmpty) {
      try {
        final dir = await _photoDir();
        final tmpPath = p.join(dir.path, 'tmp_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await File(tmpPath).writeAsBytes(thumb);
        newPhotoPath = tmpPath;
      } catch (_) {
        // No photo is fine — keep the emoji fallback.
      }
    }

    setState(() {
      _phone = newPhone;
      _phones = all;
      _photoPath = newPhotoPath;
      _deviceContactId = picked.id;
    });
  }

  /// Human-readable label for a flutter_contacts phone label, stored on the
  /// [ContactPhone] so the call-time chooser can show "Mobile" / "Home" / ….
  String? _phoneLabel(Label<PhoneLabel>? raw) {
    if (raw == null) return null;
    // A custom label string takes precedence over the `custom` enum value.
    final custom = raw.customLabel;
    if (custom != null && custom.isNotEmpty) return custom;
    final name = raw.label.name; // e.g. 'mobile', 'faxWork'
    final lower = name.toLowerCase();
    final known = {
      'mobile': 'Mobile',
      'home': 'Home',
      'work': 'Work',
      'main': 'Main',
      'faxwork': 'Fax (work)',
      'faxhome': 'Fax (home)',
      'pager': 'Pager',
      'other': 'Other',
      'custom': 'Custom',
    };
    return known[lower] ?? name[0].toUpperCase() + name.substring(1);
  }

  void _removeImportedInfo() {
    final oldPhoto = _photoPath;
    setState(() {
      _phone = null;
      _phones = const [];
      _deviceContactId = null;
      _photoPath = null;
    });
    // Best-effort delete of the cached photo file. Temp files from a fresh
    // import are always safe to remove; an existing contact's file is only
    // removed here when the user explicitly clears the enrichment.
    if (oldPhoto != null) {
      try {
        final f = File(oldPhoto);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final botPad = MediaQuery.viewInsetsOf(context).bottom;
    final isUpdate = widget.existingContact != null;

    return Padding(
      padding: EdgeInsets.only(bottom: botPad),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              isUpdate ? 'Edit Contact' : 'New Contact',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 16),

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
            const SizedBox(height: 16),

            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                prefixIcon: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Text(_icon, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Import from device address book (read-only, on-device).
            _ImportButton(onTap: _importFromPhone),
            if (_phone != null || _photoPath != null) ...[
              const SizedBox(height: 12),
              _ImportPreview(
                photoPath: _photoPath,
                emoji: _icon,
                colorHex: _color,
                phone: _phone,
                phoneCount: _phones.length,
                onRemove: _removeImportedInfo,
              ),
            ],
            const SizedBox(height: 12),

            // Icon Picker
            SizedBox(
              height: 44,
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
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: cs.primary, width: 2) : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(icon, style: const TextStyle(fontSize: 22)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Color Picker
            SizedBox(
              height: 36,
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
                      width: 36,
                      height: 36,
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
            const SizedBox(height: 16),

            TextField(
              controller: _amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Default Amount (Optional)',
                prefixText: '₹ ',
                helperText: 'Quick-fill for recurring entries (e.g. tiffin cost)',
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _noteCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Default Note (Optional)',
                helperText: 'Quick-fill for recurring entries (e.g. "Dinner")',
              ),
            ),
            const SizedBox(height: 12),

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
            const SizedBox(height: 20),

            FilledButton(
              onPressed: _nameCtrl.text.trim().isNotEmpty ? _save : null,
              child: Text(isUpdate ? 'Save Changes' : 'Create Contact'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.contact_page_rounded, size: 20, color: cs.primary),
      label: Text(
        'Import from phone',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: cs.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({
    required this.photoPath,
    required this.emoji,
    required this.colorHex,
    required this.phone,
    required this.phoneCount,
    required this.onRemove,
  });

  final String? photoPath;
  final String emoji;
  final String colorHex;
  final String? phone;
  final int phoneCount;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPhone = phone != null && phone!.isNotEmpty;
    final extra = phoneCount > 1 ? phoneCount - 1 : 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          ContactAvatar(
            photoPath: photoPath,
            emoji: emoji,
            colorHex: colorHex,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasPhone ? formatPhone(phone!) : 'Photo imported',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (extra > 0) ...[
                  const SizedBox(height: 1),
                  Text(
                    '+$extra more number${extra == 1 ? '' : 's'}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove contact info',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: cs.onSurfaceVariant,
          ),
        ],
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
