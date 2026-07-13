import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/ai_gatekeeper.dart';

void main() {
  group('AiGatekeeper.restore', () {
    final gatekeeper = AiGatekeeper(
      legend: const {
        'cat_0': 'Food & Dining',
        'cat_1': 'Home Rent',
        'cat_10': 'Subscriptions',
        'mode_0': 'UPI',
        'mode_1': 'HDFC Card',
      },
      validLabels: const {
        'cat_0', 'cat_1', 'cat_10', 'mode_0', 'mode_1',
      },
    );

    test('replaces labels with real names', () {
      final out = gatekeeper.restore('cat_0 spending spiked, paid via mode_0.');
      expect(out, 'Food & Dining spending spiked, paid via UPI.');
    });

    test('handles double-digit labels before single-digit prefixes', () {
      // cat_10 must be restored as a whole before cat_1 is considered, so a
      // token like cat_10 isn't corrupted into "<cat_1>0".
      final out = gatekeeper.restore('cat_10 and cat_1 both rose.');
      expect(out, 'Subscriptions and Home Rent both rose.');
      expect(out, isNot(contains('cat_')));
    });

    test('word-boundary: cat_0 is not matched inside cat_01', () {
      // cat_01 is not a valid label; restore must leave it alone rather than
      // turning it into "Food & Dining1".
      final out = gatekeeper.restore('cat_01 is unknown here.');
      expect(out, 'cat_01 is unknown here.');
    });

    test('is a no-op on partial streamed text', () {
      // A half-arrived "cat_" (not a legend key) must not match.
      expect(gatekeeper.restore('You spent cat_'), 'You spent cat_');
    });

    test('is identity when the legend is empty (shareNames=true path)', () {
      final g = AiGatekeeper(legend: const {}, validLabels: const {});
      expect(g.restore('Food & Dining spending spiked.'), isNotEmpty);
      expect(g.restore('cat_0'), 'cat_0'); // nothing to restore
    });
  });

  group('AiGatekeeper.check', () {
    AiGatekeeper g({Map<String, String> legend = const {},
      Set<String> validLabels = const {},
      double? maxContextAmount}) =>
        AiGatekeeper(
            legend: legend, validLabels: validLabels, maxContextAmount: maxContextAmount);

    test('bad: empty text', () {
      expect(g().check('').severity, AiCheckSeverity.bad);
    });

    test('bad: only whitespace + markdown markers', () {
      expect(g().check('  \n# \n- \n--- \n> ').severity, AiCheckSeverity.bad);
    });

    test('bad: empty even with a legend', () {
      expect(
        g(legend: const {'cat_0': 'Food'}).check('   ').severity,
        AiCheckSeverity.bad,
      );
    });

    test('flagged: leftover unknown label not in validLabels', () {
      final res = g(
        legend: const {'cat_0': 'Food'},
        validLabels: const {'cat_0'},
      ).check('You spent a lot on cat_9 this month.');
      expect(res.severity, AiCheckSeverity.flagged);
      expect(res.issues, isNotEmpty);
      expect(res.issues.first, contains('cat_9'));
    });

    test('flagged: valid label missing from legend (could not restore)', () {
      final res = g(
        legend: const {},
        validLabels: const {'cat_0'},
      ).check('cat_0 spending spiked.');
      expect(res.severity, AiCheckSeverity.flagged);
      expect(res.issues.any((i) => i.contains('cat_0')), isTrue);
    });

    test('flagged: phone-ish number', () {
      final res = g().check('Call me at +91 99999 99999 for details.');
      expect(res.severity, AiCheckSeverity.flagged);
      expect(res.issues.any((i) => i.contains('phone')), isTrue);
    });

    test('flagged: email-ish token', () {
      final res = g().check('Reach me at user@example.com please.');
      expect(res.severity, AiCheckSeverity.flagged);
      expect(res.issues.any((i) => i.contains('email')), isTrue);
    });

    test('ok: clean restored text with no problems', () {
      final res = g(
        legend: const {'cat_0': 'Food & Dining'},
        validLabels: const {'cat_0'},
      ).check('You spent most on cat_0 this month.');
      // Restored to "Food & Dining", no leftover labels, no PII, no huge number.
      expect(res.severity, AiCheckSeverity.ok);
      expect(res.issues, isEmpty);
    });

    test('flagged: number far above 10x the context ceiling', () {
      final res = g(maxContextAmount: 85000)
          .check('You somehow spent 9,999,999 on dining.');
      expect(res.severity, AiCheckSeverity.flagged);
      expect(res.issues.any((i) => i.contains('number')), isTrue);
    });

    test('ok: number within range is not flagged', () {
      final res = g(maxContextAmount: 85000)
          .check('You spent 90,000 this month.');
      expect(res.severity, AiCheckSeverity.ok);
    });

    test('ok: a normal short number with no context ceiling is fine', () {
      final res = g().check('You had 3 transactions over 5000.');
      expect(res.severity, AiCheckSeverity.ok);
    });
  });

  group('AiGatekeeper.check — numeric correspondence', () {
    AiGatekeeper g({
      Map<String, String> legend = const {},
      Set<String> validLabels = const {},
      double? maxContextAmount,
      Set<double>? sentAmounts,
    }) =>
        AiGatekeeper(
          legend: legend,
          validLabels: validLabels,
          maxContextAmount: maxContextAmount,
          sentAmounts: sentAmounts,
        );

    test('ok: reply figure matches a sent amount within tolerance', () {
      final res = g(
        maxContextAmount: 85000,
        sentAmounts: {62000, 18000, 85000},
      ).check('You spent 62,000 this month.');
      expect(res.severity, AiCheckSeverity.ok);
      expect(res.issues, isEmpty);
    });

    test('ok: figure slightly off but within 2% tolerance of a sent amount', () {
      final res = g(
        maxContextAmount: 85000,
        sentAmounts: {62000},
      ).check('You spent about 62,500.'); // ~0.8% off
      expect(res.severity, AiCheckSeverity.ok);
    });

    test('ok: derived figure under the sane ceiling (max*1.5) is accepted', () {
      final res = g(
        maxContextAmount: 85000,
        sentAmounts: {62000},
      ).check('Your total outflow including transfers was 110,000.');
      // 110000 not in sentAmounts but <= 85000*1.5 = 127500 → ok.
      expect(res.severity, AiCheckSeverity.ok);
    });

    test('flagged: figure matches nothing sent and exceeds the sane ceiling',
        () {
      final res = g(
        maxContextAmount: 85000,
        sentAmounts: {62000, 18000},
      ).check('You spent 250,000 on dining this month.');
      // 250000 not within tolerance of 62000/18000 and > 127500 → flagged.
      expect(res.severity, AiCheckSeverity.flagged);
      expect(res.issues.any((i) => i.contains('figure')), isTrue);
    });

    test('flagged: hallucinated figure with no matching sent amount', () {
      final res = g(
        maxContextAmount: 50000,
        sentAmounts: {12000, 8000},
      ).check('You spent 95,000 on subscriptions.');
      expect(res.severity, AiCheckSeverity.flagged);
      expect(res.issues.any((i) => i.contains('figure')), isTrue);
    });

    test('ok: correspondence skipped when no amounts and no ceiling', () {
      // Legacy no-op: a number with no sent amounts and no ceiling is left
      // alone (preserves the prior behavior for callers that don't opt in).
      final res = g().check('You spent 5000 on coffee.');
      expect(res.severity, AiCheckSeverity.ok);
    });
  });

  group('AiGatekeeper.check — hallucinated-name detection (shareNames)', () {
    AiGatekeeper g({
      Map<String, String> legend = const {},
      Set<String> validLabels = const {},
      Set<String>? sentNameVocabulary,
    }) =>
        AiGatekeeper(
          legend: legend,
          validLabels: validLabels,
          sentNameVocabulary: sentNameVocabulary,
        );

    test('ok: reply uses only known names', () {
      final res = g(
        legend: const {'cat_0': 'Food & Dining', 'mode_0': 'UPI'},
        validLabels: const {'cat_0', 'mode_0'},
        sentNameVocabulary: {'Food & Dining', 'UPI'},
      ).check('You spent most on Food & Dining, paid via UPI.');
      expect(res.severity, AiCheckSeverity.ok);
    });

    test('flagged: reply mentions an unknown category name', () {
      final res = g(
        legend: const {'cat_0': 'Food & Dining'},
        validLabels: const {'cat_0'},
        sentNameVocabulary: {'Food & Dining'},
      ).check('You spent a lot on Travel this month.');
      // "Travel" is capitalized, not the first word, not a known name.
      expect(res.severity, AiCheckSeverity.flagged);
      expect(res.issues.any((i) => i.contains('unknown name')), isTrue);
    });

    test('ok: section-heading words are not flagged as invented names', () {
      final res = g(
        legend: const {'cat_0': 'Food & Dining'},
        validLabels: const {'cat_0'},
        sentNameVocabulary: {'Food & Dining'},
      ).check('### Overview\nYou spent on Food & Dining.');
      // "Overview" is a heading (line starts with #) → skipped.
      expect(res.severity, AiCheckSeverity.ok);
    });

    test('ok: anonymized mode (no vocabulary) skips the name check', () {
      // When names were never sent, the gatekeeper does not hunt for invented
      // names — it only restores labels + checks numbers/PII.
      final res = g(
        legend: const {'cat_0': 'Food & Dining'},
        validLabels: const {'cat_0'},
      ).check('You spent on Travel and Food & Dining.');
      // No sentNameVocabulary → name check disabled; "Travel" not flagged here.
      // (Label restore still ran; no leftover labels, no PII, no numbers.)
      expect(res.severity, AiCheckSeverity.ok);
    });
  });

  group('AiGatekeeper.check — goal/bill labels', () {
    test('flagged: leftover goal_N not in validLabels', () {
      final res = AiGatekeeper(
        legend: const {'goal_0': 'New Phone'},
        validLabels: const {'goal_0'},
      ).check('You are saving for goal_9.');
      expect(res.severity, AiCheckSeverity.flagged);
      expect(res.issues.first, contains('goal_9'));
    });

    test('ok: valid goal label is restored', () {
      final gk = AiGatekeeper(
        legend: const {'goal_0': 'New Phone', 'bill_0': 'Netflix'},
        validLabels: const {'goal_0', 'bill_0'},
      );
      expect(gk.restore('Your goal_0 and bill_0 are on track.'),
          'Your New Phone and Netflix are on track.');
      expect(gk.check('Your goal_0 and bill_0 are on track.').severity,
          AiCheckSeverity.ok);
    });
  });
}