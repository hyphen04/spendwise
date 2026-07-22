/// Whole-word, longest-first token replacement — the shared mechanic behind
/// every on-device label restore / anonymize pass.
///
/// Two passes, both opt-in so the **anonymize** direction (name → label) keeps
/// its exact, case-sensitive behavior while the **restore** direction (label
/// → name) can be more aggressive:
/// 1. **Exact** (always on, [caseInsensitive] toggles case). Every legend key is
///    matched on word boundaries (`\b`), `RegExp.escape`d, longest-first. Safe
///    on partial / streaming text: a half-arrived token like `cat_` (which is
///    not itself a key) won't match until the full `cat_0` is present.
///    Case-insensitivity (restore only) catches `Cat_0` / `CAT_0` — the LLM
///    often capitalizes a label at a sentence start.
/// 2. **Fuzzy** ([fuzzy], restore only) — a single case-insensitive regex
///    matches label-*shaped* tokens the exact pass missed: alias prefixes
///    (`cate`, `category`, `categories`, `account`, `accounts`, `bills`, …)
///    and flexible separators (`_`, `-`, space, or none). Each match is
///    canonicalized to a `prefix_N` key; if that key is in the legend it is
///    restored to the real name; otherwise it is scrubbed to a generic noun
///    ("category", "account", …) so the user never sees a raw `cate_0` /
///    `cat 0` / `cat-0` token.
///
/// Tokens are replaced longest-first in the exact pass so a longer key wins
/// over a shorter prefix (e.g. `cat_10` before `cat_1`, or `HDFC Card` before
/// `HDFC`). The fuzzy pass only runs in the restore direction, so it never
/// re-matches the labels that anonymize just inserted (those are values, not
/// keys, and the exact pass already produced them).
class LabelReplacer {
  /// Replace every key in [mapping] with its value across [text]: exact
  /// (longest-first, whole-word), then — when [fuzzy] is on — a fuzzy
  /// restore/scrub pass for malformed label tokens. A no-op on empty text.
  ///
  /// [caseInsensitive] makes the exact pass case-insensitive (restore). The
  /// fuzzy pass is itself always case-insensitive. Both default to `false` so
  /// the anonymize direction is unchanged.
  static String replace(
    String text,
    Map<String, String> mapping, {
    bool caseInsensitive = false,
    bool fuzzy = false,
  }) {
    if (text.isEmpty) return text;

    // Pass 1 — exact, longest-first, optionally case-insensitive.
    if (mapping.isNotEmpty) {
      final order = mapping.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      var out = text;
      for (final token in order) {
        if (token.isEmpty) continue;
        final re = RegExp(r'\b' + RegExp.escape(token) + r'\b',
            caseSensitive: !caseInsensitive);
        out = out.replaceAll(re, mapping[token]!);
      }
      text = out;
    }

    // Pass 2 — fuzzy malformed-label restore / scrub (restore direction only).
    if (!fuzzy) return text;
    // Real names (legend values), lowercased. A fuzzy match whose text is
    // itself a real name is ambiguous — it may be the name Pass 1 just inserted
    // OR a coincidental label reference — and leaving a real name is always
    // safe (never a raw label leak), so we skip those rather than corrupt a
    // name like "Cat11" into the holder of label cat_11.
    final valuesLower = {for (final v in mapping.values) v.toLowerCase()};
    return text.replaceAllMapped(_fuzzyLabelRe, (m) {
      final canon = _prefixAliases[m.group(1)!.toLowerCase()];
      if (canon == null) return m.group(0)!;
      final raw = m.group(0)!;
      if (valuesLower.contains(raw.toLowerCase())) return raw;
      final token = '${canon}_${m.group(2)}';
      final name = mapping[token];
      if (name != null) return name;
      // Unknown number / not in legend → scrub to the generic noun so no raw
      // label-shaped token reaches the user.
      return _entityNoun[canon] ?? token;
    });
  }

  /// Detect label-shaped tokens in [text] for the gatekeeper's flag pass.
  /// Returns each token's raw form and its canonical `prefix_N` form. Run on
  /// the **pre-restore** text: `replace` scrubs display text, so scanning post-
  /// restore would find nothing. The gatekeeper uses this to flag genuine
  /// problems (unknown / unrestorable labels) without noise for variants that
  /// were successfully restored.
  static List<LabelFinding> findLabelTokens(String text) {
    final out = <LabelFinding>[];
    if (text.isEmpty) return out;
    for (final m in _fuzzyLabelRe.allMatches(text)) {
      final canon = _prefixAliases[m.group(1)!.toLowerCase()];
      if (canon == null) continue;
      out.add((raw: m.group(0)!, canonical: '${canon}_${m.group(2)}'));
    }
    return out;
  }

  /// Alias prefixes the LLM sometimes emits in place of the canonical ones.
  /// Maps to the canonical prefix used in the legend (`cat_0`, `acc_1`, …).
  static const Map<String, String> _prefixAliases = {
    'cat': 'cat',
    'cate': 'cat',
    'category': 'cat',
    'categories': 'cat',
    'acc': 'acc',
    'account': 'acc',
    'accounts': 'acc',
    'mode': 'mode',
    'modes': 'mode',
    'goal': 'goal',
    'goals': 'goal',
    'bill': 'bill',
    'bills': 'bill',
  };

  /// Generic noun per canonical prefix, used to scrub unresolvable label-
  /// shaped tokens so the user never sees a raw `cat_0`-style token.
  static const Map<String, String> _entityNoun = {
    'cat': 'category',
    'acc': 'account',
    'mode': 'payment mode',
    'goal': 'goal',
    'bill': 'bill',
  };

  /// Matches label-shaped tokens with alias prefixes and a flexible
  /// separator (`_`, `-`, space, or none) before the index. Case-insensitive.
  /// `[\s_-]?` is optional so `cat_0`, `cat-0`, `cat 0`, and (rare) `cat0` all
  /// match. Word boundaries anchor the prefix start and the digit end.
  static final RegExp _fuzzyLabelRe = RegExp(
    r'\b(cat|cate|category|categories|acc|account|accounts|mode|modes|goal|goals|bill|bills)[\s_-]?(\d+)\b',
    caseSensitive: false,
  );
}

/// One detected label-shaped token: its raw text in the reply and its
/// canonical `prefix_N` form (the key the gatekeeper checks against the legend).
typedef LabelFinding = ({String raw, String canonical});