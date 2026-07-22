import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/domain/ai_config.dart';

/// Guards the per-provider default-model invariant: every non-custom preset
/// ships a non-empty default model (so a fresh user can ask immediately), and
/// the free-tier flag is set only for providers whose default is usable without
/// payment. Also pins the specific free-tier defaults we chose.
void main() {
  group('LlmProviderPreset defaults', () {
    test('every non-custom preset has a non-empty default model', () {
      for (final p in LlmProviderPreset.all) {
        if (p.kind == LlmProviderKind.custom) continue;
        expect(p.model,
            isNotEmpty,
            reason: '${p.id} must ship a default model');
      }
    });

    test('custom has no default model or base URL', () {
      final custom = LlmProviderPreset.byId('custom');
      expect(custom.model, '');
      expect(custom.baseUrl, '');
    });

    test('free-tier defaults are the chosen free models', () {
      final gemini = LlmProviderPreset.byId('gemini');
      expect(gemini.freeTier, isTrue);
      expect(gemini.model, 'gemini-2.5-flash');

      final groq = LlmProviderPreset.byId('groq');
      expect(groq.freeTier, isTrue);
      expect(groq.model, 'llama-3.3-70b-versatile');

      final openrouter = LlmProviderPreset.byId('openrouter');
      expect(openrouter.freeTier, isTrue);
      expect(openrouter.model, 'openrouter/free');
    });

    test('OpenAI is not flagged free (no free API tier)', () {
      final openai = LlmProviderPreset.byId('openai');
      expect(openai.freeTier, isFalse);
      expect(openai.model, 'gpt-4o-mini');
    });

    test('byId falls back to the first preset for an unknown id', () {
      expect(LlmProviderPreset.byId('nope').id, LlmProviderPreset.all.first.id);
    });
  });

  group('AiConfig.model resolves override-then-default', () {
    test('uses the override when set', () {
      final preset = LlmProviderPreset.byId('gemini');
      final cfg = AiConfig(preset: preset, modelOverride: 'gemini-2.5-flash-lite');
      expect(cfg.model, 'gemini-2.5-flash-lite');
    });

    test('falls back to the preset default when override is empty', () {
      final preset = LlmProviderPreset.byId('gemini');
      final cfg = AiConfig(preset: preset);
      expect(cfg.model, 'gemini-2.5-flash');
      expect(AiConfig(preset: preset, modelOverride: '').model,
          'gemini-2.5-flash');
      expect(AiConfig(preset: preset, modelOverride: '   ').model,
          'gemini-2.5-flash');
    });
  });
}