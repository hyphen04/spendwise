import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/insight_anonymizer.dart';
import 'package:spendwise/features/ai/domain/local_insight_engine.dart';

void main() {
  group('InsightAnonymizer', () {
    final anonymizer = InsightAnonymizer(
      categories: {'Food', 'Home Rent', 'Subscriptions'},
      modes: {'UPI', 'HDFC Card'},
    );

    final insights = [
      const AiInsight(
        title: 'Food spending spiked',
        body: 'You spent 18000 on Food this month — up 80% from your 3-month '
            'average of 10000.',
        severity: InsightSeverity.warning,
        emoji: '🍔',
      ),
      const AiInsight(
        title: 'Likely recurring charge in Subscriptions',
        body: 'We spotted 3 near-equal payments of about 500 (monthly) in '
            'Subscriptions paid via UPI. Worth confirming.',
        severity: InsightSeverity.info,
        emoji: '🔁',
      ),
      const AiInsight(
        title: 'Home Rent is over budget',
        body: 'You\'ve spent 12000 against a 10000 budget — over by 2000.',
        severity: InsightSeverity.warning,
        emoji: '🏠',
      ),
    ];

    test('anonymized text contains NO real category or mode names', () {
      final anon = anonymizer.anonymizeInsights(insights);
      final blob = anon.map((t) => '${t.title} ${t.body}').join(' ');
      expect(blob, isNot(contains('Food')));
      expect(blob, isNot(contains('Home Rent')));
      expect(blob, isNot(contains('Subscriptions')));
      expect(blob, isNot(contains('UPI')));
      expect(blob, isNot(contains('HDFC Card')));
    });

    test('anonymized text uses opaque labels', () {
      final anon = anonymizer.anonymizeInsights(insights);
      // The numbers must survive (they are not PII).
      expect(anon[0].body, contains('18000'));
      // Labels are present.
      final blob = anon.map((t) => '${t.title} ${t.body}').join(' ');
      expect(blob, contains('cat_'));
      expect(blob, contains('mode_'));
    });

    test('restore round-trips the labels back to real names', () {
      final anon = anonymizer.anonymizeInsights(insights);
      // Simulate the LLM rewriting while preserving labels verbatim.
      final llmRewritten = anon
          .map((t) => (title: 'Nudge: ${t.title}', body: '${t.body} Act soon!'))
          .toList();
      final restored = anonymizer.restore(llmRewritten);

      final blob = restored.map((t) => '${t.title} ${t.body}').join(' ');
      expect(blob, contains('Food'));
      expect(blob, contains('Subscriptions'));
      expect(blob, contains('UPI'));
      expect(blob, contains('Home Rent'));
      // The added coaching text survives.
      expect(blob, contains('Nudge:'));
      expect(blob, contains('Act soon!'));
    });

    test('longer names replaced before shorter prefixes (no corruption)', () {
      // 'HDFC Card' must be handled as a whole, not split into 'HDFC' + 'Card'.
      final a = InsightAnonymizer(
        categories: {'HDFC', 'HDFC Card'},
        modes: const {},
      );
      const insight = AiInsight(
          title: 'HDFC Card charge', body: 'HDFC Card and HDFC both appear');
      final anon = a.anonymizeInsights([insight]);
      // No real names remain.
      expect(anon[0].body, isNot(contains('HDFC Card')));
      expect(anon[0].body, isNot(contains('HDFC')));
      // Two distinct labels were used.
      expect(anon[0].body, contains('cat_'));
      final restored = a.restore(anon);
      expect(restored[0].body, contains('HDFC Card'));
      expect(restored[0].body, contains('HDFC'));
    });

    test('restore handles double-digit label ordering (cat_10 before cat_1)',
        () {
      final cats = {for (int i = 0; i < 12; i++) 'Cat$i'};
      final a = InsightAnonymizer(categories: cats, modes: const {});
      // Build a synthetic insight referencing the label that sorts as a prefix.
      // 'Cat1' maps to some label; 'Cat11' to another. After anonymizing we
      // craft a polished string that includes both labels and ensure restore
      // doesn't corrupt the longer one.
      const insight = AiInsight(title: 'Cat1 and Cat11', body: 'both');
      final anon = a.anonymizeInsights([insight]);
      final restored = a.restore(anon);
      expect(restored[0].title, contains('Cat1'));
      expect(restored[0].title, contains('Cat11'));
    });

    test('whole-word matching: "Food" does not match inside "Foodie"', () {
      final a =
          InsightAnonymizer(categories: {'Food'}, modes: const {});
      const insight =
          AiInsight(title: 'Foodie spend', body: 'Food is high but Foodie is unrelated');
      final anon = a.anonymizeInsights([insight]);
      // 'Foodie' must survive untouched; only the standalone 'Food' is labeled.
      expect(anon[0].body, contains('Foodie'));
      expect(anon[0].body, isNot(contains(' Food ')));
    });

    test('empty vocabulary is a no-op pass-through', () {
      final a = InsightAnonymizer(categories: const {}, modes: const {});
      const insight = AiInsight(title: 'Savings rate slipping', body: 'down to 12%');
      final anon = a.anonymizeInsights([insight]);
      expect(anon[0].title, 'Savings rate slipping');
      expect(anon[0].body, 'down to 12%');
      expect(a.restore(anon).first.body, 'down to 12%');
    });
  });
}