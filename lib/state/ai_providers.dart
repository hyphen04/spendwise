import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/repositories/ai_chat_repository.dart';
import '../features/ai/domain/ai_config.dart';
import '../features/ai/domain/ai_report_data.dart';
import '../features/ai/domain/llm_client.dart';
import '../services/secure_storage_service.dart';
import 'database_provider.dart'; // appDatabaseProvider
import 'home_providers.dart'; // budgetsRepositoryProvider, budgetsStreamProvider
import 'prefs_providers.dart'; // prefsServiceProvider
import 'reports_providers.dart'; // reportsRepositoryProvider
import 'transactions_providers.dart'; // allTransactionsStreamProvider

// ── AI Copilot config + key (Phase 2) ─────────────────────────────────────
//
// Non-secret config lives in SharedPreferences (via PrefsService →
// prefs_providers). The API key lives in SecureStorageService and is read
// on demand — it is intentionally NOT held in long-lived Riverpod state so a
// stale key can never be reused after the user clears it.

final aiEnabledProvider =
    StateNotifierProvider<AiEnabledNotifier, bool>(
        (ref) => AiEnabledNotifier(ref.watch(prefsServiceProvider)));

class AiEnabledNotifier extends StateNotifier<bool> {
  AiEnabledNotifier(this._prefs) : super(_prefs.aiEnabled);
  final PrefsService _prefs;
  Future<void> set(bool v) async {
    await _prefs.setAiEnabled(v);
    state = v;
  }
}

final aiShareNamesProvider =
    StateNotifierProvider<AiShareNamesNotifier, bool>(
        (ref) => AiShareNamesNotifier(ref.watch(prefsServiceProvider)));

class AiShareNamesNotifier extends StateNotifier<bool> {
  AiShareNamesNotifier(this._prefs) : super(_prefs.aiShareNames);
  final PrefsService _prefs;
  Future<void> set(bool v) async {
    await _prefs.setAiShareNames(v);
    state = v;
  }
}

/// Whether the AI Report may propose its own chart layout (LLM emits a chart
/// spec). Off by default; the report uses a safe fixed default spec otherwise.
final aiSpecEnabledProvider =
    StateNotifierProvider<AiSpecEnabledNotifier, bool>(
        (ref) => AiSpecEnabledNotifier(ref.watch(prefsServiceProvider)));

class AiSpecEnabledNotifier extends StateNotifier<bool> {
  AiSpecEnabledNotifier(this._prefs) : super(_prefs.aiSpecEnabled);
  final PrefsService _prefs;
  Future<void> set(bool v) async {
    await _prefs.setAiSpecEnabled(v);
    state = v;
  }
}

/// Whether the AI may author read-only SQL (the opt-in `customSql` provider),
/// gated by the [SqlGuard] safety pipeline. Off by default.
final aiCustomSqlProvider =
    StateNotifierProvider<AiCustomSqlNotifier, bool>(
        (ref) => AiCustomSqlNotifier(ref.watch(prefsServiceProvider)));

class AiCustomSqlNotifier extends StateNotifier<bool> {
  AiCustomSqlNotifier(this._prefs) : super(_prefs.aiCustomSql);
  final PrefsService _prefs;
  Future<void> set(bool v) async {
    await _prefs.setAiCustomSql(v);
    state = v;
  }
}

/// Whether the AI Copilot chat may call on-device lookup tools. On by default
/// (privacy-safe — aggregates only). See [PrefsService.aiToolCalling].
final aiToolCallingProvider =
    StateNotifierProvider<AiToolCallingNotifier, bool>(
        (ref) => AiToolCallingNotifier(ref.watch(prefsServiceProvider)));

class AiToolCallingNotifier extends StateNotifier<bool> {
  AiToolCallingNotifier(this._prefs) : super(_prefs.aiToolCalling);
  final PrefsService _prefs;
  Future<void> set(bool v) async {
    await _prefs.setAiToolCalling(v);
    state = v;
  }
}

/// Resolved (non-secret) AI config from the prefs-stored provider/base/model.
/// Watches [aiShareNamesProvider] so flipping the "Share names" toggle takes
/// effect immediately (the toggle's notifier updates prefs + state; this
/// provider recomputes). `shareNames` is the only prefs-backed AI field with a
/// dedicated reactive notifier — the provider/model/base-URL settings are
/// pulled from [prefsServiceProvider] and invalidated explicitly by their
/// sheets when they change.
final aiConfigProvider = Provider<AiConfig>((ref) {
  final prefs = ref.watch(prefsServiceProvider);
  final shareNames = ref.watch(aiShareNamesProvider); // reactive to the toggle
  final preset = LlmProviderPreset.byId(prefs.aiProvider);
  return AiConfig(
    preset: preset,
    baseUrlOverride: prefs.aiBaseUrl,
    modelOverride: prefs.aiModel,
    shareNames: shareNames,
  );
});

