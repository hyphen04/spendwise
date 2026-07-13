import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_config.dart';
import 'llm_client.dart';

/// Google Gemini client. Gemini uses a different REST shape from the
/// OpenAI-compatible family: `:generateContent` (non-streaming) and
/// `:streamGenerateContent?alt=sse` (streaming), with the key as a query
/// param and roles named `user` / `model` (not `assistant`). The system
/// prompt goes in a separate `systemInstruction` field.
class GeminiLlmClient implements LlmClient {
  static const Duration _timeout = Duration(seconds: 60);

  String _modelPath(AiConfig config) =>
      '${config.baseUrl}/models/${config.model}';

  Map<String, dynamic> _payload(List<ChatMessage> messages, int? maxTokens,
          {bool json = false}) =>
      geminiPayloadFor(messages, maxTokens: maxTokens, json: json);

  String _extractContent(String body) {
    final decoded = jsonDecode(body);
    final candidates = decoded['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final parts = candidates[0]['content']?['parts'];
      if (parts is List) {
        final text = parts
            .map((p) => (p is Map && p['text'] is String) ? p['text'] as String : '')
            .join();
        if (text.isNotEmpty) return text;
      }
    }
    throw const LlmException(LlmErrorKind.parse);
  }

  @override
  Future<String> complete(AiConfig config, List<ChatMessage> messages,
      {int? maxTokens, bool json = false}) async {
    validateConfig(config);
    final uri = Uri.parse(
        '${_modelPath(config)}:generateContent?key=${config.apiKey}');
    try {
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(_payload(messages, maxTokens, json: json)))
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw httpStatusToException(response.statusCode, response.body);
      }
      return _extractContent(response.body);
    } on LlmException {
      rethrow;
    } on http.ClientException {
      throw const LlmException(LlmErrorKind.network);
    } on TimeoutException {
      throw const LlmException(LlmErrorKind.network);
    } catch (e) {
      throw LlmException(LlmErrorKind.parse, e.toString());
    }
  }

  @override
  Stream<String> stream(AiConfig config, List<ChatMessage> messages,
      {int? maxTokens}) async* {
    validateConfig(config);
    final uri = Uri.parse(
        '${_modelPath(config)}:streamGenerateContent?alt=sse&key=${config.apiKey}');
    final client = http.Client();
    try {
      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(_payload(messages, maxTokens));
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode != 200) {
        final bodyText = await response.stream.bytesToString();
        throw httpStatusToException(response.statusCode, bodyText);
      }
      // Gemini SSE: each `data:` line is a full candidate chunk.
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.isEmpty || !line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data);
          final parts = json['candidates']?[0]?['content']?['parts'];
          if (parts is List) {
            for (final p in parts) {
              if (p is Map && p['text'] is String && (p['text'] as String).isNotEmpty) {
                yield p['text'] as String;
              }
            }
          }
        } catch (_) {
          // Skip malformed-but-continuable chunks.
        }
      }
    } on LlmException {
      rethrow;
    } on http.ClientException {
      throw const LlmException(LlmErrorKind.network);
    } on TimeoutException {
      throw const LlmException(LlmErrorKind.network);
    } catch (e) {
      throw LlmException(LlmErrorKind.parse, e.toString());
    } finally {
      client.close();
    }
  }
}

/// Builds the Gemini `generateContent` / `streamGenerateContent` payload.
/// Extracted to a top-level `@visibleForTesting` function so the role mapping
/// (system → systemInstruction, assistant → model, user → user) can be
/// asserted without hitting the network.
@visibleForTesting
Map<String, dynamic> geminiPayloadFor(List<ChatMessage> messages,
    {int? maxTokens, bool json = false}) {
  // Split out the system message(s) into systemInstruction; Gemini does not
  // accept 'system' as a content role.
  final systemParts = <Map<String, dynamic>>[];
  final contents = <Map<String, dynamic>>[];
  for (final m in messages) {
    if (m.role == 'system') {
      systemParts.add({'text': m.content});
    } else {
      contents.add({
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': [
          {'text': m.content}
        ],
      });
    }
  }
  final payload = <String, dynamic>{
    'contents': contents,
  };
  if (systemParts.isNotEmpty) {
    payload['systemInstruction'] = {'parts': systemParts};
  }
  payload['generationConfig'] = {
    'maxOutputTokens': maxTokens ?? 1024,
    'temperature': 0.4,
    // JSON mode: Gemini supports responseMimeType application/json. We don't
    // pass a strict responseSchema (propertyOrdering is ignored and some
    // models reject schemas); the Dart SpecValidator is the source of truth.
    if (json) 'responseMimeType': 'application/json',
  };
  return payload;
}