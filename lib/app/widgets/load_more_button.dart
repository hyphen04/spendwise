import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A reusable "Load more" affordance shown as the fallback for infinite-scroll
/// lists — and the only control when a list is shorter than the viewport (so
/// scroll-near-bottom never fires). `pageSize` is the increment revealed per
/// tap, matching the page size used by the host screen's paging state.
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({
    super.key,
    required this.showing,
    required this.total,
    required this.pageSize,
    required this.onTap,
  });

  /// How many items are currently visible.
  final int showing;

  /// Total items available.
  final int total;

  /// Page size — the number of items one tap will reveal (capped to remaining).
  final int pageSize;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining = total - showing;
    final loadNext = remaining > pageSize ? pageSize : remaining;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outlineVariant),
          minimumSize: const Size(double.infinity, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        child: Text('Load $loadNext more  ·  $remaining remaining'),
      ),
    );
  }
}