/// Whether a key is present in secure storage (drives UI gating). Reactive to
/// an invalidating [aiKeyVersionProvider] bump so a save/clear is reflected.
final aiKeyVersionProvider = StateProvider<int>((_) => 0);

final aiHasApiKeyProvider = FutureProvider<bool>((ref) async {
  ref.watch(aiKeyVersionProvider); // re-check after save/clear
  return SecureStorageService.hasLlmKey();
});

/// Loads the key from secure storage and returns a fully-populated [AiConfig]
/// ready to pass to a [LlmClient]. Returns null if no key is set.
Future<AiConfig?> aiConfigWithKey(Ref ref) async {
  final config = ref.read(aiConfigProvider);
  final key = await SecureStorageService.readLlmKey();
  if (key == null || key.trim().isEmpty) return null;
  return AiConfig(
    preset: config.preset,
    baseUrlOverride: config.baseUrlOverride,
    modelOverride: config.modelOverride,
    shareNames: config.shareNames,
    apiKey: key.trim(),
  );
}

/// Provider that resolves the live [LlmClient] implementation for the current
/// config, or null when not configured. The API key is fetched on demand by
/// callers (see [aiConfigWithKey]) so it is never held here.
final aiClientProvider = Provider<LlmClient>((ref) {
  final config = ref.watch(aiConfigProvider);
  return LlmClient.forConfig(config);
});

/// Sends a trivial completion to verify the configured key + model work.
/// Returns null on success, or an [LlmException] describing the failure.
final aiTestConnectionProvider =
    FutureProvider.family<LlmException?, void>((ref, _) async {
  final config = await aiConfigWithKey(ref);
  if (config == null) return const LlmException(LlmErrorKind.noKey);
  try {
    await ref.read(aiClientProvider).complete(
          config,
          const [
            ChatMessage(role: 'system', content: 'Reply with the single word: ok'),
            ChatMessage(role: 'user', content: 'ok'),
          ],
        );
    return null; // success
  } on LlmException catch (e) {
    return e;
  } catch (e) {
    return LlmException(LlmErrorKind.parse, e.toString());
  }
});

// ── AI Copilot chat history (threads + messages) ──────────────────────────

final aiChatRepositoryProvider = Provider<AiChatRepository>(
    (ref) => AiChatRepository(ref.watch(appDatabaseProvider)));

/// All chat threads, most-recently-active first (for the chat list screen).
final aiThreadsStreamProvider =
    StreamProvider<List<AiThread>>((ref) =>
        ref.watch(aiChatRepositoryProvider).watchThreads());

/// A single thread (for the chat screen's AppBar title, which may be renamed).
final aiThreadStreamProvider =
    StreamProvider.family<AiThread?, String>(
        (ref, id) => ref.watch(aiChatRepositoryProvider).watchThread(id));

/// Distinct chat folder names (alpha-sorted) for the chat list filter chips.
final aiFoldersStreamProvider =
    StreamProvider<List<String>>((ref) =>
        ref.watch(aiChatRepositoryProvider).watchFolders());

// ── AI Report on-device data (Phase 4 visuals + gatekeeper parity) ──────────

/// The month's real aggregations, gathered once and consumed by BOTH the
/// report screen's charts (always-on, no AI/key needed) and
/// [AiReportNotifier] (which feeds them to [AiPayloadBuilder] so the AI
/// narrative is written from the same figures the charts show). Keyed by
/// `(year, month)`; reactive to transaction changes.
final aiReportDataProvider =
    FutureProvider.family<AiReportData, (int, int)>((ref, args) async {
  ref.watch(allTransactionsStreamProvider); // re-run on tx changes
  final repo = ref.read(reportsRepositoryProvider);
  final budgetsRepo = ref.read(budgetsRepositoryProvider);
  final monthDate = DateTime(args.$1, args.$2);

  final summary = await repo.monthlySummary(args.$1, args.$2);
  final budgets = await budgetsRepo.progressForMonth(monthDate);
  final cashflow = await repo.cashFlowMonths();
  final from = monthDate.toIso8601String();
  final to = DateTime(args.$1, args.$2 + 1).toIso8601String();
  final topCats = await repo.topSpends(from: from, to: to, limit: 10);
  final modes = await repo.modeBreakdown(from: from, to: to, kind: 'expense');

  return (
    summary: summary,
    budgets: budgets,
    cashflow: cashflow,
    topExpenseCategories: topCats,
    modes: modes,
  );
});
