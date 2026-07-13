import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/tools/ai_tool_protocol.dart';

void main() {
  group('AiToolProtocol.parse', () {
    test('parses a bare JSON tool-call', () {
      final r = AiToolProtocol.parse('{"tool":"breakdown","args":{"group_by":"category","from":"2026-10-01","to":"2026-11-01"}}');
      expect(r.isToolCall, isTrue);
      expect(r.call!.tool, 'breakdown');
      expect(r.call!.args['group_by'], 'category');
      expect(r.call!.args['from'], '2026-10-01');
    });

    test('parses a fenced ```json tool-call', () {
      final r = AiToolProtocol.parse('```json\n{"tool":"list_entities","args":{"kind":"category"}}\n```');
      expect(r.isToolCall, isTrue);
      expect(r.call!.tool, 'list_entities');
      expect(r.call!.args['kind'], 'category');
    });

    test('parses a tool-call embedded in prose (first object wins)', () {
      final r = AiToolProtocol.parse('Let me look that up.\n{"tool":"monthly_totals","args":{"from":"2026-01-01","to":"2026-12-01"}}');
      expect(r.isToolCall, isTrue);
      expect(r.call!.tool, 'monthly_totals');
    });

    test('a plain-text answer with no JSON is the final answer', () {
      final r = AiToolProtocol.parse('You spent 3000 on Food in October.');
      expect(r.isToolCall, isFalse);
      expect(r.text, 'You spent 3000 on Food in October.');
    });

    test('JSON without a "tool" key is a final answer (not a tool-call)', () {
      final r = AiToolProtocol.parse('{"summary":"You spent 3000."}');
      expect(r.isToolCall, isFalse);
    });

    test('malformed JSON is a final answer, never throws', () {
      final r = AiToolProtocol.parse('{"tool":"breakdown","args":');
      expect(r.isToolCall, isFalse);
      expect(r.text, '{"tool":"breakdown","args":');
    });

    test('tool without args still parses (empty args map)', () {
      final r = AiToolProtocol.parse('{"tool":"goals_overview"}');
      expect(r.isToolCall, isTrue);
      expect(r.call!.tool, 'goals_overview');
      expect(r.call!.args, isEmpty);
    });
  });
}