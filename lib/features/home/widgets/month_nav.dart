import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state/home_providers.dart';
import '../../../state/period_providers.dart';

/// ‹ Jun 2026 › arrow + tap-to-pick month navigator.
/// Reads/writes [selectedPeriodProvider].
class MonthNav extends ConsumerWidget {
  const MonthNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(selectedPeriodProvider);
    final earliestAsync = ref.watch(earliestTransactionDateProvider);
    final earliest = earliestAsync.valueOrNull;
    final now = DateTime.now();

    final current = DateTime(period.year, period.month);
    final nowMonth = DateTime(now.year, now.month);
    final canGoForward = current.isBefore(nowMonth);

    final earliestMonth =
        earliest != null ? DateTime(earliest.year, earliest.month) : null;
    final canGoBack =
        earliestMonth == null || current.isAfter(earliestMonth);

    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Arrow(
          icon: Icons.chevron_left_rounded,
          enabled: canGoBack,
          onTap: () {
            final prev = DateTime(period.year, period.month - 1);
            ref.read(selectedPeriodProvider.notifier).state =
                (year: prev.year, month: prev.month);
          },
        ),
        GestureDetector(
          onTap: () => _showSheet(context, ref, period),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(
              _label(period.month, period.year),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
        _Arrow(
          icon: Icons.chevron_right_rounded,
          enabled: canGoForward,
          onTap: () {
            final next = DateTime(period.year, period.month + 1);
            ref.read(selectedPeriodProvider.notifier).state =
                (year: next.year, month: next.month);
          },
        ),
      ],
    );
  }

  static String _label(int month, int year) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    if (year == now.year && month == now.month) return 'This month';
    return '${names[month - 1]} $year';
  }

  void _showSheet(
    BuildContext context,
    WidgetRef ref,
    ({int year, int month}) current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MonthPickerSheet(
        current: current,
        onSelect: (y, m) =>
            ref.read(selectedPeriodProvider.notifier).state =
                (year: y, month: m),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? cs.onSurface
              : cs.onSurface.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}

// ── Month picker sheet ─────────────────────────────────────────────────────────

class _MonthPickerSheet extends StatefulWidget {
  const _MonthPickerSheet({required this.current, required this.onSelect});
  final ({int year, int month}) current;
  final void Function(int year, int month) onSelect;

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.current.year;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Year stepper
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left_rounded, color: cs.onSurface),
                  onPressed: () => setState(() => _year--),
                ),
                Text(
                  '$_year',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: _year < now.year
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.22),
                  ),
                  onPressed: _year < now.year
                      ? () => setState(() => _year++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 3×4 month grid
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.8,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: List.generate(12, (i) {
                final m = i + 1;
                final isFuture = _year > now.year ||
                    (_year == now.year && m > now.month);
                final isSelected = _year == widget.current.year &&
                    m == widget.current.month;

                return GestureDetector(
                  onTap: isFuture
                      ? null
                      : () {
                          widget.onSelect(_year, m);
                          Navigator.pop(context);
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cs.primary
                          : isFuture
                              ? Colors.transparent
                              : cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      names[i],
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? cs.onPrimary
                            : isFuture
                                ? cs.onSurface.withValues(alpha: 0.22)
                                : cs.onSurface,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
