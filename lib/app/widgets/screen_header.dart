import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Standardised top header for all main screens.
///
/// Renders the screen [title] in Manrope w800 24pt (lowercase) aligned to the
/// left, with [actions] clustered on the right. Handles safe-area top padding
/// automatically — do NOT wrap in an AppBar or add extra top padding on top.
///
/// Optional [bottom] is rendered below the title row (e.g. a search bar).
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bottom,
  });

  final String title;

  /// Short caption displayed below the title in onSurfaceVariant Inter 13pt.
  final String? subtitle;

  /// Icon buttons — build each with [HeaderIconButton].
  final List<Widget> actions;

  /// Widget rendered below the title row with 14 pt gap (e.g. search bar).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.paddingOf(context).top;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 16, 16, bottom != null ? 0 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      height: 1.0,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              ...actions,
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 14),
            bottom!,
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// Standardised icon button for [ScreenHeader.actions].
///
/// 40×40, surfaceContainer background, rounded 12, onSurface icon.
/// Pass [badge] > 0 to show a small count indicator on the top-right corner.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Widget btn = IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 19),
      style: IconButton.styleFrom(
        backgroundColor: cs.surfaceContainer,
        foregroundColor: cs.onSurface,
        fixedSize: const Size(40, 40),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        padding: EdgeInsets.zero,
      ),
    );

    if (badge <= 0) return Padding(padding: const EdgeInsets.only(left: 8), child: btn);

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          btn,
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                badge.toString(),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimary,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
