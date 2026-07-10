/// Phone-number normalization for the device-contacts enrichment feature.
///
/// Device address books are messy: the same person may be stored as
/// "+91 98765 43210", "09876543210", or "9876543210". To dedup and compare
/// reliably we collapse every form to a canonical key: digits only, with the
/// India country code (91) stripped, keeping the **last 10 digits**. This is
/// the value stored in `due_contacts.phone` and the key used by the import
/// dedup guard (see `DuesRepository.findContactByPhone`).
///
/// Returns the empty string for input with no usable digits, so callers can
/// treat "no phone" uniformly with a simple `isEmpty` check.
library;

import 'dart:convert';

/// Strip a raw phone string down to its canonical comparison key.
///
/// Rules:
///   - Keep digits only (drops spaces, +, -, parens).
///   - If 11-12 digits and starts with `91` (India), drop the leading `91`.
///   - Keep the last 10 digits.
///   - Empty / no-digit input → `''`.
String normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';

  var stripped = digits;
  // Drop a leading India country code so +91… and 091… align with bare 10-digit.
  if (stripped.length > 10 && stripped.startsWith('91')) {
    stripped = stripped.substring(2);
  }
  // Whatever remains, the comparison key is the last 10 digits.
  if (stripped.length > 10) {
    stripped = stripped.substring(stripped.length - 10);
  }
  return stripped;
}

/// Whether two raw phone strings refer to the same number, by canonical key.
bool phonesMatch(String a, String b) {
  final ka = normalizePhone(a);
  if (ka.isEmpty) return false;
  return ka == normalizePhone(b);
}

/// Format a normalized 10-digit India number as `+91 XXXXX XXXXX` for display.
/// Falls back to the raw input if it isn't a 10-digit key.
String formatPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) {
    return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
  }
  return phone;
}

/// A single phone number attached to a Dues contact.
///
/// [number] is the canonical normalized key (see [normalizePhone]); [label] is
/// an optional human-readable label ("Mobile", "Home", …). A contact stores a
/// list of these as a JSON-encoded string in the `due_contacts.phones` column,
/// so we can keep every number from a device contact and let the user pick
/// which to call/WhatsApp at action time rather than committing to one at
/// import. The legacy single-`phone` column is kept as the denormalized primary
/// for display + backward compatibility.
class ContactPhone {
  const ContactPhone({required this.number, this.label});

  final String number;
  final String? label;

  Map<String, dynamic> toJson() => {
        'number': number,
        if (label != null && label!.isNotEmpty) 'label': label,
      };

  static ContactPhone fromJson(Map<String, dynamic> j) => ContactPhone(
        number: j['number'] as String? ?? '',
        label: j['label'] as String?,
      );

  /// Encode a list to the JSON string stored in `phones`.
  static String encode(List<ContactPhone> phones) =>
      jsonEncode(phones.map((e) => e.toJson()).toList());

  /// Decode the JSON string stored in `phones`. Returns an empty list for
  /// null/empty/garbage input (never throws — a corrupted row just yields no
  /// numbers, and the caller falls back to the legacy `phone` column).
  static List<ContactPhone> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .map((e) => e is Map<String, dynamic>
              ? ContactPhone.fromJson(e)
              : ContactPhone.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}