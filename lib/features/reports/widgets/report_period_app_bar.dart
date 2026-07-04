import 'package:flutter/material.dart';

class ReportPeriodAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ReportPeriodAppBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPrevious,
    required this.onNext,
    this.disableNext = false,
    this.showNavigation = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool disableNext;
  final bool showNavigation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showNavigation)
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: onPrevious,
            ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          if (showNavigation)
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: disableNext ? null : onNext,
            ),
        ],
      ),
      centerTitle: true,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
