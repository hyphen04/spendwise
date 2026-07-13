import 'dart:convert';

/// A parsed tool-call from an LLM reply: the tool name + its args map.
class AiToolCall {
  const AiToolCall({required this.tool, required this.args});
  final String tool;
  final Map<String, Object?> args;
}

/// The result of parsing an LLM reply. Either it is a tool-call
/// ([isToolCall] true, [call] set) or the final answer ([text] holds the raw
/// reply to render). The parser is forgiving: any decode failure or missing
/// `tool` key degrades to "final answer" rather than throwing — so a malformed
/// reply never blocks the user.
class AiToolParseResult {
  const AiToolParseResult({this.call, required this.text});
  final AiToolCall? call;
  final String text;
  bool get isToolCall => call != null;
}

/// Provider-agnostic JSON tool-call protocol. The LLM is told (in the system
/// prompt) to either answer in plain text or reply with **only** a JSON object
/// `{"tool": "<name>", "args": {…}}`. This class parses that.
class AiToolProtocol {
  const AiToolProtocol._();

  /// Parse [reply]. Strips a leading ```json / ``` fence if present, finds the
  /// first `{...}` object, and decodes it. A tool-call requires a `tool` field
  /// that is a non-empty string; `args` defaults to an empty map. Anything else
  /// (no JSON, malformed JSON, JSON without `tool`) is treated as the final
  /// answer.
  static AiToolParseResult parse(String reply) {
    final stripped = _stripFence(reply);
    final obj = _firstJsonObject(stripped);
    if (obj == null) return AiToolParseResult(text: reply);
    final tool = obj['tool'];
    if (tool is! String || tool.trim().isEmpty) {
      return AiToolParseResult(text: reply);
    }
    final args = obj['args'];
    final argMap = args is Map ? Map<String, Object?>.from(args) : const <String, Object?>{};
    return AiToolParseResult(call: AiToolCall(tool: tool.trim(), args: argMap), text: reply);
  }

  static String _stripFence(String s) {
    final trimmed = s.trim();
    if (trimmed.startsWith('```')) {
      // Drop the opening fence (```json or ```) and a trailing ```.
      final withoutOpen = trimmed.replaceFirst(RegExp(r'^```[a-zA-Z]*\n'), '');
      return withoutOpen.replaceFirst(RegExp(r'```\s*$'), '').trim();
    }
    return trimmed;
  }

  /// Find and decode the first balanced `{...}` object in [s], or null.
  static Map<String, Object?>? _firstJsonObject(String s) {
    final start = s.indexOf('{');
    if (start < 0) return null;
    int depth = 0;
    bool inStr = false;
    String? esc;
    for (int i = start; i < s.length; i++) {
      final ch = s[i];
      if (inStr) {
        if (esc == '\\') {
          esc = null;
        } else if (ch == '\\') {
          esc = '\\';
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          final slice = s.substring(start, i + 1);
          try {
            final decoded = jsonDecode(slice);
            if (decoded is Map) return Map<String, Object?>.from(decoded);
            return null;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }
}

/// One-line nudge appended when a reply looked tool-ish but didn't parse, to
/// give the LLM one chance to self-correct before treating the reply as final.
const String kToolRetryNudge =
    'Respond with only the JSON tool-call object ({"tool": "...", "args": {...}}), '
    'or your final answer in plain text.';