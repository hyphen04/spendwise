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

    test('case-insensitive: Cat_0 / CAT_0 are restored too', () {
      // The LLM often capitalizes a label at a sentence start; restore must
      // catch it regardless of case.
      expect(gatekeeper.restore('Cat_0 spiked, and CAT_0 also rose.'),
          'Food & Dining spiked, and Food & Dining also rose.');
    });

    test('fuzzy: cate_0 / category_0 / cat 0 / cat-0 restore to the real name', () {
      // The LLM sometimes invents malformed prefixes/separators. Each
      // canonicalizes to cat_0 → the real name, never leaking the raw token.
      expect(gatekeeper.restore('cate_0 spiked.'), 'Food & Dining spiked.');
      expect(gatekeeper.restore('category_0 spiked.'), 'Food & Dining spiked.');
      expect(gatekeeper.restore('categories_0 spiked.'), 'Food & Dining spiked.');
      expect(gatekeeper.restore('cat 0 spiked.'), 'Food & Dining spiked.');
      expect(gatekeeper.restore('cat-0 spiked.'), 'Food & Dining spiked.');
    });

    test('scrubs an unknown label number to a generic noun (no raw leak)', () {
      // cat_99 is not in the legend → the exact pass leaves it, the fuzzy pass
      // scrubs it to "category" so the user never sees cat_99.
      expect(gatekeeper.restore('You spent a lot on cat_99 this month.'),
          'You spent a lot on category this month.');
    });

    test('scrubs an invalid label like cat_01 to a noun (not corrupted)', () {
      // cat_01 is not a valid legend key; the old pass left it raw. The fuzzy
      // pass canonicalizes it to cat_01 (unknown) and scrubs it to "category"
      // rather than corrupting it into "<Food & Dining>1" or leaking it raw.
      final out = gatekeeper.restore('cat_01 is unknown here.');
      expect(out, 'category is unknown here.');
    });

    test('is a no-op on partial streamed text', () {
      // A half-arrived "cat_" (not a legend key) must not match.
      expect(gatekeeper.restore('You spent cat_'), 'You spent cat_');
    });

    test('scrubs leaked labels to nouns even when the legend is empty', () {
      // shareNames=true path: the legend may be empty, but a leaked label-shaped
      // token is still scrubbed to a generic noun instead of shown raw.
      final g = AiGatekeeper(legend: const {}, validLabels: const {});
      expect(g.restore('Food & Dining spending spiked.'),
          'Food & Dining spending spiked.');
      expect(g.restore('cat_0'), 'category');
      expect(g.restore('acc_1'), 'account');
      expect(g.restore('mode_2'), 'payment mode');
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

    test('flagged: unknown malformed label (cate_99) is flagged', () {
      final res = g(
        legend: const {'cat_0': 'Food'},
        validLabels: const {'cat_0'},
      ).check('You spent a lot on cate_99 this month.');
      expect(res.severity, AiCheckSeverity.flagged);
      // The issue references the raw leaked token so it's debuggable.
      expect(res.issues.any((i) => i.contains('cate_99')), isTrue);
    });

    test('ok: a malformed label that DOES restore is not flagged', () {
      // cate_0 canonicalizes to cat_0, which is valid + in the legend → restored
      // successfully. The gatekeeper must not flag it (no false noise).
      final res = g(
        legend: const {'cat_0': 'Food & Dining'},
        validLabels: const {'cat_0'},
      ).check('You spent most on cate_0 this month.');
      expect(res.severity, AiCheckSeverity.ok);
      expect(res.issues, isEmpty);
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