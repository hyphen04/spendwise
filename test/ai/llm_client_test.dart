import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/ai_config.dart';
import 'package:spendwise/features/ai/domain/llm_client.dart';
import 'package:spendwise/features/ai/domain/openai_compatible_client.dart';
import 'package:spendwise/features/ai/domain/gemini_client.dart';

void main() {
  group('LlmProviderPreset', () {
    test('byId resolves a known provider', () {
      expect(LlmProviderPreset.byId('groq').kind, LlmProviderKind.groq);
      expect(LlmProviderPreset.byId('gemini').isGemini, isTrue);
    });

    test('byId falls back to the first preset for an unknown id', () {
      expect(LlmProviderPreset.byId('nonsense').id, 'openai');
    });

    test('every non-custom preset ships a default base URL and model', () {
      for (final p in LlmProviderPreset.all) {
        if (p.kind == LlmProviderKind.custom) continue;
        expect(p.baseUrl, isNotEmpty);
        expect(p.model, isNotEmpty);
      }
    });
  });

  group('AiConfig resolution', () {
    test('uses preset defaults when no override is given', () {
      final c = AiConfig(preset: LlmProviderPreset.byId('openai'));
      expect(c.baseUrl, 'https://api.openai.com/v1');
      expect(c.model, 'gpt-4o-mini');
      expect(c.isConfigured, isTrue);
    });

    test('override wins over preset default', () {
      final c = AiConfig(
        preset: LlmProviderPreset.byId('openai'),
        baseUrlOverride: 'https://my-proxy.example.com/v1 ',
        modelOverride: 'gpt-4o',
      );
      expect(c.baseUrl, 'https://my-proxy.example.com/v1'); // trimmed
      expect(c.model, 'gpt-4o');
    });

    test('blank/empty overrides fall back to the preset default', () {
      final c = AiConfig(
        preset: LlmProviderPreset.byId('openai'),
        baseUrlOverride: '   ',
        modelOverride: '',
      );
      expect(c.baseUrl, 'https://api.openai.com/v1');
      expect(c.model, 'gpt-4o-mini');
    });

    test('custom preset with no overrides is not configured', () {
      final c = AiConfig(preset: LlmProviderPreset.byId('custom'));
      expect(c.isConfigured, isFalse);
    });
  });

  group('validateConfig', () {
    test('throws noKey when the API key is empty', () {
      final c = AiConfig(preset: LlmProviderPreset.byId('openai'));
      expect(
        () => validateConfig(c),
        throwsA(predicate(
            (e) => e is LlmException && e.kind == LlmErrorKind.noKey)),
      );
    });

    test('throws badConfig when provider is custom and unconfigured', () {
      final c = AiConfig(
        preset: LlmProviderPreset.byId('custom'),
        apiKey: 'sk-test',
      );
      expect(
        () => validateConfig(c),
        throwsA(predicate(
            (e) => e is LlmException && e.kind == LlmErrorKind.badConfig)),
      );
    });

    test('passes for a fully-populated config', () {
      final c = AiConfig(
        preset: LlmProviderPreset.byId('openai'),
        apiKey: 'sk-test',
      );
      expect(() => validateConfig(c), returnsNormally);
    });
  });

  group('httpStatusToException', () {
    void expectKind(int status, LlmErrorKind kind) {
      expect(httpStatusToException(status, null).kind, kind);
    }

    test('maps common status codes', () {
      expectKind(401, LlmErrorKind.auth);
      expectKind(403, LlmErrorKind.auth);
      expectKind(404, LlmErrorKind.notFound);
      expectKind(429, LlmErrorKind.rateLimit);
      expectKind(500, LlmErrorKind.provider);
      expectKind(503, LlmErrorKind.provider);
    });

    test('userMessage is non-empty for every kind', () {
      for (final k in LlmErrorKind.values) {
        expect(LlmException(k).userMessage, isNotEmpty);
      }
    });
  });

  group('OpenAI-compatible body', () {
    test('shape: model, messages, stream, and conservative limits', () {
      final config = AiConfig(
        preset: LlmProviderPreset.byId('openai'),
        apiKey: 'sk-test',
      );
      final body = openAiBodyFor(
        config,
        const [
          ChatMessage(role: 'system', content: 'be concise'),
          ChatMessage(role: 'user', content: 'hi'),
        ],
        true,
      );
      expect(body['model'], 'gpt-4o-mini');
      expect(body['stream'], isTrue);
      expect(body['max_tokens'], 1024);
      expect(body['temperature'], 0.4);
      final messages = body['messages'] as List;
      expect(messages.length, 2);
      expect((messages[0] as Map)['role'], 'system');
      expect((messages[1] as Map)['content'], 'hi');
    });

    test('json mode adds response_format and is off by default', () {
      final config = AiConfig(
        preset: LlmProviderPreset.byId('openai'),
        apiKey: 'sk-test',
      );
      // Default: no response_format.
      final plain = openAiBodyFor(config, const [
        ChatMessage(role: 'user', content: 'hi'),
      ], false);
      expect(plain.containsKey('response_format'), isFalse);

      // json: true → json_object response_format.
      final json = openAiBodyFor(config, const [
        ChatMessage(role: 'user', content: 'hi'),
      ], false, json: true);
      expect(json['response_format'], {'type': 'json_object'});
    });
  });

  group('Gemini payload role mapping', () {
    test('system → systemInstruction; assistant → model; user → user', () {
      final payload = geminiPayloadFor(const [
        ChatMessage(role: 'system', content: 'be concise'),
        ChatMessage(role: 'user', content: 'hi'),
        ChatMessage(role: 'assistant', content: 'hello back'),
      ]);
      // System moved out of contents.
      final contents = payload['contents'] as List;
      expect(contents.length, 2);
      expect((contents[0] as Map)['role'], 'user');
      expect((contents[1] as Map)['role'], 'model');
      // System instruction present.
      expect(payload['systemInstruction'], isNotNull);
      final parts = (payload['systemInstruction'] as Map)['parts'] as List;
      expect((parts[0] as Map)['text'], 'be concise');
      // Generation config capped.
      expect((payload['generationConfig'] as Map)['maxOutputTokens'], 1024);
    });

    test('no system message → no systemInstruction field', () {
      final payload = geminiPayloadFor(
          const [ChatMessage(role: 'user', content: 'hi')]);
      expect(payload.containsKey('systemInstruction'), isFalse);
    });

    test('json mode adds responseMimeType and is off by default', () {
      final plain = geminiPayloadFor(
          const [ChatMessage(role: 'user', content: 'hi')]);
      final genConfig = plain['generationConfig'] as Map;
      expect(genConfig.containsKey('responseMimeType'), isFalse);

      final json = geminiPayloadFor(
          const [ChatMessage(role: 'user', content: 'hi')],
          json: true);
      expect((json['generationConfig'] as Map)['responseMimeType'],
          'application/json');
    });
  });

  group('LlmClient.forConfig', () {
    test('returns Gemini client for a Gemini preset', () {
      final c = AiConfig(preset: LlmProviderPreset.byId('gemini'));
      expect(LlmClient.forConfig(c), isA<GeminiLlmClient>());
    });

    test('returns OpenAI-compatible client for an OpenAI preset', () {
      final c = AiConfig(preset: LlmProviderPreset.byId('openai'));
      expect(LlmClient.forConfig(c), isA<OpenAiCompatibleLlmClient>());
    });

    test('returns OpenAI-compatible client for Groq', () {
      final c = AiConfig(preset: LlmProviderPreset.byId('groq'));
      expect(LlmClient.forConfig(c), isA<OpenAiCompatibleLlmClient>());
    });
  });
}