import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../app/themes/app_fonts.dart';

import '../../../app/utils/money_format.dart';
import '../cashflow_forecast.dart';

/// Compact monthly forecast visual: a progress ring showing how far through
/// the month you are, with the projected month-end balance in the centre.
///
/// Used instead of the GitHub day-grid for the monthly mode — a single month's
/// ~30 days don't fill a square grid nicely (either huge cells or a narrow
/// strip), so a ring reads better. Observation tone, no alarm.
///
/// [accent] defaults to the theme seed (`cs.primary`) so the ring follows the
/// user's chosen colour; pass an override only when you need a fixed hue.
class ForecastMonthlyRing extends StatelessWidget {
  const ForecastMonthlyRing({
    super.key,
    required this.forecast,
    this.accent,
    this.size = 156,
  });

  final CashflowForecast forecast;
  final Color? accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = forecast;
    final hasData = f.hasData;
    final negative = f.projectedEnd < 0;
    final endColor = negative ? cs.error : cs.onSurface;
    final ringColor = accent ?? cs.primary;
    final dayFraction = f.daysInPeriod > 0
        ? (f.daysElapsed / f.daysInPeriod).clamp(0.0, 1.0)
        : 0.0;
    final stroke = size * 0.085;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: dayFraction,
              accent: hasData
                  ? ringColor
                  : ringColor.withValues(alpha: 0.45),
              track: cs.outlineVariant,
              stroke: stroke,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: stroke + 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasData ? 'PROJECTED' : 'AWAITING',
                  style: plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 4),
                if (hasData)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${negative ? '−' : ''}${fmtMoney(f.projectedEnd.abs())}',
                      style: spaceGrotesk(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: endColor,
                        letterSpacing: -0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                else
                  Text(
                    'Log spending',
                    style: plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  hasData ? 'at month-end' : 'to see a projection',
                  style: plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.accent,
    required this.track,
    required this.stroke,
  });

  final double progress;
  final Color accent;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track.withValues(alpha: 0.28),
    );

    // Progress arc (starts at top, sweeps clockwise with the month).
    const start = -math.pi / 2;
    final sweep = progress * 2 * math.pi;
    if (sweep > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = accent,
      );
      // End-of-progress dot.
      final endAngle = start + sweep;
      final dotCenter = Offset(
        center.dx + radius * math.cos(endAngle),
        center.dy + radius * math.sin(endAngle),
      );
      canvas.drawCircle(
        dotCenter,
        stroke * 0.72,
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.track != track ||
      old.stroke != stroke;
}