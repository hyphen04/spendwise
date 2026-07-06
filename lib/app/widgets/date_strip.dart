import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DateStrip extends StatelessWidget {
  const DateStrip({super.key, required this.selected, required this.onSelect});
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      onSelect(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const dayLabels = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

    // Show the last 7 days (oldest to newest)
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final selDay = DateTime(selected.year, selected.month, selected.day);
    
    if (!days.contains(selDay)) {
      days.insert(0, selDay);
    }

    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: days.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return GestureDetector(
              onTap: () => _pickDate(context),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(Icons.calendar_month_rounded, size: 20, color: cs.primary),
              ),
            );
          }

          final day = days[i - 1];
          final active = day == selDay;
          // weekday: 1=Mon … 7=Sun
          final label = '${day.day}\n${dayLabels[day.weekday - 1]}';

          return GestureDetector(
            onTap: () => onSelect(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: active ? null : Border.all(color: cs.outline),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? cs.onPrimary : cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
