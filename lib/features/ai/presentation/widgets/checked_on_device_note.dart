import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A small "Checked on-device" badge shown above the AI narrative.
///
/// The gatekeeper ([AiGatekeeper]) restores opaque labels to real names and
/// validates the reply on the user's device — the legend never leaves the
/// phone. This note makes that guarantee visible. When [flagged] is true the
/// gatekeeper found something to flag (an invented label, a leaked-looking
/// token, or an out-of-range number); the text is still shown, with this note.
class CheckedOnDeviceNote extends StatelessWidget {
  const CheckedOnDeviceNote({super.key, this.flagged = false});

  final bool flagged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        children: [
          Icon(Icons.shield_outlined,
              size: 14, color: flagged ? cs.tertiary : cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              flagged
                  ? 'Checked on-device — names restored locally; one or more '
                      'items were flagged for review.'
                  : 'Checked on-device — real names restored locally, nothing '
                      'personal was sent to the AI.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: flagged ? cs.tertiary : cs.onSurfaceVariant,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}