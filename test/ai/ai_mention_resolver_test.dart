import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/ai_mention_resolver.dart';

AiMentionData _data({
  List<AiEntityName> categories = const [],
  List<AiEntityName> accounts = const [],
  List<AiEntityName> modes = const [],
  Map<String, double> categoryAmount = const {},
  Map<String, double> modeAmount = const {},
  Map<String, double> accountBalance = const {},
}) =>
    AiMentionData(
      categories: categories,
      accounts: accounts,
      modes: modes,
      categoryAmount: categoryAmount,
      modeAmount: modeAmount,
      accountBalance: accountBalance,
    );

void main() {
  group('AiMentionResolver.resolve', () {
    test('resolves a category name that is in the legend to its label', () {
      final r = AiMentionResolver(
        data: _data(
          categories: const [(id: 'c3', name: 'Fuel')],
          categoryAmount: const {'c3': 1200},
        ),
        legend: const {'cat_0': 'Food', 'cat_3': 'Fuel'},
      );
      final res = r.resolve('Tell me about fuel this month');
      expect(res.hasMentions, isTrue);
      expect(res.hint, contains('Context note'));
      expect(res.hint, contains('cat_3'));
      expect(res.hint, contains('1200'));
      expect(res.amounts, contains(1200.0));
      expect(res.matchedNames, contains('Fuel'));
    });

    test('resolves a category NOT in the legend (no spend) without a label', () {
      // Fuel exists as a category but has no spend this month and isn't in the
      // top-5, so it never received a label in the context.
      final r = AiMentionResolver(
        data: _data(
          categories: const [(id: 'c9', name: 'Fuel')],
          categoryAmount: const {},
        ),
        legend: const {'cat_0': 'Food'},
      );
      final res = r.resolve('how is my fuel category doing');
      expect(res.hasMentions, isTrue);
      expect(res.hint, contains('one of your categories'));
      expect(res.hint, contains('spent 0'));
      expect(res.hint, isNot(contains('cat_')));
      expect(res.amounts, contains(0.0));
    });

    test('matching is case-insensitive', () {
      final r = AiMentionResolver(
        data: _data(categories: const [(id: 'c3', name: 'Fuel')]),
        legend: const {'cat_3': 'Fuel'},
      );
      final res = r.resolve('WHAT ABOUT FUEL?');
      expect(res.hasMentions, isTrue);
      expect(res.hint, contains('cat_3'));
    });

    test('longest name wins so "Food & Dining" is not split into "Food"', () {
      final r = AiMentionResolver(
        data: _data(
          categories: const [
            (id: 'c1', name: 'Food'),
            (id: 'c2', name: 'Food & Dining'),
          ],
          categoryAmount: const {'c2': 3000},
        ),
        legend: const {'cat_2': 'Food & Dining'},
      );
      final res = r.resolve('tell me about food & dining');
      expect(res.hasMentions, isTrue);
      // Only one note, for the longer match — "Food" is not double-matched.
      expect(res.matchedNames, ['Food & Dining']);
      expect(res.hint, contains('cat_2'));
      expect(res.hint, contains('3000'));
    });

    test('no mention -> empty hint', () {
      final r = AiMentionResolver(
        data: _data(categories: const [(id: 'c3', name: 'Fuel')]),
        legend: const {'cat_3': 'Fuel'},
      );
      final res = r.resolve('how is my spending overall?');
      expect(res.hasMentions, isFalse);
      expect(res.hint, '');
      expect(res.amounts, isEmpty);
    });

    test('word boundary: short name does not match inside a longer word', () {
      final r = AiMentionResolver(
        data: _data(categories: const [(id: 'c1', name: 'Car')]),
        legend: const {},
      );
      // "Car" (3 letters) must not match inside "carry" or "cardigan".
      final res = r.resolve('i carry a lot of cardigan');
      expect(res.hasMentions, isFalse);
    });

    test('resolves an account mention with its balance and label', () {
      final r = AiMentionResolver(
        data: _data(
          accounts: const [(id: 'a1', name: 'HDFC Card')],
          accountBalance: const {'a1': 45000},
        ),
        legend: const {'acc_1': 'HDFC Card'},
      );
      final res = r.resolve('what is in my hdfc card account');
      expect(res.hasMentions, isTrue);
      expect(res.hint, contains('acc_1'));
      expect(res.hint, contains('45000'));
      expect(res.hint, contains('account'));
    });

    test('resolves multiple distinct mentions in one message', () {
      final r = AiMentionResolver(
        data: _data(
          categories: const [(id: 'c3', name: 'Fuel')],
          accounts: const [(id: 'a1', name: 'HDFC')],
          accountBalance: const {'a1': 12000},
        ),
        legend: const {'cat_3': 'Fuel', 'acc_1': 'HDFC'},
      );
      final res = r.resolve('compare fuel spending vs my hdfc balance');
      expect(res.hasMentions, isTrue);
      expect(res.hint, contains('cat_3'));
      expect(res.hint, contains('acc_1'));
      expect(res.matchedNames.length, 2);
    });

    test('privacy: a directory name the user did NOT type never appears in the hint', () {
      final r = AiMentionResolver(
        data: _data(
          categories: const [
            (id: 'c3', name: 'Fuel'),
            (id: 'c4', name: 'Therapy'), // sensitive, NOT mentioned
          ],
          categoryAmount: const {'c3': 1200, 'c4': 8000},
        ),
        legend: const {'cat_3': 'Fuel'},
      );
      final res = r.resolve('tell me about fuel');
      expect(res.hint, contains('Fuel'));
      expect(res.hint, isNot(contains('Therapy')));
      expect(res.hint, isNot(contains('8000')));
      expect(res.amounts, isNot(contains(8000.0)));
    });

    test('empty message -> no mentions', () {
      final r = AiMentionResolver(
        data: _data(categories: const [(id: 'c3', name: 'Fuel')]),
        legend: const {},
      );
      expect(r.resolve('').hasMentions, isFalse);
      expect(r.resolve('   ').hasMentions, isFalse);
    });

    test('names shorter than 3 characters are not matched', () {
      final r = AiMentionResolver(
        data: _data(categories: const [(id: 'c1', name: 'PC')]),
        legend: const {},
      );
      expect(r.resolve('spending on my pc').hasMentions, isFalse);
    });
  });
}