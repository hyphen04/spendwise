import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/label_replacer.dart';

void main() {
  const legend = {
    'cat_0': 'Food & Dining',
    'cat_1': 'Home Rent',
    'cat_10': 'Subscriptions',
    'acc_0': 'Cash',
    'mode_0': 'UPI',
    'goal_0': 'New Phone',
    'bill_0': 'Netflix',
  };

  // Restore-direction flags (what AiGatekeeper.restore / InsightAnonymizer.use).
  const restore = (caseInsensitive: true, fuzzy: true);

  group('LabelReplacer.replace — default (anonymize direction)', () {
    test('exact case-sensitive replace, longest-first', () {
      // Default: case-sensitive, no fuzzy — the anonymize behavior.
      expect(LabelReplacer.replace('cat_10 and cat_1', legend),
          'Subscriptions and Home Rent');
    });

    test('default does NOT touch Cat_0 (case-sensitive) or cate_0 (no fuzzy)', () {
      // Anonymize direction must stay conservative: a capitalized or malformed
      // token is left alone (it isn't a real name being re-inserted).
      expect(LabelReplacer.replace('Cat_0 here', legend), 'Cat_0 here');
      expect(LabelReplacer.replace('cate_0 here', legend), 'cate_0 here');
    });

    test('no-op on partial streamed text', () {
      expect(LabelReplacer.replace('You spent cat_', legend), 'You spent cat_');
    });
  });

  group('LabelReplacer.replace — restore direction (caseInsensitive + fuzzy)', () {
    test('replaces labels with real names, longest-first', () {
      expect(
          LabelReplacer.replace('cat_10 and cat_1', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Subscriptions and Home Rent');
    });

    test('is case-insensitive (Cat_0 / CAT_0)', () {
      expect(
          LabelReplacer.replace('Cat_0 and CAT_0', legend,
              caseInsensitive: restore.caseInsensitive),
          'Food & Dining and Food & Dining');
    });

    test('word-boundary: an invalid cat_01 is scrubbed to a noun', () {
      expect(
          LabelReplacer.replace('cat_01 here', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'category here');
    });

    test('fuzzy: alias-prefix variants restore to the real name', () {
      expect(
          LabelReplacer.replace('cate_0 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Food & Dining rose');
      expect(
          LabelReplacer.replace('category_0 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Food & Dining rose');
      expect(
          LabelReplacer.replace('categories_0 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Food & Dining rose');
      expect(
          LabelReplacer.replace('account_0 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Cash rose');
      expect(
          LabelReplacer.replace('accounts_0 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Cash rose');
      expect(
          LabelReplacer.replace('bills_0 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Netflix rose');
      expect(
          LabelReplacer.replace('goals_0 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'New Phone rose');
    });

    test('fuzzy: flexible-separator variants restore', () {
      expect(
          LabelReplacer.replace('cat 0 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Food & Dining rose');
      expect(
          LabelReplacer.replace('cat-0 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Food & Dining rose');
    });

    test('fuzzy: scrubs unknown label numbers to a generic noun', () {
      expect(
          LabelReplacer.replace('cat_99 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'category rose');
      expect(
          LabelReplacer.replace('acc_99 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'account rose');
      expect(
          LabelReplacer.replace('mode_99 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'payment mode rose');
      expect(
          LabelReplacer.replace('goal_99 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'goal rose');
      expect(
          LabelReplacer.replace('bill_99 rose', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'bill rose');
    });

    test('fuzzy: with empty legend, leaked labels are still scrubbed to nouns', () {
      expect(
          LabelReplacer.replace('cat_0 here', const {},
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'category here');
      expect(
          LabelReplacer.replace('cate_0 here', const {},
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'category here');
    });

    test('leaves plain prose untouched (no false fuzzy match)', () {
      expect(
          LabelReplacer.replace('You spent a lot this month.', legend,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'You spent a lot this month.');
    });

    test('does not corrupt a real name that is itself label-shaped', () {
      // "Cat11" is a real name (a legend value). The fuzzy pass must NOT
      // re-match it as label cat_11 and replace it with that label's name —
      // leaving the real name is always safe.
      final legendWithShapedName = {
        'cat_0': 'Cat0',
        'cat_1': 'Cat1',
        'cat_2': 'Cat10',
        'cat_3': 'Cat11',
        'cat_11': 'Cat9',
      };
      expect(
          LabelReplacer.replace('Cat1 and Cat11', legendWithShapedName,
              caseInsensitive: restore.caseInsensitive, fuzzy: restore.fuzzy),
          'Cat1 and Cat11');
    });
  });

  group('LabelReplacer.findLabelTokens', () {
    test('detects exact and malformed label tokens with canonicals', () {
      final found = LabelReplacer.findLabelTokens('cat_0 and cate_1 then cat-2');
      expect(found.map((f) => f.canonical).toList(),
          ['cat_0', 'cat_1', 'cat_2']);
      expect(found.first.raw, 'cat_0');
      expect(found[1].raw, 'cate_1');
      expect(found[2].raw, 'cat-2');
    });

    test('returns empty for plain prose', () {
      expect(LabelReplacer.findLabelTokens('No labels here at all.'), isEmpty);
    });
  });
}