import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/themes/app_colors.dart';
import '../../../app/themes/app_fonts.dart';
import '../../../app/utils/money_format.dart';
import '../../../app/widgets/spendwise_card.dart';
import '../../../state/forecast_providers.dart';
import '../../../state/home_providers.dart';
import '../../../state/period_providers.dart';
import '../../../state/prefs_providers.dart';

/// The Home lead card. Leads with **this month's spend** — the one number a
/// daily-use expense tracker user cares about right now — plus a single
/// aggregate budget-progress bar and a one-line run-rate forecast. Net worth
/// and this-month income/expense are demoted to a compact footer row (net worth
/// keeps its eye toggle). Folds the old standalone budget-pacing + forecast
/// cards into one glanceable card so the Home feed scrolls less.
///
/// On-device only; reads existing providers. Tap → `/transactions` (month spend
/// context).
class HomeSpentHeroCard extends ConsumerWidget {
  const HomeSpentHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;

    final period = ref.watch(selectedPeriodProvider);
    final prev = DateTime(period.year, period.month - 1);
    final summary = ref.watch(homeSummaryProvider((period.year, period.month)));
    final prevSummary = ref.watch(homeSummaryProvider((prev.year, prev.month)));
    final netWorth = ref.watch(globalNetWorthProvider).valueOrNull ?? 0.0;
    final hideNet = ref.watch(hideNetWorthProvider);
    final budget = ref.watch(overallBudgetProgressProvider((period.year, period.month)));
    final forecast = ref.watch(cashflowMonthlyForecastProvider).valueOrNull;

    final monthName = _monthName(period.month);
    final expense = summary.expense;
    final income = summary.income;

    return SpendwiseCard(
      outerPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      innerPadding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + vs-last-month delta chip (left). The net-worth eye toggle
          // lives down beside the net-worth amount, not here.
          Row(
            children: [
              Text(
                'spent in $monthName',
                style: plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              if (prevSummary.expense > 0)
                _DeltaChip(
                  thisExpense: expense,
                  prevExpense: prevSummary.expense,
                  prevLabel: _monthName(prev.month),
                  appColors: appColors,
                ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₹${fmtGrouped(expense)}',
              style: spaceGrotesk(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                letterSpacing: -1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (budget.hasBudgets || forecast != null) ...[
            const SizedBox(height: 14),
            if (budget.hasBudgets) _BudgetBar(budget: budget, cs: cs, appColors: appColors),
            if (forecast != null && forecast.expenseSoFar > 0)
              Padding(
                padding: EdgeInsets.only(top: budget.hasBudgets ? 8 : 0),
                child: Text(
                  'on pace for ~${fmtMoney(forecast.projectedExpense)} by month end',
                  style: plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 0.5, color: cs.outline),
          const SizedBox(height: 12),
          // Footer: this-month income/expense (left) + net worth (right).
          Row(
            children: [
              if (income > 0 || expense > 0) ...[
                Text(
                  '↑ ${fmtMoney(income)}',
                  style: plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: appColors.income,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '↓ ${fmtMoney(expense)}',
                  style: plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: appColors.expense,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ] else
                Text(
                  'No activity yet',
                  style: plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'net worth',
                    style: plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hideNet ? '••••••' : fmtFullMoney(netWorth),
                        style: spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          letterSpacing: -0.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => ref
                            .read(hideNetWorthProvider.notifier)
                            .set(!hideNet),
                        child: Icon(
                          hideNet
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 15,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 60.ms, duration: 300.ms).slideY(begin: 0.04, end: 0, duration: 300.ms);
  }

  static String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];
}

/// Compact "↑12% vs Jun" / "↓8% vs Jun" chip — green when spend dropped, red when
/// it rose. Hidden when the change is negligible (<1%) or last month was 0.
class _DeltaChip extends StatelessWidget {
  const _DeltaChip({
    required this.thisExpense,
    required this.prevExpense,
    required this.prevLabel,
    required this.appColors,
  });

  final double thisExpense;
  final double prevExpense;
  final String prevLabel;
  final AppColors appColors;

  @override
  Widget build(BuildContext context) {
    final diff = thisExpense - prevExpense;
    final pct = (diff.abs() / prevExpense) * 100;
    if (pct < 1) return const SizedBox.shrink();
    final rose = diff > 0;
    final color = rose ? appColors.expense : appColors.income;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${rose ? '↑' : '↓'} ${pct.toStringAsFixed(0)}% vs $prevLabel',
        style: plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// The hero's single aggregate budget bar — spent vs total monthly budget.
/// Over-budget renders the fill in the semantic expense red.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.budget, required this.cs, required this.appColors});

  final ({double spent, double budget, double fraction, bool hasBudgets, bool isOver})
      budget;
  final ColorScheme cs;
  final AppColors appColors;

  @override
  Widget build(BuildContext context) {
    final pct = (budget.fraction * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(color: cs.surfaceContainerHigh),
                FractionallySizedBox(
                  widthFactor: budget.fraction,
                  child: Container(
                    color: budget.isOver ? appColors.expense : cs.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              budget.isOver
                  ? '${fmtMoney(budget.spent)} of ${fmtMoney(budget.budget)} · over'
                  : '$pct% of ${fmtMoney(budget.budget)} budget',
              style: plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: budget.isOver ? appColors.expense : cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}