import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/utils/money_format.dart';
import '../../../features/forecast/cashflow_forecast.dart';
import '../../../features/forecast/run_rate.dart';
import '../../../features/forecast/widgets/forecast_day_grid.dart';
import '../../../features/forecast/widgets/forecast_monthly_ring.dart';
import '../../../state/forecast_providers.dart';
import '../../../state/manage_providers.dart';
import '../widgets/insight_card.dart';

const _kForecastAccent = Color(0xFF14B8A6);
const _kAmber = Color(0xFFB45309);

/// Month / year run-rate projection. A GitHub-style day grid shows pacing,
/// the hero number is the projected period-end balance, and (monthly only) a
/// per-category run-rate section compares this month to the usual pace.
/// Observation tone, no alarm. On-device only — no AI, no network.
class CashflowForecastReport extends ConsumerWidget {
  const CashflowForecastReport({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final mode = ref.watch(forecastModeProvider);
    final forecastAsync = ref.watch(cashflowForecastForModeProvider(mode));
    final expenseAsync = ref.watch(forecastDayExpenseProvider(mode));
    final runRateAsync = ref.watch(runRateObservationsProvider);
    final cats =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    final expenseMap = expenseAsync.valueOrNull ?? const <String, double>{};

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                '${mode == ForecastMode.sixMonths ? '6-Month' : 'Month'} '
                'Forecast',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            Text('Run-rate projection · on-device',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // Mode toggle.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _ModePill(
                  mode: mode,
                  onChanged: (m) =>
                      ref.read(forecastModeProvider.notifier).state = m,
                ),
                const Spacer(),
                Text(
                  mode == ForecastMode.sixMonths
                      ? 'Daily spend · last 6 months'
                      : 'Daily spend this month',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Day grid card — 6-month mode only. (Monthly uses a progress ring
          // inside the forecast card below instead, since one month doesn't
          // fill a GitHub grid nicely.)
          if (mode == ForecastMode.sixMonths) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ForecastDayGrid(
                      mode: mode,
                      dayExpense: expenseMap,
                      today: DateTime.now(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Legend(accent: _kForecastAccent, cs: cs),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          forecastAsync.when(
            loading: () => const Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(),
            )),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Could not compute forecast: $e'),
            ),
            data: (f) => _ForecastCard(forecast: f),
          ),
          if (mode == ForecastMode.monthly) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _kForecastAccent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Text('RUN-RATE BY CATEGORY',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 12),
            runRateAsync.when(
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
              error: (e, _) => Text('Could not compute run-rate: $e',
                  style: TextStyle(color: cs.error)),
              data: (obs) {
                if (obs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Not enough history yet. After a couple of months of '
                      'spending, your usual pace by this point in the month '
                      'will show here.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final o in obs)
                      _RunRateTile(
                        observation: o,
                        icon: cats
                                .where((c) => c.name == o.categoryName)
                                .firstOrNull
                                ?.icon ??
                            '📦',
                      ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          InsightCard(text: _explainer(mode)),
        ],
      ),
    );
  }

  static String _explainer(ForecastMode mode) => mode == ForecastMode.sixMonths
      ? 'This is an estimate, not a target. It takes your average monthly net '
          '(income minus spending) over the last 6 completed months and '
          'projects it forward 6 months from today\'s balance. Big one-off '
          'events (a bonus, a festival splurge) can skew it — it\'s a heads-up, '
          'never a judgment.'
      : 'This is an estimate, not a target. It assumes your spending keeps '
          'today\'s pace for the rest of the month and only counts income '
          'you\'ve already logged — upcoming salary isn\'t included until you '
          'enter it. It\'s a heads-up, never a judgment.';
}

class _Legend extends StatelessWidget {
  const _Legend({required this.accent, required this.cs});
  final Color accent;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Less',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
        const SizedBox(width: 6),
        for (final a in const [0.10, 0.30, 0.55, 0.80, 0.95])
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: a),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        const SizedBox(width: 6),
        Text('More',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
        const Spacer(),
        Text('Today is ringed',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
      ],
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.forecast});
  final CashflowForecast forecast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = forecast;
    if (!f.hasData) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          f.mode == ForecastMode.sixMonths
              ? 'Not enough history yet. After a few months of spending, '
                  'your 6-month pace and projection will appear here.'
              : 'No spending recorded this month yet. Once you log a '
                  'transaction, your run-rate projection will appear here.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, color: cs.onSurfaceVariant),
        ),
      );
    }
    final negative = f.projectedEnd < 0;
    final endColor = negative ? _kAmber : cs.onSurface;
    final calm = !negative && !f.outlook.contains('tight') &&
        !f.outlook.contains('Worth') && !f.outlook.contains('dip');
    final pillBg = (calm ? _kForecastAccent : _kAmber).withValues(alpha: 0.16);
    final pillFg = calm ? _kForecastAccent : _kAmber;
    final monthly = f.mode == ForecastMode.monthly;
    final outlookPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(f.outlook,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, fontWeight: FontWeight.w700, color: pillFg)),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (monthly)
            // The ring is the focal point: it carries the projected balance
            // (centre) and day-of-month progress (arc). The right side holds
            // the label + outlook pill.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ForecastMonthlyRing(forecast: f, size: 122),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Projected balance\nat month-end',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant)),
                      const SizedBox(height: 10),
                      outlookPill,
                    ],
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _kForecastAccent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('🔮', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Projected balance in 6 months',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant),
                  ),
                ),
                outlookPill,
              ],
            ),
          const SizedBox(height: 12),
          if (!monthly) ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${negative ? '−' : ''}${fmtMoney(f.projectedEnd.abs())}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: endColor,
                  letterSpacing: -1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            monthly
                ? '≈ what you\'d have left across all accounts by month-end, '
                    'if spending keeps today\'s pace and no more income is '
                    'logged.'
                : '≈ where you\'d be in 6 months if your last 6 months\' '
                    'income and spending pace continues.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (monthly)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Day ${f.daysElapsed} of ${f.daysInPeriod} · '
                      '${f.daysLeft} left in ${f.periodLabel}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  'Opening + income so far − projected spend',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Based on your last 6 completed months',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  'Now + 6 × avg monthly net',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ],
            ),
          const SizedBox(height: 18),
          // IntrinsicHeight + stretch keeps all three tiles the same height
          // regardless of label/value length, with values bottom-aligned.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: _StatTile(
                  label: f.mode == ForecastMode.sixMonths
                      ? 'Balance now'
                      : 'Opening balance',
                  value: fmtMoney(f.openingBalance),
                  accent: cs.onSurfaceVariant,
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _StatTile(
                  label: f.mode == ForecastMode.sixMonths
                      ? 'Projected income'
                      : 'Income so far',
                  value: fmtMoney(f.mode == ForecastMode.sixMonths
                      ? f.projectedIncome
                      : f.incomeSoFar),
                  accent: _kForecastAccent,
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _StatTile(
                        label: 'Projected spend',
                        value: fmtMoney(f.projectedExpense),
                        accent: cs.error)),
              ],
            ),
          ),
          if (f.billsDueBeforePeriodEnd.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              f.mode == ForecastMode.sixMonths
                  ? 'Known bills due in the next 6 months'
                  : 'Known bills due before month-end',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: f.billsDueBeforePeriodEnd.take(8).map((b) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _kAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: _kAmber.withValues(alpha: 0.3)),
                  ),
                  child: Text(b,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kAmber)),
                );
              }).toList(),
            ),
            if (f.billsDueBeforePeriodEnd.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+${f.billsDueBeforePeriodEnd.length - 8} more',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label, required this.value, required this.accent});
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Spacer fills any extra height from the IntrinsicHeight row so every
        // tile matches the tallest one and the values bottom-align.
        children: [
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.3,
                  height: 1.25)),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

class _RunRateTile extends StatelessWidget {
  const _RunRateTile({required this.observation, required this.icon});
  final RunRateObservation observation;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final o = observation;
    final ratio = o.typical > 0 ? (o.actual / o.typical) : 0.0;
    final over = ratio > 1.0;
    final barFill = ratio.clamp(0.0, 1.3);
    final barColor = over ? _kAmber : _kForecastAccent;
    final labelColor = over ? _kAmber : cs.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.surface,
              shape: BoxShape.circle,
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(o.categoryName,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(o.label,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: labelColor)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (barFill / 1.3).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: barColor.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(barColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Usually ${fmtMoney(o.typical)} by now · '
                  'now ${fmtMoney(o.actual)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small segmented pill: [Monthly | Yearly]. Shared shape with the Home card.
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
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(cs, 'Monthly', mode == ForecastMode.monthly,
              () => onChanged(ForecastMode.monthly)),
          _seg(cs, '6 Months', mode == ForecastMode.sixMonths,
              () => onChanged(ForecastMode.sixMonths)),
        ],
      ),
    );
  }

  Widget _seg(ColorScheme cs, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _kForecastAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : cs.onSurfaceVariant)),
      ),
    );
  }
}