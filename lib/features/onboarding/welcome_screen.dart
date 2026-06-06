import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

/// Full-screen welcome page shown before the onboarding slides.
/// Matches the "mibu" reference: big lowercase wordmark, tagline, and floating
/// category pills positioned around the centre. No illustration asset required.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          // ── Floating category pills ────────────────────────────────────────
          // Positions are proportional to screen size, mimicking the reference.
          ..._pills(size, cs),

          // ── Centre content: wordmark + tagline + CTA ─────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'spendwise',
                  style: GoogleFonts.manrope(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    letterSpacing: -1.5,
                    height: 1.0,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.1, end: 0, duration: 500.ms),
                const SizedBox(height: 10),
                Text(
                  'your minimal money tracker',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurfaceVariant,
                  ),
                )
                    .animate(delay: 120.ms)
                    .fadeIn(duration: 400.ms),
              ],
            ),
          ),

          // ── Bottom CTA ────────────────────────────────────────────────────
          Positioned(
            left: 32,
            right: 32,
            bottom: MediaQuery.paddingOf(context).bottom + 40,
            child: FilledButton(
              onPressed: onGetStarted,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: const StadiumBorder(),
              ),
              child: Text(
                'Get started',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
                .animate(delay: 300.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.2, end: 0),
          ),
        ],
      ),
    );
  }

  static List<Widget> _pills(Size size, ColorScheme cs) {
    final items = [
      ('💰', 'balance', 0.14, 0.16),
      ('📈', 'income', 0.06, 0.30),
      ('💸', 'expenses', 0.72, 0.22),
      ('🎉', 'fun', 0.05, 0.55),
      ('🍕', 'food', 0.68, 0.60),
      ('✈️', 'travel', 0.70, 0.40),
      ('🏡', 'retire', 0.08, 0.70),
    ];

    return items.asMap().entries.map((entry) {
      final i = entry.key;
      final (emoji, label, xFrac, yFrac) = entry.value;
      return Positioned(
        left: size.width * xFrac,
        top: size.height * yFrac,
        child: _FloatingPill(emoji: emoji, label: label, cs: cs)
            .animate(delay: Duration(milliseconds: 80 + i * 60))
            .fadeIn(duration: 350.ms)
            .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1)),
      );
    }).toList();
  }
}

class _FloatingPill extends StatelessWidget {
  const _FloatingPill({
    required this.emoji,
    required this.label,
    required this.cs,
  });
  final String emoji;
  final String label;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: cs.onSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.surface,
            ),
          ),
        ],
      ),
    );
  }
}
