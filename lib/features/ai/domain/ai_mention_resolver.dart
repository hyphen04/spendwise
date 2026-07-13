import '../../../app/utils/money_format.dart';

/// An entity the user can refer to by name — `(id, name)`. The directory of
/// these is gathered on-device (see `gatherAiMentionData`) and is **never sent**
/// to the LLM; only names the user *themselves typed* can appear in a hint, and
/// only because the user already put them in their own message.
typedef AiEntityName = ({String id, String name});

/// The kind of entity a mention resolved to. Mirrors the opaque-label prefixes
/// the payload uses (`cat_`/`acc_`/`mode_`/`tag_`).
enum AiMentionKind { category, account, mode, tag }

/// The on-device directory + current-month figures used to resolve the user's
/// real-name mentions. Everything here stays on-device; the resolver emits only
/// a hint that re-uses names the user already typed plus aggregate amounts.
class AiMentionData {
  const AiMentionData({
    required this.categories,
    required this.accounts,
    required this.modes,
    required this.tags,
    required this.categoryAmount,
    required this.modeAmount,
    required this.tagAmount,
    required this.accountBalance,
  });

  /// All active categories/accounts/modes/tags as `(id, name)`.
  final List<AiEntityName> categories;
  final List<AiEntityName> accounts;
  final List<AiEntityName> modes;
  final List<AiEntityName> tags;

  /// Current-month spend per entity id (0 for entities with no activity — they
  /// are simply absent from these maps). `accountBalance` is the live balance.
  final Map<String, double> categoryAmount;
  final Map<String, double> modeAmount;
  final Map<String, double> tagAmount;
  final Map<String, double> accountBalance;

  static const empty = AiMentionData(
    categories: [],
    accounts: [],
    modes: [],
    tags: [],
    categoryAmount: {},
    modeAmount: {},
    tagAmount: {},
    accountBalance: {},
  );
}

/// Result of resolving the mentions in one user message.
class AiMentionResolution {
  const AiMentionResolution({
    required this.hint,
    required this.amounts,
    required this.matchedNames,
  });

  /// The `[Context note: …]` block to append to the user message **as sent to
  /// the LLM only** (never persisted, never shown in the UI). Empty when the
  /// message mentions no known entity.
  final String hint;

  /// The figures introduced by the hint, to merge into the gatekeeper's
  /// `sentAmounts` so a reply that quotes them isn't flagged as hallucinated.
  final Set<double> amounts;

  /// The canonical real names the user mentioned (on-device only — used to
  /// extend `sentNameVocabulary` in `shareNames` mode so a reply that uses a
  /// mentioned-but-not-top-5 name isn't flagged as invented).
  final List<String> matchedNames;

  bool get hasMentions => hint.isNotEmpty;
}

/// Resolves the real entity names a user types in their question to the
/// anonymized labels / figures the LLM holds — **on-device, without leaking the
/// legend.**
///
/// The privacy contract: the LLM sees categories as `cat_0..cat_N` (no names,
/// unless `shareNames` is on). So when the user asks "tell me about fuel", the
/// LLM cannot map "fuel" to any `cat_N` and wrongly claims no such category
/// exists. This resolver bridges that gap by scanning the user's *own* message
/// for names that match the on-device directory, then emitting a `[Context note]`
/// that ties the name the user already typed to its label (when the label is in
/// the context) and its current-month amount. No name the user did **not** type
/// is ever put in the hint — the legend for unmentioned entities never leaves.
///
/// Pure Dart, no Flutter, no IO — unit-testable in isolation.
class AiMentionResolver {
  AiMentionResolver({
    required this.data,
    required this.legend,
  });

  /// On-device entity directory + current-month figures (never sent wholesale).
  final AiMentionData data;

  /// `label → real name`, as built by `AiPayloadBuilder` (the on-device legend).
  /// Used to map a mentioned name to the *exact label token* the LLM received,
  /// when that entity is in the context. Inverted locally; never sent.
  final Map<String, String> legend;

