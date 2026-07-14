import 'dart:convert';

import '../domain/ai_config.dart';
import '../domain/ai_gatekeeper.dart';
import '../domain/llm_client.dart';
import 'ai_tool_executor.dart';
import 'ai_tool_protocol.dart';

typedef AiGatekeeperBuilder = AiGatekeeper Function(
    Set<double> extraAmounts, Set<String> extraNames);

/// Runs the buffered tool-use round loop for one user question. Pure-ish: takes
/// an [LlmClient] (so a fake can script rounds in tests) and an [AiToolExecutor].
/// Every round is non-streaming ([LlmClient.complete]) — the full reply must be
/// in hand to decide tool-call vs final answer, and streaming an internal
/// tool-call JSON to the user would leak the protocol.
///
/// Round: request completion → if [AiToolProtocol.parse] yields a tool-call,
/// execute it via [executor], append the tool-call + an anonymized `tool_result`
/// message, merge the emitted amounts/names into the gatekeeper, call
/// [onStatus] ("Looking up your data…"), and loop (≤ [maxRounds]). On a
/// non-tool-call reply: restore + check via the gatekeeper and return. On
/// reaching [maxRounds]: append an "answer now" instruction and force one final
/// completion, treating its reply as the final answer.
class AiToolRunner {
  AiToolRunner({
    required this.client,
    required this.config,
    required this.executor,
    required this.gatekeeperBuilder,
    required this.onStatus,
    this.maxRounds = 4,
  });

  final LlmClient client;
  final AiConfig config;
  final AiToolExecutor executor;
  final AiGatekeeperBuilder gatekeeperBuilder;
  final void Function(String status) onStatus;
  final int maxRounds;

  Future<({String content, AiCheckResult check})> run({
    required List<ChatMessage> preamble,
    required List<ChatMessage> history,
  }) async {
    final messages = <ChatMessage>[...preamble, ...history];
    Set<double> extraAmounts = const <double>{};
    Set<String> extraNames = const <String>{};

    for (int round = 0; round < maxRounds; round++) {
      final reply = await client.complete(config, messages, maxTokens: 1024);
      final parsed = AiToolProtocol.parse(reply);
      if (!parsed.isToolCall) {
        return _finalize(reply, extraAmounts, extraNames);
      }
      // Tool round.
      onStatus('Looking up your data…');
      final result =
          await executor.execute(parsed.call!.tool, parsed.call!.args);
      extraAmounts = {...extraAmounts, ...result.amounts};
      extraNames = {...extraNames, ...result.names};
      // Append the assistant tool-call (so the LLM sees its own call) + the
      // tool_result as a user message (provider-safe role — some providers
      // reject a 'tool' role).
      messages.add(ChatMessage(role: 'assistant', content: reply));
      messages.add(ChatMessage(
        role: 'user',
        content: '[Tool result for ${parsed.call!.tool}]: '
            '${const JsonEncoder.withIndent('  ').convert(result.body)}\n'
            'Now answer the user using this data, or call another tool if needed.',
      ));
    }

    // Maxed out → force a final answer.
    onStatus('Looking up your data…');
    messages.add(const ChatMessage(
      role: 'user',
      content: 'Answer the user now using the data you have. '
          'Do not call another tool.',
    ));
    final reply = await client.complete(config, messages, maxTokens: 1024);
    return _finalize(reply, extraAmounts, extraNames);
  }

  ({String content, AiCheckResult check}) _finalize(
      String reply, Set<double> extraAmounts, Set<String> extraNames) {
    final gatekeeper = gatekeeperBuilder(extraAmounts, extraNames);
    final restored = gatekeeper.restore(reply);
    return (content: restored, check: gatekeeper.check(restored));
  }
}