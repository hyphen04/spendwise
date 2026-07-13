import 'package:flutter/material.dart';

/// The app's unified bottom sheet.
///
/// Replaces bare `showModalBottomSheet` calls across the project with a
/// consistent chrome: a drag handle centered at the top. Callers pass their
/// content via [builder]; the component owns the drag handle and the safe-area
/// handling so individual sheets no longer hand-roll those. Each sheet is
/// responsible for its own close affordance (a header close button, a Cancel
/// action, or just barrier/drag dismiss) — there is no component-level close
/// button, so it can never end up behind the status bar / notch.
///
/// For a `DraggableScrollableSheet` (which manages its own sizing/drag), pass
/// `showChrome: false` and embed a [SpendWiseSheetChrome] as the first child of
/// the sheet's internal `Column`.
Future<T?> showSpendWiseSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool showChrome = true,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  bool useRootNavigator = false,
  String? barrierLabel,
}) {
  // Read the real status-bar/notch inset straight from the View rather than
  // the inherited MediaQuery — an ancestor SafeArea/Scaffold can already have
  // consumed `MediaQuery.padding` (so it reads 0 by the time the sheet sees
  // it), which left tall sheets sitting behind the iPhone notch / Android
  // punch-hole. The View's own padding is the physical safe area and is never
  // consumed, so this is correct on every device. We use it to cap the sheet's
  // height so its top edge (and therefore the drag handle) stops at the
  // status-bar boundary.
  final view = MediaQueryData.fromView(View.of(context));
  final topInset = view.padding.top;
  final safeMaxHeight = view.size.height - topInset;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor,
    shape: shape,
    // Cap the sheet to the vertical *safe* area so a tall sheet can never grow
    // up under the status bar — its top edge stops at the status-bar boundary.
    // We only ever *reduce* a caller's maxHeight, never grow it, so callers can
    // still pass a tighter cap (e.g. 0.92 * safeHeight for a small top gap).
    constraints: (constraints ?? const BoxConstraints())
        .enforce(BoxConstraints(maxHeight: safeMaxHeight)),
    showDragHandle: false,
    useSafeArea: false,
    useRootNavigator: useRootNavigator,
    barrierLabel: barrierLabel,
    builder: (ctx) {
      final content = builder(ctx);
      if (!showChrome) return content;
      // The height cap above keeps the sheet's top edge (and the drag handle)
      // just below the status bar — no inherited SafeArea(top) (which can read
      // 0 once an ancestor consumed it) and no double inset. The content's
      // SafeArea(bottom) still clears the home indicator. mainAxisSize.min +
      // Flexible keeps short sheets short and lets tall/capped content scroll
      // naturally. Each sheet owns its own close button in its content, well
      // below the status bar.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpendWiseSheetChrome(showHandle: enableDrag),
          Flexible(
            child: SafeArea(
              top: false,
              bottom: true,
              child: content,
            ),
          ),
        ],
      );
    },
  );
}

/// The centered drag handle shown at the top of every [showSpendWiseSheet].
///
/// When [showHandle] is false (e.g. a non-draggable PIN sheet, which has its
/// own in-content close button), the chrome collapses to nothing.
///
/// This widget does NOT apply its own top SafeArea — the height cap in
/// [showSpendWiseSheet] (or a `SafeArea(top: true)` the caller wraps it in for
/// DraggableScrollable sheets) keeps it below the status bar.
class SpendWiseSheetChrome extends StatelessWidget {
  const SpendWiseSheetChrome({super.key, this.showHandle = true});

  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    if (!showHandle) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Center(child: const _DragHandle()),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: cs.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}