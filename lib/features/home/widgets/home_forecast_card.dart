import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/utils/money_format.dart';
import '../../../features/forecast/cashflow_forecast.dart';
import '../../../features/forecast/widgets/forecast_day_grid.dart';
import '../../../features/forecast/widgets/forecast_monthly_ring.dart';
import '../../../state/forecast_providers.dart';
import '../../reports/reports/cashflow_forecast_report.dart';

const _kForecastAccent = Color(0xFF14B8A6);
const _kAmber = Color(0xFFB45309);

/// Compact "at a glance" forecast on the Home feed: a GitHub-style day grid
/// (month or year, switched by a pill) colored by daily spend, plus a one-line
/// description and the projected period-end balance. Taps open the full
/// Forecast report on the same mode. On-device only; observation tone.
class HomeForecastCard extends ConsumerWidget {
  const HomeForecastCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final mode = ref.watch(forecastModeProvider);
    final forecastAsync = ref.watch(cashflowForecastForModeProvider(mode));
    final expenseAsync = ref.watch(forecastDayExpenseProvider(mode));

    final expenseMap = expenseAsync.valueOrNull ?? const <String, double>{};
    final f = forecastAsync.valueOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const CashflowForecastReport()),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: pill toggle (left) + chevron (right).
                Row(
                  children: [
                    _ModePill(
                      mode: mode,
                      onChanged: (m) => ref
                          .read(forecastModeProvider.notifier).state = m,
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant, size: 20),
                  ],
                ),
                const SizedBox(height: 12),
                // Visual: progress ring for the month, GitHub grid for 6 months.
                Center(
                  child: mode == ForecastMode.monthly
                      ? (f == null
                          ? const SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : ForecastMonthlyRing(forecast: f))
                      : ForecastDayGrid(
                          mode: mode,
                          dayExpense: expenseMap,
                          today: DateTime.now(),
                          accent: _kForecastAccent,
                        ),
                ),
                const SizedBox(height: 12),
                // Description + projected amount.
                forecastAsync.when(
                  loading: () => const SizedBox(
                      height: 20,
                      child: Center(
                          child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2)))),
                  error: (_, __) => SizedBox(
                      height: 20,
                      child: Text('Forecast unavailable',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: cs.onSurfaceVariant))),
                  data: (f) => _Footer(f: f, cs: cs),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.f, required this.cs});
  final CashflowForecast f;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final negative = f.projectedEnd < 0;
    final endColor = negative ? _kAmber : cs.onSurface;
    // Monthly: the ring already carries the balance, so the footer just states
    // where we are in the month. 6-month: pace line + projected balance.
    if (f.mode == ForecastMode.monthly) {
      return Text(
        'Day ${f.daysElapsed} of ${f.daysInPeriod} · '
        '${f.daysLeft} left in ${f.periodLabel}',
        style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            'Last 6 months\' pace → where you\'d be in 6 months',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Projected balance',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.3)),
            const SizedBox(height: 1),
            Text(
              '${negative ? '−' : ''}${fmtMoney(f.projectedEnd.abs())}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: endColor,
                  letterSpacing: -0.3,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      ],
    );
  }
}

/// Small segmented pill: [Monthly | Yearly].
class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode, required this.onChanged});
  final ForecastMode mode;
  final ValueChanged<ForecastMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pillSegment(cs, 'Monthly', mode == ForecastMode.monthly,
              () => onChanged(ForecastMode.monthly)),
          _pillSegment(cs, '6 Months', mode == ForecastMode.sixMonths,
              () => onChanged(ForecastMode.sixMonths)),
        ],
      ),
    );
  }

  Widget _pillSegment(
      ColorScheme cs, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? _kForecastAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : cs.onSurfaceVariant)),
      ),
    );
  }
}