import 'ai_config.dart';
import 'openai_compatible_client.dart';
import 'gemini_client.dart';

/// A single chat message. Roles follow the OpenAI convention ('system',
/// 'user', 'assistant'); Gemini maps 'assistant' → 'model' internally.
class ChatMessage {
  const ChatMessage({required this.role, required this.content});
  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Typed errors so the UI can map to specific, actionable messages instead of
/// showing a raw exception string.
enum LlmErrorKind {
  noKey,
  badConfig,
  auth,
  notFound,
  rateLimit,
  provider,
  network,
  parse,
}

class LlmException implements Exception {
  const LlmException(this.kind, [this.message]);
  final LlmErrorKind kind;
  final String? message;

  String get userMessage => switch (kind) {
        LlmErrorKind.noKey =>
          'Add your AI API key in Settings to use this feature.',
        LlmErrorKind.badConfig =>
          'AI settings look incomplete — check the provider, base URL, and model.',
        LlmErrorKind.auth => 'Invalid API key — check it in Settings.',
        LlmErrorKind.notFound =>
          'Model or endpoint not found — check the model name and base URL.',
        LlmErrorKind.rateLimit =>
          'Rate limit reached — wait a moment and try again.',
        LlmErrorKind.network =>
          'Network error — check your connection and try again.',
        LlmErrorKind.provider =>
          'The AI provider returned an error. Try again or switch models.',
        LlmErrorKind.parse => 'Unexpected response from the AI provider.',
      };

  @override
  String toString() => 'LlmException($kind): ${message ?? userMessage}';
}

/// Stateless LLM client. Implementations ([OpenAiCompatibleLlmClient],
/// [GeminiLlmClient]) cover the supported [LlmProviderPreset] kinds. The API
/// key is taken from [AiConfig.apiKey] (populated at call time from secure
/// storage) — implementations must never read it from anywhere else.
abstract class LlmClient {
  /// Non-streaming completion → full assistant text.
  ///
  /// [maxTokens] overrides the default completion length cap (1024) — the
  /// narrative report path passes a larger value so long-form output isn't
  /// truncated. When null, the client default is used.
  ///
  /// [json]: when true, request a structured-JSON response (`response_format:
  /// {"type":"json_object"}` for OpenAI-compatible, `responseMimeType:
  /// "application/json"` for Gemini). Provider enforcement is uneven, so the
  /// caller must still parse + validate (e.g. [SpecValidator]); this only nudges
  /// the model toward emitting valid JSON.
  Future<String> complete(AiConfig config, List<ChatMessage> messages,
      {int? maxTokens, bool json = false});

  /// Streaming completion → incremental text chunks as they arrive.
  ///
  /// See [complete] for [maxTokens].
  Stream<String> stream(AiConfig config, List<ChatMessage> messages,
      {int? maxTokens});

  /// Resolve the right client implementation for a config's provider.
  factory LlmClient.forConfig(AiConfig config) {
    if (config.isGemini) return GeminiLlmClient();
    return OpenAiCompatibleLlmClient();
  }
}

/// Shared helper: map an HTTP status code to a typed [LlmException].
LlmException httpStatusToException(int status, String? body) {
  switch (status) {
    case 401:
    case 403:
      return const LlmException(LlmErrorKind.auth);
    case 404:
      return const LlmException(LlmErrorKind.notFound);
    case 429:
      return const LlmException(LlmErrorKind.rateLimit);
    case >= 500:
      return LlmException(LlmErrorKind.provider, body);
    default:
      return LlmException(LlmErrorKind.provider, 'HTTP $status: $body');
  }
}

/// Pre-request validation shared by both clients.
void validateConfig(AiConfig config) {
  if (config.apiKey.trim().isEmpty) {
    throw const LlmException(LlmErrorKind.noKey);
  }
  if (!config.isConfigured) {
    throw const LlmException(LlmErrorKind.badConfig);
  }
}