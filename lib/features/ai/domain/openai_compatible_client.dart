import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_config.dart';
import 'llm_client.dart';

/// OpenAI-compatible chat-completions client.
///
/// One implementation covers OpenAI, OpenRouter, Groq, Ollama, and any custom
/// endpoint that speaks the `/chat/completions` shape. Gemini is handled
/// separately ([GeminiLlmClient]) because its REST shape differs.
///
/// Streaming uses Server-Sent Events parsed from the `http` `StreamedResponse`
/// (mirrors `UpdateService.downloadApk`'s streaming pattern). Non-streaming
/// reads the full JSON body.
class OpenAiCompatibleLlmClient implements LlmClient {
  static const Duration _timeout = Duration(seconds: 60);

  Uri _uri(AiConfig config) {
    // Trim trailing slashes (custom overrides may include one), then append the
    // chat-completions path. Presets already have no trailing slash.
    final base = config.baseUrl;
    final trimmed =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$trimmed/chat/completions');
  }

  Map<String, String> _headers(AiConfig config) => {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        // OpenRouter attribution headers (ignored by other providers).
        if (config.preset.kind == LlmProviderKind.openrouter) ...{
          'HTTP-Referer': 'https://github.com/hyphen04/spendwise',
          'X-Title': 'SpendWise',
        },
      };

  Map<String, dynamic> _body(AiConfig config, List<ChatMessage> messages,
          bool stream, int? maxTokens, {bool json = false}) =>
      openAiBodyFor(config, messages, stream,
          maxTokens: maxTokens, json: json);

  @override
  Future<String> complete(AiConfig config, List<ChatMessage> messages,
      {int? maxTokens, bool json = false}) async {
    validateConfig(config);
    final body =
        jsonEncode(_body(config, messages, false, maxTokens, json: json));
    try {
      final response = await http
          .post(_uri(config), headers: _headers(config), body: body)
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw httpStatusToException(response.statusCode, response.body);
      }
      final decoded = jsonDecode(response.body);
      final content = decoded['choices']?[0]?['message']?['content'];
      if (content is! String || content.isEmpty) {
        throw const LlmException(LlmErrorKind.parse);
      }
      return content;
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
    final body = jsonEncode(_body(config, messages, true, maxTokens));
    final client = http.Client();
    try {
      final request = http.Request('POST', _uri(config));
      request.headers.addAll(_headers(config));
      request.body = body;
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode != 200) {
        final bodyText = await response.stream.bytesToString();
        throw httpStatusToException(response.statusCode, bodyText);
      }
      // SSE: split into lines, emit each `data:` payload's delta content.
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.isEmpty) continue;
        if (!line.startsWith('data:')) continue; // skip comments/keepalives
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data);
          final delta = json['choices']?[0]?['delta']?['content'];
          if (delta is String && delta.isNotEmpty) yield delta;
        } catch (_) {
          // Skip malformed-but-continuable chunks rather than aborting.
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

/// Builds the OpenAI-compatible `/chat/completions` request body. Extracted to
/// a top-level `@visibleForTesting` function so the request shape can be
/// asserted without hitting the network.
@visibleForTesting
Map<String, dynamic> openAiBodyFor(AiConfig config, List<ChatMessage> messages,
    bool stream, {int? maxTokens, bool json = false}) {
  return {
    'model': config.model,
    'messages': messages.map((m) => m.toJson()).toList(),
    'stream': stream,
    // Keep responses tight and cheap unless the caller needs more room (report).
    'max_tokens': maxTokens ?? 1024,
    'temperature': 0.4,
    // JSON mode: ask the model for a valid JSON object. We don't pass a strict
    // json_schema (provider enforcement is uneven and some reject it); the
    // Dart SpecValidator is the source of truth.
    if (json) 'response_format': {'type': 'json_object'},
  };
}