import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/ai/domain/ai_model.dart';
import '../features/ai/domain/llm_client.dart';
import '../features/ai/domain/model_catalog.dart';
import 'ai_providers.dart';

/// State of the model-picker sheet.
enum ModelBrowserStatus { idle, loading, loaded, error, manual }

/// The picker's view state. `visible` is the current page (slice) of the
/// filtered list; `hasMore` is true when more filtered items remain to reveal.
class ModelBrowserState {
  const ModelBrowserState({
    this.status = ModelBrowserStatus.idle,
    this.visible = const [],
    this.totalFiltered = 0,
    this.query = '',
    this.hasMore = false,
    this.error,
  });

  final ModelBrowserStatus status;
  final List<AiModel> visible;

  /// Size of the full filtered list (after applying [query]). Used by the
  /// "Load more" affordance to show an accurate "remaining" count.
  final int totalFiltered;

  final String query;
  final bool hasMore;
  final String? error;

  ModelBrowserState copyWith({
    ModelBrowserStatus? status,
    List<AiModel>? visible,
    int? totalFiltered,
    String? query,
    bool? hasMore,
    String? error,
  }) =>
      ModelBrowserState(
        status: status ?? this.status,
        visible: visible ?? this.visible,
        totalFiltered: totalFiltered ?? this.totalFiltered,
        query: query ?? this.query,
        hasMore: hasMore ?? this.hasMore,
        error: error,
      );
}

/// Backs the model-picker sheet.
///
/// Fetches the provider's model list once via [ModelCatalog], caches it for the
/// sheet's lifetime (so search + "show more" never re-hit the network), and
/// paginates + filters on the client. The API key is resolved on demand via
/// [aiConfigWithKey] and lives only in the local `config` var during the fetch
/// — it is never stored here (the cached `_all` list is public model metadata,
/// no keys).
class ModelBrowserNotifier extends StateNotifier<ModelBrowserState> {
  ModelBrowserNotifier(this._ref) : super(const ModelBrowserState());
  final Ref _ref;

  static const int _pageSize = 40;

  /// Cached full list for the current provider (public metadata, no key).
  List<AiModel> _all = [];
  List<AiModel> _filtered = [];
  int _visibleCount = _pageSize;
  String? _lastProviderId;

  /// Load the list for the current provider. Re-fetches only when the provider
  /// changed or the cache is empty (so re-opening the sheet is instant). Pass
  /// [force] to bypass the cache (used by the retry button).
  Future<void> open({bool force = false}) async {
    final keyless = _ref.read(aiConfigProvider);
    final providerId = keyless.preset.id;
    if (!force &&
        _lastProviderId == providerId &&
        _all.isNotEmpty &&
        state.status != ModelBrowserStatus.error) {
      // Cache is valid for this provider — re-render the full list. Clear any
      // stale search query left from a previous open (the provider survives
      // across opens) so the sheet always starts showing all models, with the
      // selected one pinned to the top.
      state = state.copyWith(query: '');
      _applyQuery();
      return;
    }
    state = state.copyWith(
      status: ModelBrowserStatus.loading,
      visible: const [],
      totalFiltered: 0,
      query: '',
      hasMore: false,
      error: null,
    );
    // Key present → keyed config (auth); absent → keyless config (OpenRouter's
    // /models is public; OpenAI/Groq/Gemini will 401 → actionable error).
    final config =
        (await aiConfigWithKey(_ref)) ?? keyless;
    try {
      _all = await ModelCatalog().listModels(config);
      _lastProviderId = providerId;
      _applyQuery();
    } on ModelListUnavailable {
      // Custom provider with no list endpoint → manual entry, not an error.
      _lastProviderId = providerId;
      state = state.copyWith(status: ModelBrowserStatus.manual, error: null);
    } on LlmException catch (e) {
      state = state.copyWith(
        status: ModelBrowserStatus.error,
        error: e.userMessage,
      );
    }
  }

  /// Filter the cached list by [q] (id + label, case-insensitive) and reset to
  /// the first page. No network — instant.
  void setQuery(String q) {
    state = state.copyWith(query: q);
    if (_all.isEmpty) return; // nothing loaded yet; query is recorded for later.
    _applyQuery();
  }

  void loadMore() {
    if (!state.hasMore) return;
    _visibleCount += _pageSize;
    state = state.copyWith(
      visible: _filtered.take(_visibleCount).toList(),
      totalFiltered: _filtered.length,
      hasMore: _filtered.length > _visibleCount,
    );
  }

  /// Force a re-fetch (retry button).
  Future<void> retry() => open(force: true);

  void _applyQuery() {
    final q = state.query.trim().toLowerCase();
    final List<AiModel> filtered;
    if (q.isEmpty) {
      // Full list: pin the currently-selected model to the top so the user
      // immediately sees what's active, then the rest in alphabetical order.
      final current = _ref.read(aiConfigProvider).model;
      if (current.isNotEmpty) {
        final selected = _all.where((m) => m.id == current).toList();
        final rest = _all.where((m) => m.id != current).toList();
        filtered = [...selected, ...rest];
      } else {
        filtered = _all.toList();
      }
    } else {
      filtered = _all
          .where((m) =>
              m.id.toLowerCase().contains(q) ||
              (m.label?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    _filtered = filtered;
    _visibleCount = _pageSize;
    state = state.copyWith(
      status: ModelBrowserStatus.loaded,
      visible: _filtered.take(_visibleCount).toList(),
      totalFiltered: _filtered.length,
      hasMore: _filtered.length > _visibleCount,
      error: null,
    );
  }
}

/// Non-autoDispose so the fetched list survives opening/closing the sheet
/// within a session (OpenRouter's list is large; avoid refetching per open).
/// `open()` re-fetches only when the provider changes or the cache is empty.
final modelBrowserProvider =
    StateNotifierProvider<ModelBrowserNotifier, ModelBrowserState>(
        (ref) => ModelBrowserNotifier(ref));