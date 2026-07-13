/// A model offered by the user's chosen LLM provider.
///
/// `id` is the string stored in prefs (`ai_model`) and sent in the `model` field
/// of a request — e.g. `gpt-4o-mini`, `openai/gpt-4o-mini`, `gemini-2.0-flash`.
/// `label` is the provider's human-facing name for it (OpenRouter `name`, Gemini
/// `displayName`); when absent we fall back to `id`. This is **public model
/// metadata only** — it never carries any SpendWise data, keys, or PII (see
/// [ModelCatalog]).
class AiModel {
  const AiModel({
    required this.id,
    this.label,
    this.description,
    this.contextWindow,
  });

  final String id;
  final String? label;
  final String? description;

  /// Max input tokens the model accepts, when the provider reports it.
  final int? contextWindow;

  /// Display text: the provider label when present, else the id.
  String get display =>
      (label != null && label!.trim().isNotEmpty) ? label! : id;
}