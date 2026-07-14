import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/budgets_repository.dart';
import 'package:spendwise/data/repositories/reports_repository.dart';
import 'package:spendwise/features/ai/domain/ai_config.dart';
import 'package:spendwise/features/ai/domain/ai_gatekeeper.dart';
import 'package:spendwise/features/ai/domain/ai_mention_resolver.dart';
import 'package:spendwise/features/ai/domain/ai_payload_builder.dart';
import 'package:spendwise/features/ai/domain/llm_client.dart';
import 'package:spendwise/features/ai/tools/ai_tool_executor.dart';
import 'package:spendwise/features/ai/tools/ai_tool_runner.dart';

/// A fake client that returns scripted replies in order, recording every call.
class _FakeClient implements LlmClient {
  _FakeClient(this.replies);
  final List<String> replies;
  final List<List<ChatMessage>> calls = [];
  int _i = 0;
  @override
  Future<String> complete(AiConfig config, List<ChatMessage> messages,
      {int? maxTokens, bool json = false}) async {
    calls.add(messages);
    final reply = replies[_i < replies.length ? _i : replies.length - 1];
    _i++;
    return reply;
  }

  @override
  Stream<String> stream(AiConfig config, List<ChatMessage> messages,
      {int? maxTokens}) async* {
    yield await complete(config, messages, maxTokens: maxTokens);
  }
}

AiConfig get _config => AiConfig(preset: LlmProviderPreset.all.first);

/// Builds an executor backed by a tiny in-memory database. The no-tool tests
/// never call `execute`, but using real repos (instead of `null as dynamic`)
/// keeps the analyzer clean and mirrors Task 5's setUp.
AiToolExecutor _executor({
  List<GoalSummary> goals = const [],
  List<BillSummary> bills = const [],
  Map<String, String> labelToId = const {},
  bool shareNames = false,
}) {
  final db = AppDatabase(NativeDatabase.memory());
  final reports = ReportsRepository(db);
  final budgets = BudgetsRepository(db);
  return AiToolExecutor(
    reports: reports,
    budgets: budgets,
    directory: AiMentionData(
      categories: const [],
      accounts: const [],
      modes: const [],
      tags: const [],
      categoryAmount: const {},
      modeAmount: const {},
      tagAmount: const {},
      accountBalance: const {},
    ),
    goals: goals,
    bills: bills,
    labelToId: labelToId,
    shareNames: shareNames,
  );
}

void main() {
  test('a non-tool-call first reply is the final answer (no tool round)', () async {
    final client = _FakeClient(['You spent 3000 on Food.']);
    final runner = AiToolRunner(
      client: client,
      config: _config,
      executor: _executor(),
      gatekeeperBuilder: (a, n) =>
          AiGatekeeper(legend: const {}, validLabels: const {}, sentAmounts: a),
      onStatus: (_) {},
    );
    final res = await runner.run(
      preamble: const [ChatMessage(role: 'system', content: 'sys')],
      history: const [ChatMessage(role: 'user', content: 'how much on Food?')],
    );
    expect(client.calls.length, 1);
    expect(res.content, 'You spent 3000 on Food.');
    expect(res.check.severity, AiCheckSeverity.ok);
  });

  test('a tool-call then a final answer runs two rounds and feeds the result back',
      () async {
    final client = _FakeClient([
      '{"tool":"goals_overview","args":{}}',
      'Your goal is 25% funded.',
    ]);
    final executor = _executor(
      goals: const [
        (id: 'g1', name: 'Phone', target: 60000, saved: 15000,
            monthsLeft: 10, monthlyCommitment: 4500)
      ],
      labelToId: const {'goal_0': 'g1'},
    );
    final statuses = <String>[];
    final runner = AiToolRunner(
      client: client,
      config: _config,
      executor: executor,
      gatekeeperBuilder: (a, n) => AiGatekeeper(
          legend: const {}, validLabels: const {'goal_0'}, sentAmounts: a),
      onStatus: statuses.add,
    );
    final res = await runner.run(
      preamble: const [ChatMessage(role: 'system', content: 'sys')],
      history: const [ChatMessage(role: 'user', content: 'how is my goal?')],
    );
    expect(client.calls.length, 2);
    // The second call's messages include the tool_result.
    final second = client.calls[1];
    expect(second.any((m) => m.content.contains('Tool result')), isTrue);
    expect(statuses, contains('Looking up your data…'));
    expect(res.content, 'Your goal is 25% funded.');
  });

  test('max rounds forces a final answer', () async {
    // Always replies with a tool-call → after maxRounds the runner forces one.
    final client = _FakeClient(['{"tool":"goals_overview","args":{}}']);
    final runner = AiToolRunner(
      client: client,
      config: _config,
      executor: _executor(),
      gatekeeperBuilder: (a, n) =>
          AiGatekeeper(legend: const {}, validLabels: const {}, sentAmounts: a),
      onStatus: (_) {},
      maxRounds: 2,
    );
    final res = await runner.run(
      preamble: const [ChatMessage(role: 'system', content: 'sys')],
      history: const [ChatMessage(role: 'user', content: 'go')],
    );
    // The last call carries the "answer now" instruction and the reply (still a
    // tool-call) is treated as the final answer text rather than looping forever.
    expect(res.content, contains('tool'));
  });
}