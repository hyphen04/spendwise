/// Whole-word, longest-first token replacement — the shared mechanic behind
/// every on-device label restore / anonymize pass.
///
/// Tokens are replaced in **longest-first** order so that a longer key wins
/// over a shorter prefix (e.g. `cat_10` before `cat_1`, or `HDFC Card` before
/// `HDFC`). Each token is matched on **word boundaries** (`\b`) and is
/// `RegExp.escape`d, so replacement is safe to run on partial / streaming text:
/// a half-arrived token like `cat_` (which is not itself a key) won't match
/// until the full `cat_0` token is present.
class LabelReplacer {
  /// Replace every key in [mapping] with its value across [text], longest key
  /// first, whole-word only. A no-op when [mapping] is empty.
  static String replace(String text, Map<String, String> mapping) {
    if (mapping.isEmpty || text.isEmpty) return text;
    final order = mapping.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var out = text;
    for (final token in order) {
      if (token.isEmpty) continue;
      final re = RegExp(r'\b' + RegExp.escape(token) + r'\b');
      out = out.replaceAll(re, mapping[token]!);
    }
    return out;
  }
}