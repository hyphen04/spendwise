import 'package:flutter/material.dart';

/// The shared Home-card chrome: `surfaceContainerLow` fill, 1px `outline` border,
/// 20px radius, elevation 0, optional tap. This is the shape `cardTheme`
/// (`app_theme.dart`) already mandates and that every Home card was duplicating
/// inline (~12 lines each). Use this so the bento stays visually consistent and
/// each card file only describes its *contents*, not its frame.
///
/// `outerPadding` is the section margin around the card (defaults to the Home
/// rhythm: 20px sides, 10px top, 4px bottom). `innerPadding` is the content inset.
/// Pass `onTap` to make the card tappable (renders an `InkWell`); omit it for a
/// static card.
class SpendwiseCard extends StatelessWidget {
  const SpendwiseCard({
    super.key,
    required this.child,
    this.onTap,
    this.outerPadding = const EdgeInsets.fromLTRB(20, 10, 20, 4),
    this.innerPadding = const EdgeInsets.fromLTRB(14, 14, 14, 14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets outerPadding;
  final EdgeInsets innerPadding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: outerPadding,
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.outline),
                ),
                child: Padding(padding: innerPadding, child: child),
              )
            : InkWell(
                onTap: onTap,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Padding(padding: innerPadding, child: child),
                ),
              ),
      ),
    );
  }
}