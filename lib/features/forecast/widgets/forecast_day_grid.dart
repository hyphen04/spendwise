import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../features/forecast/cashflow_forecast.dart' show ForecastMode;

/// A GitHub-style spending heatmap: one small square per day, laid out
/// Mon→Sun down the rows and weeks across the columns, colored by that day's
/// spend (darker teal = more), today ringed, future days drawn as outlined
/// placeholders so the full period is countable. No day numbers — just the
/// squares, like a contribution graph.
///
/// - **Monthly**: the current month (~5–6 week-columns), squares sized to fill
///   the available width.
/// - **6 months**: the rolling 6 calendar months (~26 week-columns, smaller
///   squares, month labels on top).
///
/// No alarm — it's a glance at pacing, not a score.
class ForecastDayGrid extends StatelessWidget {
  const ForecastDayGrid({
    super.key,
    required this.mode,
    required this.dayExpense,
    required this.today,
    this.accent = const Color(0xFF14B8A6),
  });

  final ForecastMode mode;
  final Map<String, double> dayExpense;
  final DateTime today;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final year = today.year;
    final month = today.month;
    final DateTime start;
    final DateTime end; // exclusive
    if (mode == ForecastMode.sixMonths) {
      start = DateTime(year, month - 5, 1);
      end = DateTime(year, month + 1, 1);
    } else {
      start = DateTime(year, month, 1);
      end = DateTime(year, month + 1, 1);
    }
    return _Grid(
      start: start,
      end: end,
      today: today,
      dayExpense: dayExpense,
      accent: accent,
      // 6-month has ~26 columns → small squares fill the width naturally.
      // A single month has only ~6 week-columns, so keep its squares small
      // too (compact GitHub-style grid, not stretched into huge cells).
      cellMax: mode == ForecastMode.sixMonths ? 13.0 : 16.0,
      showMonthLabels: mode == ForecastMode.sixMonths,
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.start,
    required this.end,
    required this.today,
    required this.dayExpense,
    required this.accent,
    required this.cellMax,
    required this.showMonthLabels,
  });

  final DateTime start;
  final DateTime end; // exclusive
  final DateTime today;
  final Map<String, double> dayExpense;
  final Color accent;
  final double cellMax;
  final bool showMonthLabels;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final daysInWindow = end.difference(start).inDays;
    final offset = start.weekday - 1; // Mon = 0
    final cols = (offset + daysInWindow + 6) ~/ 7;

    final todayDay = DateTime(today.year, today.month, today.day);
    final maxExpense =
        dayExpense.values.fold<double>(0, (a, b) => b > a ? b : a);

    // Key cells by their grid position so the painter can also render the
    // out-of-month slots (leading days before the 1st) as a faint base — that
    // keeps the grid a clean filled rectangle.
    final byPos = <int, _DayCell>{};
    for (int i = 0; i < daysInWindow; i++) {
      final date = start.add(Duration(days: i));
      final pos = i + offset;
      byPos[pos] = _DayCell(
        expense: dayExpense[_isoDay(date)] ?? 0,
        isFuture: date.isAfter(todayDay),
        isToday: date.year == todayDay.year &&
            date.month == todayDay.month &&
            date.day == todayDay.day,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelW = 16.0;
        const gap = 2.0;
        final availW = constraints.maxWidth - labelW - (cols - 1) * gap;
        final cell = (availW / cols).clamp(2.5, cellMax);
        final gridW = labelW + cols * cell + (cols - 1) * gap;
        final gridH = 7 * cell + 6 * gap;

        return SizedBox(
          width: gridW,
          height: gridH + (showMonthLabels ? 14.0 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showMonthLabels)
                _MonthLabels(cols: cols, cell: cell, gap: gap, cs: cs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WeekdayLabels(cell: cell, cs: cs),
                  SizedBox(
                    width: cols * cell + (cols - 1) * gap,
                    height: gridH,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _GridPainter(
                        cols: cols,
                        offset: offset,
                        cellsByPos: byPos,
                        cell: cell,
                        gap: gap,
                        accent: accent,
                        maxExpense: maxExpense,
                        faint: cs.outlineVariant,
                        todayRing: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayCell {
  const _DayCell({
    required this.expense,
    required this.isFuture,
    required this.isToday,
  });
  final double expense;
  final bool isFuture;
  final bool isToday;
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.cols,
    required this.offset,
    required this.cellsByPos,
    required this.cell,
    required this.gap,
    required this.accent,
    required this.maxExpense,
    required this.faint,
    required this.todayRing,
  });

  final int cols;
  final int offset; // leading out-of-month slots in column 0
  final Map<int, _DayCell> cellsByPos;
  final double cell;
  final double gap;
  final Color accent;
  final double maxExpense;
  final Color faint;
  final Color todayRing;

  @override
  void paint(Canvas canvas, Size size) {
    final step = cell + gap;
    final r = Radius.circular(cell * 0.22);
    for (int col = 0; col < cols; col++) {
      for (int row = 0; row < 7; row++) {
        final pos = col * 7 + row;
        final x = col * step;
        final y = row * step;
        final rect = Rect.fromLTWH(x, y, cell, cell);
        final rr = RRect.fromRectAndRadius(rect, r);
        final c = cellsByPos[pos];
        if (c == null) {
          // Out-of-month slot (before the 1st): faint base so the grid reads as
          // a complete rectangle.
          canvas.drawRRect(
            rr,
            Paint()..color = faint.withValues(alpha: 0.10),
          );
          continue;
        }
        if (c.isFuture) {
          // Future day: outlined placeholder — clearly countable in both
          // themes, but hollow so it reads as "upcoming", not "spent".
          canvas.drawRRect(
            rr,
            Paint()..color = accent.withValues(alpha: 0.06),
          );
          canvas.drawRRect(
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.0, cell * 0.09)
              ..color = faint.withValues(alpha: 0.55),
          );
          continue;
        }
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.fill
            ..color = _spendColor(c),
        );
        if (c.isToday) {
          canvas.drawRRect(
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.28
              ..color = todayRing,
          );
        }
      }
    }
  }

  Color _spendColor(_DayCell c) {
    if (c.expense <= 0) return accent.withValues(alpha: 0.10);
    final intensity =
        maxExpense > 0 ? (c.expense / maxExpense).clamp(0.0, 1.0) : 0.0;
    return accent.withValues(alpha: 0.22 + 0.70 * intensity);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.cellsByPos != cellsByPos ||
      old.cell != cell ||
      old.cols != cols ||
      old.maxExpense != maxExpense ||
      old.accent != accent ||
      old.faint != faint;
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels({required this.cell, required this.cs});
  final double cell;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final labels = {0: 'Mon', 2: 'Wed', 4: 'Fri'};
    return SizedBox(
      width: 16,
      child: Column(
        children: [
          for (int r = 0; r < 7; r++)
            SizedBox(
              height: cell,
              child: labels.containsKey(r)
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(labels[r]!,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.7))),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

class _MonthLabels extends StatelessWidget {
  const _MonthLabels({
    required this.cols,
    required this.cell,
    required this.gap,
    required this.cs,
  });
  final int cols;
  final double cell;
  final double gap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final step = cell + gap;
    return SizedBox(
      height: 12,
      child: Stack(
        children: [
          for (int m = 0; m < 6; m++)
            Positioned(
              left: 16.0 + m * step * 4.43,
              top: 0,
              child: Text(names[m % 12],
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
            ),
        ],
      ),
    );
  }
}

String _isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';