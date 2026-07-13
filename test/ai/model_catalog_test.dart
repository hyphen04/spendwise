import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/model_catalog.dart';

void main() {
  group('parseOpenAiModels', () {
    test('parses OpenAI-style {data:[{id}]} bodies', () {
      const body = '''
{"data":[
  {"id":"gpt-4o-mini","object":"model","owned_by":"openai"},
  {"id":"gpt-4o","object":"model","owned_by":"openai"}
]}
''';
      final models = parseOpenAiModels(body);
      expect(models.length, 2);
      // Sorted alphabetically by id.
      expect(models.first.id, 'gpt-4o');
      expect(models.last.id, 'gpt-4o-mini');
      // No provider `name` label on OpenAI → display falls back to id.
      expect(models.first.display, 'gpt-4o');
      expect(models.first.label, isNull);
    });

    test('parses OpenRouter-style entries with name + context_length', () {
      const body = '''
{"data":[
  {"id":"openai/gpt-4o-mini","name":"OpenAI: GPT-4o-mini","context_length":128000},
  {"id":"anthropic/claude-3.5-sonnet","name":"Anthropic: Claude 3.5 Sonnet","context_length":200000}
]}
''';
      final models = parseOpenAiModels(body);
      expect(models.length, 2);
      final gpt = models.firstWhere((m) => m.id == 'openai/gpt-4o-mini');
      expect(gpt.label, 'OpenAI: GPT-4o-mini');
      expect(gpt.display, 'OpenAI: GPT-4o-mini');
      expect(gpt.contextWindow, 128000);
    });

    test('skips entries without a string id and ignores junk keys', () {
      const body = '''
{"data":[
  {"id":"ok-1"},
  {"object":"model"},
  {"id":123},
  {"id":"  "},
  {"id":"ok-2","context_window":8192}
]}
''';
      final models = parseOpenAiModels(body);
      expect(models.map((m) => m.id), ['ok-1', 'ok-2']);
      expect(models.last.contextWindow, 8192);
    });

    test('non-object / non-list bodies return empty', () {
      expect(parseOpenAiModels('[]'), isEmpty);
      expect(parseOpenAiModels('"hi"'), isEmpty);
      expect(parseOpenAiModels('not json'), isEmpty);
    });
  });

  group('parseGeminiModels', () {
    test('keeps only generateContent models, strips models/ prefix, maps displayName + inputTokenLimit', () {
      const body = '''
{"models":[
  {"name":"models/gemini-2.0-flash","displayName":"Gemini 2.0 Flash","supportedGenerationMethods":["generateContent","countTokens"],"inputTokenLimit":1048576},
  {"name":"models/embedding-001","displayName":"Embedding 001","supportedGenerationMethods":["embedContent"]},
  {"name":"models/gemini-1.5-pro","supportedGenerationMethods":["generateContent"],"inputTokenLimit":2000000}
]}
''';
      final models = parseGeminiModels(body);
      expect(models.length, 2); // embedding-001 dropped.
      final flash = models.firstWhere((m) => m.id == 'gemini-2.0-flash');
      expect(flash.label, 'Gemini 2.0 Flash');
      expect(flash.display, 'Gemini 2.0 Flash');
      expect(flash.contextWindow, 1048576);
      // No displayName → display falls back to the stripped id.
      final pro = models.firstWhere((m) => m.id == 'gemini-1.5-pro');
      expect(pro.label, isNull);
      expect(pro.display, 'gemini-1.5-pro');
    });

    test('handles names without the models/ prefix', () {
      const body = '''
{"models":[{"name":"gemini-2.0-flash","supportedGenerationMethods":["generateContent"]}]}
''';
      expect(parseGeminiModels(body).single.id, 'gemini-2.0-flash');
    });

    test('non-object / non-list bodies return empty', () {
      expect(parseGeminiModels('[]'), isEmpty);
      expect(parseGeminiModels('{}'), isEmpty);
      expect(parseGeminiModels('not json'), isEmpty);
    });
  });
}