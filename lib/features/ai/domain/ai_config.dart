// Provider preset + non-secret AI configuration for the opt-in AI Copilot.
//
// The API key is deliberately NOT part of this value — it lives in
// SecureStorageService and is injected at call time (see LlmClient).
// Everything here (provider, base URL, model, share-names) is non-secret and
// stored in SharedPreferences.

enum LlmProviderKind {
  openai,
  openrouter,
  groq,
  gemini,
  custom,
}

/// A registered provider preset: id, display label, default base URL, and a
/// sensible default model. Custom has no defaults — the user must supply both.
class LlmProviderPreset {
  const LlmProviderPreset({
    required this.kind,
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.model,
    required this.helpUrl,
    required this.isGemini,
    this.freeTier = false,
  });

  final LlmProviderKind kind;
  final String id; // stored in prefs
  final String label; // shown in settings
  final String baseUrl;
  final String model;
  final String helpUrl; // where the user gets an API key
  final bool isGemini; // Gemini has a different REST shape
  /// True when the default model is usable on the provider's free tier (no
  /// card / no payment required). Shown as a hint in the provider picker.
  final bool freeTier;

  static const List<LlmProviderPreset> all = [
    LlmProviderPreset(
      kind: LlmProviderKind.openai,
      id: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      helpUrl: 'https://platform.openai.com/api-keys',
      isGemini: false,
      // OpenAI has no free API tier; gpt-4o-mini is the cheap-but-powerful pick.
      freeTier: false,
    ),
    LlmProviderPreset(
      kind: LlmProviderKind.openrouter,
      id: 'openrouter',
      label: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      // `openrouter/free` auto-routes to whatever free model is currently
      // available, so the default won't break when an individual free model is
      // retired (e.g. llama-3.3-70b:free is being deprecated). Free models may
      // lack JSON mode — the AI Report falls back to its default charts then.
      model: 'openrouter/free',
      helpUrl: 'https://openrouter.ai/keys',
      isGemini: false,
      freeTier: true,
    ),
    LlmProviderPreset(
      kind: LlmProviderKind.groq,
      id: 'groq',
      label: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'llama-3.3-70b-versatile',
      helpUrl: 'https://console.groq.com/keys',
      isGemini: false,
      freeTier: true,
    ),
    LlmProviderPreset(
      kind: LlmProviderKind.gemini,
      id: 'gemini',
      label: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      // gemini-2.5-flash is on the free tier (1,500 req/day, no card) and is
      // more capable than 2.0-flash. Stable through Oct 2026.
      model: 'gemini-2.5-flash',
      helpUrl: 'https://aistudio.google.com/app/apikey',
      isGemini: true,
      freeTier: true,
    ),
    LlmProviderPreset(
      kind: LlmProviderKind.custom,
      id: 'custom',
      label: 'Custom (OpenAI-compatible)',
      baseUrl: '',
      model: '',
      helpUrl: '',
      isGemini: false,
      freeTier: false,
    ),
  ];

  static LlmProviderPreset byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);
}

/// Resolved (non-secret) AI configuration. The [apiKey] is populated from secure
/// storage only when a request is actually made — it is not persisted here and
/// not held in long-lived state.
class AiConfig {
  const AiConfig({
    required this.preset,
    this.baseUrlOverride,
    this.modelOverride,
    this.shareNames = false, // default: anonymize — see the privacy rule.
    this.apiKey = '',
  });

  final LlmProviderPreset preset;
  final String? baseUrlOverride;
  final String? modelOverride;
  final bool shareNames;
  final String apiKey;

  String get baseUrl {
    final o = baseUrlOverride;
    if (o != null && o.trim().isNotEmpty) return o.trim();
    return preset.baseUrl;
  }

  String get model {
    final o = modelOverride;
    if (o != null && o.trim().isNotEmpty) return o.trim();
    return preset.model;
  }

  bool get isGemini => preset.isGemini;

  /// True when there's enough config to attempt a request (key is checked
  /// separately — see [LlmClient]).
  bool get isConfigured =>
      baseUrl.isNotEmpty && model.isNotEmpty;
}