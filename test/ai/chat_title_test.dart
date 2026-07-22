import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/services/ai_chat_controller.dart';

/// Guards the LLM-title cleanup heuristic: whatever the model wraps its title
/// in (quotes, a "Title:" prefix, trailing punctuation, surrounding whitespace),
/// what we persist is the bare title text.
void main() {
  group('cleanThreadTitle', () {
    test('passes through a clean title', () {
      expect(cleanThreadTitle('Over budget this month'), 'Over budget this month');
    });

    test('trims surrounding whitespace', () {
      expect(cleanThreadTitle('  Over budget this month  '),
          'Over budget this month');
    });

    test('strips a "Title:" prefix (case-insensitive)', () {
      expect(cleanThreadTitle('Title: Over budget this month'),
          'Over budget this month');
      expect(cleanThreadTitle('title: Over budget this month'),
          'Over budget this month');
    });

    test('strips a surrounding double-quote pair', () {
      expect(cleanThreadTitle('"Over budget this month"'),
          'Over budget this month');
    });

    test('strips a surrounding single-quote pair', () {
      expect(cleanThreadTitle("'Over budget this month'"),
          'Over budget this month');
    });

    test('removes a trailing period', () {
      expect(cleanThreadTitle('Over budget this month.'), 'Over budget this month');
    });

    test('does not strip a single leading quote (not a pair)', () {
      expect(cleanThreadTitle('"Over budget'), '"Over budget');
    });

    test('handles a model that wraps + prefixes + punctuates', () {
      expect(cleanThreadTitle('  Title: "Why is fuel so pricey?"  '),
          'Why is fuel so pricey?');
    });

    test('empty input stays empty', () {
      expect(cleanThreadTitle(''), '');
      expect(cleanThreadTitle('   '), '');
    });
  });
}