import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_config.dart';
import 'ai_model.dart';
import 'llm_client.dart';

/// Raised when no model list can be fetched for the config — specifically a
/// `custom` provider with no base URL. This is **not** an error to surface as a
/// failure: the caller falls back to manual model-name entry.
class ModelListUnavailable implements Exception {
  const ModelListUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'ModelListUnavailable: $reason';
}

/// Fetches the list of models the user's chosen provider supports.
///
/// This is the only other outbound call besides the chat-completion clients
/// (`openai_compatible_client.dart`, `gemini_client.dart`). It sends **only**
/// the user's API key (Bearer header for OpenAI-compat, `?key=` for Gemini) to
/// the provider's own `GET /models` endpoint — the same boundary as a chat
/// call. No SpendWise data, transactions, notes, rows, amounts, names, or PII
/// are ever sent here. The returned [AiModel] list is public model metadata
/// only (id, label, description, context window) and carries no secrets.
///
/// The API key is read from [AiConfig.apiKey] (populated by the caller via
/// `aiConfigWithKey` on demand) and is never retained by this class — it is a
/// stateless, one-shot fetch.
class ModelCatalog {
  static const Duration _timeout = Duration(seconds: 30);

  /// Fetch every model the provider exposes for this config.
  ///
  /// - `gemini` → `GET {baseUrl}/models?pageSize=100&key=…`
  /// - `custom` with no base URL → throws [ModelListUnavailable]
  /// - otherwise (openai / openrouter / groq / custom-with-URL) →
  ///   `GET {baseUrl}/models` with a Bearer key + OpenRouter attribution
  ///   headers when relevant.
  ///
  /// Non-200 responses map to a typed [LlmException] (via
  /// [httpStatusToException]) so the UI shows an actionable message.
  Future<List<AiModel>> listModels(AiConfig config) async {
    if (config.isGemini) return _listGemini(config);
    final base = config.baseUrl.trim();
    if (base.isEmpty) {
      throw const ModelListUnavailable(
          'This provider has no model-list endpoint.');
    }
    return _listOpenAiCompatible(config, base);
  }

  Future<List<AiModel>> _listOpenAiCompatible(
      AiConfig config, String base) async {
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final uri = Uri.parse('$trimmed/models');
    final headers = <String, String>{
      if (config.apiKey.trim().isNotEmpty)
        'Authorization': 'Bearer ${config.apiKey}',
      'Accept': 'application/json',
      // OpenRouter attribution headers (ignored by other providers).
      if (config.preset.kind == LlmProviderKind.openrouter) ...{
        'HTTP-Referer': 'https://github.com/hyphen04/spendwise',
        'X-Title': 'SpendWise',
      },
    };
    try {
      final response =
          await http.get(uri, headers: headers).timeout(_timeout);
      if (response.statusCode != 200) {
        throw httpStatusToException(response.statusCode, response.body);
      }
      return parseOpenAiModels(response.body);
    } on LlmException {
      rethrow;
    } on ModelListUnavailable {
      rethrow;
    } on http.ClientException {
      throw const LlmException(LlmErrorKind.network);
    } on TimeoutException {
      throw const LlmException(LlmErrorKind.network);
    } catch (e) {
      throw LlmException(LlmErrorKind.parse, e.toString());
    }
  }

  Future<List<AiModel>> _listGemini(AiConfig config) async {
    final base = config.baseUrl.trim();
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final uri = Uri.parse('$trimmed/models').replace(queryParameters: {
      'pageSize': '100',
      if (config.apiKey.trim().isNotEmpty) 'key': config.apiKey,
    });
    try {
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw httpStatusToException(response.statusCode, response.body);
      }
      return parseGeminiModels(response.body);
    } on LlmException {
      rethrow;
    } on ModelListUnavailable {
      rethrow;
    } on http.ClientException {
      throw const LlmException(LlmErrorKind.network);
    } on TimeoutException {
      throw const LlmException(LlmErrorKind.network);
    } catch (e) {
      throw LlmException(LlmErrorKind.parse, e.toString());
    }
  }
}

/// Parses an OpenAI-compatible `GET /models` body (`{data: [{id, …}]}`) into
/// [AiModel]s. Pure + unit-testable (no network). Handles OpenAI, OpenRouter,
/// and Groq — each puts the human label / context window under slightly
/// different keys, so we probe a small set.
@visibleForTesting
List<AiModel> parseOpenAiModels(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map<String, Object?>) return const [];
  final data = decoded['data'];
  if (data is! List) return const [];
  final out = <AiModel>[];
  for (final e in data) {
    if (e is! Map<String, Object?>) continue;
    final id = e['id'];
    if (id is! String || id.trim().isEmpty) continue;
    out.add(AiModel(
      id: id,
      label: e['name'] as String?,
      description: e['description'] as String?,
      contextWindow: _asInt(e['context_length']) ??
          _asInt(e['context_window']) ??
          _asInt(e['max_context_length']),
    ));
  }
  // Stable, browsable order: alphabetical by id. (Providers return arbitrary
  // order — OpenRouter's is large and unsorted.)
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

/// Parses a Gemini `GET /models` body (`{models: [{name, displayName,
/// supportedGenerationMethods, inputTokenLimit, …}]}`) into [AiModel]s,
/// keeping only models that support `generateContent` (the chat path) and
/// stripping the leading `models/` from the name. Pure + unit-testable.
@visibleForTesting
List<AiModel> parseGeminiModels(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map<String, Object?>) return const [];
  final models = decoded['models'];
  if (models is! List) return const [];
  final out = <AiModel>[];
  for (final m in models) {
    if (m is! Map<String, Object?>) continue;
    final name = m['name'];
    if (name is! String || name.trim().isEmpty) continue;
    final methods = m['supportedGenerationMethods'];
    if (methods is! List || !methods.any((v) => v == 'generateContent')) {
      continue;
    }
    final id = name.startsWith('models/') ? name.substring(7) : name;
    out.add(AiModel(
      id: id,
      label: m['displayName'] as String?,
      description: m['description'] as String?,
      contextWindow: _asInt(m['inputTokenLimit']),
    ));
  }
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}