  /// Resolve every known entity name mentioned in [userMessage]. Names are
  /// matched case-insensitively on word boundaries, longest name first (so
  /// "Food & Dining" wins over "Food"), and each distinct name resolves once.
  /// When a name matches several kinds, category > account > mode > tag.
  AiMentionResolution resolve(String userMessage) {
    if (userMessage.trim().isEmpty) {
      return const AiMentionResolution(
          hint: '', amounts: {}, matchedNames: []);
    }
    final lower = userMessage.toLowerCase();

    // (kind, id, name) candidates, longest name first, stable within a kind.
    final candidates = <_Candidate>[];
    for (final c in data.categories) {
      candidates.add(_Candidate(AiMentionKind.category, c.id, c.name));
    }
    for (final a in data.accounts) {
      candidates.add(_Candidate(AiMentionKind.account, a.id, a.name));
    }
    for (final m in data.modes) {
      candidates.add(_Candidate(AiMentionKind.mode, m.id, m.name));
    }
    for (final t in data.tags) {
      candidates.add(_Candidate(AiMentionKind.tag, t.id, t.name));
    }
    // Longest name first; prefer category > account > mode > tag on ties.
    candidates.sort((a, b) {
      final byLen = b.name.length.compareTo(a.name.length);
      if (byLen != 0) return byLen;
      return a.kind.index.compareTo(b.kind.index);
    });

    final matched = <String>{}; // lowercased names already matched
    // Spans (start, end) of accepted matches, so a shorter name that sits inside
    // an already-matched longer name (e.g. "Food" within "Food & Dining") is
    // skipped rather than double-matched.
    final spans = <(int, int)>[];
    final notes = <String>[];
    final amounts = <double>{};
    final names = <String>[];

    for (final c in candidates) {
      if (c.name.length < 3) continue;
      final nameLower = c.name.toLowerCase();
      if (matched.contains(nameLower)) continue;
      final escaped = RegExp.escape(nameLower);
      final re = RegExp('(^|\\W)$escaped(\\W|\$)', caseSensitive: false);
      final m = re.firstMatch(lower);
      if (m == null) continue;
      // The needle itself starts after the leading boundary group.
      final lead = m.group(1)!.length;
      final start = m.start + lead;
      final end = start + nameLower.length;
      if (spans.any((s) => start < s.$2 && end > s.$1)) continue;
      matched.add(nameLower);
      spans.add((start, end));

      final label = _labelForName(nameLower);
      final note = _noteFor(c, label);
      if (note != null) {
        notes.add(note);
        names.add(c.name);
        final amt = _amountFor(c);
        if (amt != null) amounts.add(amt);
      }
    }

    if (notes.isEmpty) {
      return const AiMentionResolution(
          hint: '', amounts: {}, matchedNames: []);
    }
    final hint = '\n\n[Context note: ${notes.join(' ')}]';
    return AiMentionResolution(
        hint: hint, amounts: amounts, matchedNames: names);
  }

  /// The opaque label the LLM received for [nameLower], if any. Inverts the
  /// on-device legend by value (case-insensitive).
  String? _labelForName(String nameLower) {
    for (final entry in legend.entries) {
      if (entry.value.toLowerCase() == nameLower) return entry.key;
    }
    return null;
  }

  /// The current-month figure for [c], if the kind carries one we can quote.
  double? _amountFor(_Candidate c) {
    switch (c.kind) {
      case AiMentionKind.category:
        return data.categoryAmount[c.id] ?? 0.0;
      case AiMentionKind.account:
        return data.accountBalance[c.id] ?? 0.0;
      case AiMentionKind.mode:
        return data.modeAmount[c.id] ?? 0.0;
      case AiMentionKind.tag:
        return data.tagAmount[c.id] ?? 0.0;
    }
  }

  /// Builds the single-sentence note for a matched entity. Quotes the real name
  /// the user typed, the label when it is in the context, and the figure.
  String? _noteFor(_Candidate c, String? label) {
    final amt = _amountFor(c);
    switch (c.kind) {
      case AiMentionKind.category:
        final spent = _fmt(amt ?? 0.0);
        if (label != null) {
          return '"${c.name}" refers to category $label '
              '(spent $spent this month).';
        }
        return '"${c.name}" is one of your categories '
            '(spent $spent this month; not in your top spending list).';
      case AiMentionKind.account:
        final bal = _fmt(amt ?? 0.0);
        if (label != null) {
          return '"${c.name}" refers to account $label (balance $bal).';
        }
        return '"${c.name}" is one of your accounts (balance $bal).';
      case AiMentionKind.mode:
        final spent = _fmt(amt ?? 0.0);
        if (label != null) {
          return '"${c.name}" refers to payment mode $label '
              '(spent $spent this month).';
        }
        return '"${c.name}" is one of your payment modes '
            '(spent $spent this month).';
      case AiMentionKind.tag:
        final spent = _fmt(amt ?? 0.0);
        if (label != null) {
          return '"${c.name}" refers to tag $label '
              '(spent $spent this month).';
        }
        return '"${c.name}" is one of your tags '
            '(spent $spent this month).';
    }
  }

  /// Format a figure the way the payload does (plain grouped number), so the
  /// gatekeeper's number regex can match it when it appears in the reply.
  String _fmt(double v) => fmtNumber(v);
}

class _Candidate {
  const _Candidate(this.kind, this.id, this.name);
  final AiMentionKind kind;
  final String id;
  final String name;
}