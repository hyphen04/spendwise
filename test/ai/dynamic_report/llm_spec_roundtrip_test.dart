import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/ai_gatekeeper.dart';
import 'package:spendwise/features/ai/dynamic_report/chart_spec.dart';
import 'package:spendwise/features/ai/dynamic_report/spec_executor.dart';
import 'package:spendwise/features/ai/dynamic_report/spec_renderer.dart';
import 'package:spendwise/features/ai/dynamic_report/spec_validator.dart';

/// Privacy roundtrip: a fixture blob *as the LLM would return it* (opaque
/// labels only — never real names, never notes/PII) flows through
/// [SpecValidator] (on-device label restore) → [SpecChart] render. We assert
/// the outbound fixture carries no real names, and that restored titles shown
/// to the user do carry real names — the core invariant of the dynamic report.
void main() {
  const realNames = ['Food & Dining', 'Home Rent', 'UPI', 'HDFC Card'];
  const legend = {
    'cat_0': 'Food & Dining',
    'cat_1': 'Home Rent',
    'mode_0': 'UPI',
    'mode_1': 'HDFC Card',
  };

  // The raw blob the LLM emits — only opaque labels, no real names.
  const llmBlob = '''
{
  "charts": [
    {"type":"pie","title":"Where it went (cat_0 led)","provider":"topCategories","params":{"limit":5}},
    {"type":"bar","title":"Cashflow (6 months)","provider":"cashflow6mo","params":{"count":6}},
    {"type":"progress","title":"Budgets (cat_1 over)","provider":"budgets","params":{}}
  ],
  "narrativeSeed":"cat_0 led spending; cat_1 budget went over."
}
''';

  group('outbound fixture (what the LLM saw/returned)', () {
    test('contains no real names — only opaque labels', () {
      for (final name in realNames) {
        expect(llmBlob, isNot(contains(name)),
            reason: 'real name "$name" must never appear in the LLM blob');
      }
      expect(llmBlob, contains('cat_0'));
      expect(llmBlob, contains('cat_1'));
      // No PII-ish tokens in the blob.
      expect(llmBlob.toLowerCase(), isNot(contains('note')));
      expect(llmBlob, isNot(contains('@')));
    });
  });

  group('on-device restore + render', () {
    final gatekeeper = AiGatekeeper(
      legend: legend,
      validLabels: legend.keys.toSet(),
    );
    final validator =
        SpecValidator(gatekeeper: gatekeeper, customSqlEnabled: false);

    test('validate → ValidSpec with restored real-name titles', () {
      final r = validator.parse(llmBlob);
      expect(r, isA<ValidSpec>());
      final spec = (r as ValidSpec).spec;
      expect(spec.charts.length, 3);
      // cat_0 restored to "Food & Dining" in the title.
      expect(spec.charts.first.title, contains('Food & Dining'));
      expect(spec.charts.first.title, isNot(contains('cat_0')));
      // cat_1 restored to "Home Rent".
      expect(spec.charts[2].title, contains('Home Rent'));
      // narrativeSeed is NOT restored — it stays in opaque-label form because
      // it is used only as an outbound hint to the narrative LLM (never shown
      // to the user). Restoring it would leak real names when shareNames=false.
      expect(spec.narrativeSeed, contains('cat_0'));
      expect(spec.narrativeSeed, contains('cat_1'));
      expect(spec.narrativeSeed, isNot(contains('Food & Dining')));
      expect(spec.narrativeSeed, isNot(contains('Home Rent')));
    });

    testWidgets('rendered chart shows real names, not opaque labels',
        (t) async {
      final r = validator.parse(llmBlob);
      final spec = (r as ValidSpec).spec;
      // Hand-built dataset matching the topCategories row shape (the executor
      // would produce this on-device from real data; we never send real data to
      // the LLM, so the dataset is constructed here for the render check only).
      final dataset = ChartDataset([
        {'name': 'Food & Dining', 'icon': '🍔', 'color': '16A34A', 'total': 5000.0},
        {'name': 'Home Rent', 'icon': '🏠', 'color': 'DC2626', 'total': 12000.0},
      ], DataProvider.topCategories);

      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SpecChart(spec: spec.charts.first, dataset: dataset),
        ),
      ));
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Home Rent'), findsOneWidget);
      // No opaque label leaks into the rendered UI.
      expect(find.textContaining('cat_0'), findsNothing);
    });

    test('customSql spec is rejected when customSql is disabled', () {
      const blobWithSql = '''
{
  "charts": [
    {"type":"list","title":"x","provider":"customSql","params":{"sql":"SELECT 1"}}
  ]
}
''';
      final r = validator.parse(blobWithSql);
      expect(r, isA<InvalidSpec>());
      expect(
          (r as InvalidSpec).errors
              .any((e) => e.contains('customSql') || e.contains('not enabled')),
          isTrue);
    });
  });
}