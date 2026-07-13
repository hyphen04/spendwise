import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/ai_gatekeeper.dart';
import 'package:spendwise/features/ai/dynamic_report/chart_spec.dart';
import 'package:spendwise/features/ai/dynamic_report/spec_validator.dart';

void main() {
  group('SpecValidator.parse', () {
    final plain = const SpecValidator();

    test('valid 3-chart spec → ValidSpec', () {
      const raw = '''
{
  "charts": [
    {"type":"pie","title":"Where it went","provider":"topCategories","params":{"limit":8}},
    {"type":"bar","title":"Cashflow (6 months)","provider":"cashflow6mo","params":{"count":6}},
    {"type":"progress","title":"Budgets","provider":"budgets","params":{}}
  ],
  "narrativeSeed":"cat_0 led spending."
}
''';
      final r = plain.parse(raw);
      expect(r, isA<ValidSpec>());
      final spec = (r as ValidSpec).spec;
      expect(spec.charts.length, 3);
      expect(spec.charts[0].type, ChartType.pie);
      expect(spec.charts[0].provider, DataProvider.topCategories);
      expect(spec.charts[0].params['limit'], 8);
      expect(spec.narrativeSeed, 'cat_0 led spending.');
    });

    test('non-JSON → InvalidSpec', () {
      final r = plain.parse('not json at all {{');
      expect(r, isA<InvalidSpec>());
      expect((r as InvalidSpec).errors, isNotEmpty);
    });

    test('top-level array (not object) → InvalidSpec', () {
      final r = plain.parse('[]');
      expect(r, isA<InvalidSpec>());
    });

    test('empty charts → InvalidSpec', () {
      final r = plain.parse('{"charts":[]}');
      expect(r, isA<InvalidSpec>());
    });

    test('unknown chart type → InvalidSpec', () {
      final r = plain.parse(
          '{"charts":[{"type":"radar","title":"x","provider":"budgets","params":{}}]}');
      expect(r, isA<InvalidSpec>());
      expect((r as InvalidSpec).errors.first, contains('type'));
    });

    test('unknown provider → InvalidSpec', () {
      final r = plain.parse(
          '{"charts":[{"type":"pie","title":"x","provider":"magic","params":{}}]}');
      expect(r, isA<InvalidSpec>());
      expect((r as InvalidSpec).errors.first, contains('provider'));
    });

    test('missing title → InvalidSpec', () {
      final r = plain.parse(
          '{"charts":[{"type":"pie","provider":"budgets","params":{}}]}');
      expect(r, isA<InvalidSpec>());
      expect((r as InvalidSpec).errors.any((e) => e.contains('title')), isTrue);
    });

    test('unknown param key → InvalidSpec', () {
      final r = plain.parse(
          '{"charts":[{"type":"pie","title":"x","provider":"topCategories","params":{"bogus":1}}]}');
      expect(r, isA<InvalidSpec>());
      expect((r as InvalidSpec).errors.any((e) => e.contains('bogus')), isTrue);
    });

    test('customSql without sql param → InvalidSpec', () {
      final r = plain.parse(
          '{"charts":[{"type":"list","title":"x","provider":"customSql","params":{}}]}');
      expect(r, isA<InvalidSpec>());
      expect((r as InvalidSpec).errors.any((e) => e.contains('sql')), isTrue);
    });

    test('customSql with sql param but disabled → InvalidSpec', () {
      const raw =
          '{"charts":[{"type":"list","title":"x","provider":"customSql","params":{"sql":"SELECT 1"}}]}';
      expect(plain.parse(raw), isA<InvalidSpec>());
    });

    test('customSql with sql param + enabled → ValidSpec', () {
      const raw =
          '{"charts":[{"type":"list","title":"x","provider":"customSql","params":{"sql":"SELECT 1 AS n"}}]}';
      final r = const SpecValidator(customSqlEnabled: true).parse(raw);
      expect(r, isA<ValidSpec>());
      expect((r as ValidSpec).spec.charts.first.params['sql'], 'SELECT 1 AS n');
    });

    test('one bad chart rejects the whole spec (one retry, then fallback)', () {
      const raw = '''
{"charts":[
  {"type":"pie","title":"ok","provider":"budgets","params":{}},
  {"type":"bogus","title":"bad","provider":"budgets","params":{}}
]}''';
      final r = plain.parse(raw);
      expect(r, isA<InvalidSpec>());
    });
  });

  group('SpecValidator with gatekeeper', () {
    final gatekeeper = AiGatekeeper(
      legend: const {'cat_0': 'Food & Dining'},
      validLabels: const {'cat_0'},
    );
    final v = SpecValidator(gatekeeper: gatekeeper);

    test('opaque labels in title are restored on-device', () {
      const raw =
          '{"charts":[{"type":"pie","title":"cat_0 led spending","provider":"topCategories","params":{}}]}';
      final r = v.parse(raw);
      expect(r, isA<ValidSpec>());
      expect((r as ValidSpec).spec.charts.first.title, 'Food & Dining led spending');
    });

    test('narrativeSeed labels are NOT restored (stays opaque for outbound use)', () {
      // narrativeSeed is used only as an outbound hint to the narrative LLM and
      // is never shown to the user, so it must stay in opaque-label form to
      // avoid leaking real names when the user has not opted into sharing names.
      // (Chart titles above ARE restored because they render on-device.) Any
      // opaque labels the LLM echoes into the narrative are restored on-device
      // during streaming by the AiGatekeeper.
      const raw =
          '{"charts":[{"type":"stat","title":"Net","provider":"monthlySummary","params":{}}],"narrativeSeed":"cat_0 was notable."}';
      final r = v.parse(raw);
      expect(r, isA<ValidSpec>());
      expect((r as ValidSpec).spec.narrativeSeed, 'cat_0 was notable.');
    });
  });
}