import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/utils/phone_utils.dart';
import '../../../app/widgets/spendwise_sheet.dart';

/// Lets the user pick one of a contact's numbers before calling or messaging.
///
/// Shown when a contact has more than one stored number (mobile / home / work).
/// Returns the chosen [ContactPhone], or null if the user dismissed the sheet.
/// The list is assumed already de-duplicated by normalized key (see
/// `DuesRepository.getContactPhones`).
Future<ContactPhone?> showPhoneChooser(
  BuildContext context,
  List<ContactPhone> phones, {
  String title = 'Pick a number',
  String subtitle = 'Which number do you want to use?',
  IconData icon = Icons.call_rounded,
}) {
  final cs = Theme.of(context).colorScheme;
  return showSpendWiseSheet<ContactPhone>(
    context,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: phones.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 0.8,
                  color: cs.outline,
                ),
                itemBuilder: (_, i) {
                  final ph = phones[i];
                  final formatted = formatPhone(ph.number);
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, ph),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(icon, size: 20, color: cs.onSurfaceVariant),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatted,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                                if (ph.label != null && ph.label!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    ph.label!,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 22, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}