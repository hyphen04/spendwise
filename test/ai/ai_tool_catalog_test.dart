import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/tools/ai_tool_catalog.dart';

void main() {
  test('catalog defines the 6 tools', () {
    expect(aiToolCatalog.keys, containsAll(const [
      'list_entities', 'breakdown', 'monthly_totals', 'filtered_totals',
      'budget_status', 'goals_overview', 'bills_overview',
    ]));
    expect(aiToolCatalog.length, 7);
  });

  test('catalog text names every tool and its args', () {
    final t = kAiToolCatalogText;
    for (final name in aiToolCatalog.keys) {
      expect(t, contains(name));
    }
    // breakdown must document its required args.
    expect(t, contains('group_by'));
    expect(t, contains('from'));
    expect(t, contains('to'));
  });

  test('filtered_totals documents amount_min/amount_max and entity filters', () {
    final def = aiToolCatalog['filtered_totals']!;
    expect(def.args.keys, containsAll(const ['amount_min', 'amount_max', 'category', 'kind']));
  });
}