import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A fully-rounded monochrome pill used across the app for kind selectors,
/// filters, the month dropdown, and category/merchant chips.
///
/// Selected → solid [ColorScheme.primary] background with [onPrimary] text.
/// Unselected → transparent fill with a hairline [outline] border.
class MonoPill extends StatelessWidget {
  const MonoPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leadingEmoji,
    this.leadingIcon,
    this.trailingIcon,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? leadingEmoji;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimary : cs.onSurface;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 16,
          vertical: dense ? 7 : 10,
        ),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: cs.outline, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingEmoji != null) ...[
              Text(leadingEmoji!, style: TextStyle(fontSize: dense ? 13 : 15)),
              const SizedBox(width: 6),
            ] else if (leadingIcon != null) ...[
              Icon(leadingIcon, size: dense ? 15 : 17, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: dense ? 13 : 14,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 4),
              Icon(trailingIcon, size: dense ? 15 : 17, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}
