import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/report_models.dart';
import 'package:spendwise/features/ai/domain/local_insight_engine.dart';

ExportRow _expense(String date, double amount,
        {String category = 'Food', String mode = 'Card'}) =>
    ExportRow(
        id: 'e-$date-$amount',
        amount: amount,
        date: date,
        kind: 'expense',
        accountName: 'Acc',
        categoryName: category,
        modeName: mode,
        createdAt: 0);

void main() {
  // ── Recurring-payment detection ─────────────────────────────────────────
  //
  // detectRecurring powers the Bills feature's on-device seeding of
  // recurring_items. It groups expenses by (category, mode) and flags repeated
  // near-equal amounts at a consistent interval (≥3 occurrences).

  group('detectRecurring', () {
    test('detects a monthly subscription', () {
      final rows = [
        _expense('2026-02-10T08:00:00.000', 199.0),
        _expense('2026-03-10T08:00:00.000', 199.0),
        _expense('2026-04-10T08:00:00.000', 199.0),
        _expense('2026-05-10T08:00:00.000', 199.0),
      ];
      final detected = LocalInsightEngine.detectRecurring(rows);
      expect(detected.length, 1);
      final d = detected.first;
      expect(d.categoryName, 'Food');
      expect(d.modeName, 'Card');
      expect(d.amount, 199.0);
      expect(d.occurrences, 4);
      expect(d.cadence, 'monthly');
      expect(d.lastDate, '2026-05-10T08:00:00.000');
    });

    test('ignores irregular one-off payments', () {
      final rows = [
        _expense('2026-02-03T08:00:00.000', 199.0),
        _expense('2026-03-19T08:00:00.000', 199.0), // 44-day gap
        _expense('2026-04-02T08:00:00.000', 199.0), // 14-day gap — too irregular
        _expense('2026-05-21T08:00:00.000', 199.0),
      ];
      expect(LocalInsightEngine.detectRecurring(rows), isEmpty);
    });

    test('ignores varying amounts', () {
      final rows = [
        _expense('2026-02-10T08:00:00.000', 199.0),
        _expense('2026-03-10T08:00:00.000', 4000.0), // wildly different
        _expense('2026-04-10T08:00:00.000', 199.0),
        _expense('2026-05-10T08:00:00.000', 199.0),
      ];
      expect(LocalInsightEngine.detectRecurring(rows), isEmpty);
    });

    test('requires at least 3 occurrences', () {
      final rows = [
        _expense('2026-03-10T08:00:00.000', 199.0),
        _expense('2026-04-10T08:00:00.000', 199.0),
      ];
      expect(LocalInsightEngine.detectRecurring(rows), isEmpty);
    });
  });
}