import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/themes/app_fonts.dart';
import '../../../app/utils/money_format.dart';
import '../../../app/widgets/spendwise_card.dart';
import '../../../data/db/app_database.dart';
import '../../../state/home_providers.dart';
import '../../../state/period_providers.dart';
import '../../../utils/color_utils.dart';
import '../../reports/reports/category_drilldown_report.dart';

/// Home "where it went" card — replaces the unreadable 6-month cashflow line
/// chart with a glanceable breakdown of the top 3–4 expense categories this
/// month (horizontal bars + amounts). Answers "what am I spending on?" without
/// requiring chart-reading skill. Plain Flutter bars (no chart lib). Tap →
/// the Categories drilldown report for the selected period (same screen the
/// Reports hub opens). Hidden when the month has no expenses.
///
/// On-device only; reads [monthTopCategoriesProvider].
class HomeWhereItWentCard extends ConsumerWidget {
  const HomeWhereItWentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final period = ref.watch(selectedPeriodProvider);
    final top = ref.watch(monthTopCategoriesProvider((period.year, period.month)));

    if (top.isEmpty) return const SizedBox.shrink();

    final maxAmount = top.first.amount;

    return SpendwiseCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryDrilldownReport(
            year: period.year,
            month: period.month,
          ),
        ),
      ),
      outerPadding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      innerPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'where it went · ${_monthName(period.month)}',
                style: plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: cs.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 12),
          for (final e in top) ...[
            _CatBar(
              cat: e.cat,
              amount: e.amount,
              widthFactor: maxAmount > 0 ? (e.amount / maxAmount).clamp(0.0, 1.0) : 0.0,
              cs: cs,
            ),
            if (e != top.last) const SizedBox(height: 12),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 140.ms, duration: 350.ms);
  }

  static String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];
}

class _CatBar extends StatelessWidget {
  const _CatBar({
    required this.cat,
    required this.amount,
    required this.widthFactor,
    required this.cs,
  });

  final Category cat;
  final double amount;
  final double widthFactor;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final color = hexToColor(cat.color, fallback: cs.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(cat.icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                cat.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            Text(
              fmtMoney(amount),
              style: plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(color: cs.surfaceContainerHigh),
                FractionallySizedBox(
                  widthFactor: widthFactor,
                  child: Container(color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}