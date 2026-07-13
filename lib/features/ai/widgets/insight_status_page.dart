import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/local_insight_engine.dart';

/// A single full-bleed page inside the WhatsApp-status-style insight viewer
/// ([InsightViewerScreen]).
///
/// Shows the [AiInsight]'s emoji, title, and the **full** body in a scrollable
/// view — no `maxLines`, no ellipsis. The truncation that cut off long coaching
/// on the old 152pt carousel is gone: if the body is long, it scrolls vertically
/// inside the page. The background is tinted by severity, reusing the same tone
/// mapping the retired `AiInsightCard` used, so the fullscreen pages feel like
/// the same surface as the old carousel cards.
///
/// Pure widget — takes an [AiInsight] and paints. Navigation (tap-zones,
/// swipe, auto-advance) is handled by the viewer, not here.
class InsightStatusPage extends StatelessWidget {
  const InsightStatusPage({super.key, required this.insight});

  final AiInsight insight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (iconColor, bgAlpha, _) = _tone(insight.severity, cs);
    // The viewer wraps the page stack in `SafeArea(bottom: false)`, so respect
    // the bottom inset here to keep long scrollable bodies clear of the gesture
    // bar / home indicator.
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return ColoredBox(
      color: iconColor.withValues(alpha: bgAlpha),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(28, 12, 28, 32 + bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  insight.emoji ?? '✨',
                  style: const TextStyle(fontSize: 44),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              insight.title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.25,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              insight.body,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                height: 1.6,
                color: cs.onSurface.withValues(alpha: 0.88),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Severity → (icon color, background alpha, border alpha). Matches the
  /// retired `AiInsightCard._tone` exactly so the fullscreen pages stay
  /// color-consistent with the compact entry card and the old carousel.
  /// Severity colors are hardcoded hex (matching the report screens'
  /// convention) because this app repurposes `ColorScheme.error` to a
  /// monochrome token, so the theme token can't carry the warning red.
  (Color, double, double) _tone(InsightSeverity s, ColorScheme cs) {
    return switch (s) {
      InsightSeverity.warning => (const Color(0xFFEF4444), 0.07, 0.18),
      InsightSeverity.positive => (const Color(0xFF16A34A), 0.07, 0.18),
      InsightSeverity.info => (cs.primary, 0.10, 0.18),
    };
  }
}