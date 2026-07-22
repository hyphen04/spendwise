import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/app_colors.dart';
import '../themes/app_fonts.dart';

/// Show a brief centered celebration overlay — a scale-in check, a fun one-
/// liner, and the amount just logged — on the **root** overlay, auto-removed
/// after 2s. Inserting into the root overlay (not the sheet's) is the key
/// trick: the calling sheet can be popped *while the overlay is still showing*
/// and the celebration keeps playing on the screen beneath (e.g. Home), so the
/// success animation is never cut off by the sheet sliding away.
///
/// Caller pattern: `showSuccessOverlay(context, amount: amt);` then, after a
/// short delay so the overlay has appeared, `Navigator.pop(context)` — the
/// overlay outlives the sheet.
void showSuccessOverlay(
  BuildContext context, {
  required double amount,
  String? message,
}) {
  final msg = message ?? _funMessages[Random().nextInt(_funMessages.length)];
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SuccessOverlay(amount: amount, message: msg),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 2), () {
    if (entry.mounted) entry.remove();
  });
}

const _funMessages = [
  'Cha-ching! 🎉',
  'Money moves! 💸',
  'Got it down! 📝',
  'Books balanced! ⚖️',
  'Ka-ching! 💰',
  'Logged it! ✅',
  'Secure the bag! 💼',
];

class _SuccessOverlay extends StatefulWidget {
  const _SuccessOverlay({required this.amount, required this.message});

  final double amount;
  final String message;

  @override
  State<_SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<_SuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bgOpacity;
  late final Animation<double> _boxScale;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _bgOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );
    _boxScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)),
    );
    _iconScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 1.0, curve: Curves.easeOutBack)),
    );

    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final successColor = appColors.income;

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            children: [
              Positioned.fill(
                child: FadeTransition(
                  opacity: _bgOpacity,
                  child: IgnorePointer(
                    child: Container(color: cs.scrim.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              Center(
                child: FadeTransition(
                  opacity: _bgOpacity,
                  child: ScaleTransition(
                    scale: _boxScale,
                    child: Container(
                      width: 240,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.1),
                            blurRadius: 24,
                            spreadRadius: 2,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScaleTransition(
                            scale: _iconScale,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: successColor.withValues(alpha: 0.12),
                              ),
                              child: Icon(Icons.check_rounded, color: successColor, size: 36),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.message,
                            style: plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${widget.amount.toStringAsFixed(widget.amount.truncateToDouble() == widget.amount ? 0 : 2)} logged',
                            style: plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}