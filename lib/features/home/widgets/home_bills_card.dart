import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/themes/app_colors.dart';
import '../../../app/themes/app_fonts.dart';
import '../../../app/utils/money_format.dart';
import '../../../data/db/app_database.dart';
import '../../../state/bills_providers.dart';

/// Home upcoming-bills card — the next few recurring bills (due within 30
/// days), restyled into the Home card system so it no longer clashes with the
/// flat, borderless Home aesthetic (the old `HomeDuesWidget` used a bordered
/// pager). On-device only; the user's own bill names/amounts never reach the AI
/// (the AI sees only anonymized `bill_N` aggregates via `AiPayloadBuilder`).
class HomeBillsCard extends ConsumerWidget {
  const HomeBillsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final billsAsync = ref.watch(upcomingBillsProvider(30));
    final bills = billsAsync.valueOrNull ?? <RecurringItem>[];

    if (bills.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final top = bills.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/bills'),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outline),
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'upcoming bills',
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
                const SizedBox(height: 10),
                for (final b in top) ...[
                  _BillRow(
                    item: b,
                    today: today,
                    cs: cs,
                    appColors: appColors,
                  ),
                  if (b != top.last)
                    Divider(height: 14, thickness: 0.5, color: cs.outlineVariant),
                ],
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 160.ms, duration: 350.ms);
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.item,
    required this.today,
    required this.cs,
    required this.appColors,
  });
  final RecurringItem item;
  final DateTime today;
  final ColorScheme cs;
  final AppColors appColors;

  @override
  Widget build(BuildContext context) {
    final due = DateTime.tryParse(item.nextDueDate);
    final days = due == null
        ? null
        : DateTime(due.year, due.month, due.day).difference(today).inDays;
    final overdue = days != null && days < 0;

    String daysLabel;
    if (days == null) {
      daysLabel = '—';
    } else if (days == 0) {
      daysLabel = 'due today';
    } else if (overdue) {
      daysLabel = '${-days}d overdue';
    } else {
      daysLabel = 'in $days day${days == 1 ? '' : 's'}';
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          daysLabel,
          style: plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: overdue ? appColors.expense : cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          fmtMoney(item.amount),
          style: plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}