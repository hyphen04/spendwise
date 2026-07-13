import 'label_replacer.dart';

/// Outcome of validating an AI reply on-device.
typedef AiCheckResult = ({List<String> issues, AiCheckSeverity severity});

/// How much the gatekeeper trusts the reply.
enum AiCheckSeverity {
  /// Clean — restore applied, no problems found.
  ok,

  /// Restored + usable, but something looked off (leftover/invented label,
  /// leaked-PII-looking token, a wildly out-of-range number, a figure that
  /// doesn't match anything sent, or an unknown name when names were shared).
  /// The UI shows a small "Checked on-device" note but keeps the text.
  flagged,

  /// Empty or garbage — the UI should hide the reply and show an error + Retry.
  bad,
}

/// The on-device warden for AI replies. It is the **only** layer that touches
/// LLM output before it reaches the user: it restores opaque labels to real
/// names (using a legend that never left the device) and checks the reply for
/// missing/problematic content.
///
/// Pure Dart, no Flutter, no IO — unit-testable in isolation. [restore] is safe
/// to run on partial / streaming text (see [LabelReplacer]).
///
/// The constructor accepts the figures and (optionally) the real-name
/// vocabulary that were sent to the LLM, so [check] can do two extra passes:
/// a **numeric-correspondence** check (flag currency-ish numbers in the reply
/// that neither match a sent amount within tolerance nor fall under a sane
/// derived ceiling — catches hallucinated figures) and a **hallucinated-name**
/// check (only when [sentNameVocabulary] is supplied, i.e. `shareNames` was on
/// — flag capitalized names in the reply that don't correspond to any real name
/// we sent). Both are best-effort; the text is always shown, only flagged.
class AiGatekeeper {
  AiGatekeeper({
    required Map<String, String> legend,
    required Set<String> validLabels,
    this.maxContextAmount,
    Set<double>? sentAmounts,
    Set<String>? sentNameVocabulary,
  })  : _legend = legend,
        _validLabels = validLabels,
        _sentAmounts = sentAmounts ?? const <double>{},
        _sentNameVocabulary = sentNameVocabulary;

  /// `label → real name`. May be empty (e.g. the `shareNames=true` path, where
  /// the LLM already used real names and restore is an identity no-op).
  final Map<String, String> _legend;

  /// The full set of label tokens the LLM was allowed to emit (`legend.keys`
  /// plus anything else the caller considers valid). Any `(cat|acc|mode|tag|
  /// goal|bill)_N` token found in the reply that is NOT in this set was
  /// invented by the LLM.
  final Set<String> _validLabels;

  /// Optional upper bound for the conservative numeric sanity check. Any
  /// currency-ish number in the reply that exceeds `maxContextAmount * 10` is
  /// flagged once. Null disables that wild-ceiling check.
  final double? maxContextAmount;

  /// The rounded figures the payload sent to the LLM (income, expense, amounts,
  /// balances, target/saved, etc.). Used by the numeric-correspondence check:
  /// a reply number is accepted if it matches one of these within ~2% or falls
  /// under `maxContextAmount * 1.5` (a sane derived figure). Empty = skip the
  /// correspondence pass (only the wild ceiling remains, when configured).
  final Set<double> _sentAmounts;

  /// The real names sent to the LLM (legend values + goal/bill names), only
  /// populated when `shareNames` was on. When non-null, the hallucinated-name
  /// check flags capitalized names in the reply not corresponding to any entry.
  /// Null = names were never sent (anonymized mode) → skip the name check.
  final Set<String>? _sentNameVocabulary;

  /// Replace every opaque label in [text] with its real name. No-op when the
  /// legend is empty.
  String restore(String text) => LabelReplacer.replace(text, _legend);

  /// Validate [text]: run [restore] first, then apply the checks. Returns the
  /// severity + human-readable issue strings (for a tooltip / debug).
  ///
  /// `bad` is reserved for empty / garbage replies. Everything else is `ok` or
  /// `flagged` — the text is always shown, with a note when flagged.
  AiCheckResult check(String text) {
    final restored = restore(text);

    // 1) Empty / markers-only → bad.
    if (restored.trim().isEmpty ||
        RegExp(r'^\s*[#*\->\s]*$').hasMatch(restored.trim())) {
      return (issues: const ['Reply was empty or contained no content.'],
          severity: AiCheckSeverity.bad);
    }

    final issues = <String>[];

    // 2) Leftover / invented label tokens after restore.
    final labelRe = RegExp(r'\b(?:cat|acc|mode|tag|goal|bill)_\d+\b');
    for (final match in labelRe.allMatches(restored)) {
      final token = match.group(0)!;
      if (!_validLabels.contains(token)) {
        issues.add('AI used an unknown label: $token');
      } else if (!_legend.containsKey(token)) {
        // Valid label but missing from legend → couldn't be restored.
        issues.add('Could not restore label: $token');
      }
    }

    // 3) Leaked-PII-looking tokens. These never leave the device, so this is a
    //    belt-and-suspenders scrub. Conservative regexes, single pass.
    if (_emailRe.hasMatch(restored)) {
      issues.add('Reply looked like it contained an email address.');
    }
    if (_phoneRe.hasMatch(restored)) {
      issues.add('Reply looked like it contained a phone number.');
    }
    if (_pathRe.hasMatch(restored)) {
      issues.add('Reply looked like it contained a file path.');
    }

    // 4) Numeric sanity. Two passes: a wild ceiling (any number far beyond the
    //    context) and a correspondence check (a number that doesn't match any
    //    sent figure and exceeds a sane derived bound). Both flag once.
    final hasCeiling = maxContextAmount != null && maxContextAmount! > 0;
    if (hasCeiling) {
      final ceiling = maxContextAmount! * 10;
      for (final match in _numberRe.allMatches(restored)) {
        final raw = match.group(1)!;
        final n = double.tryParse(raw.replaceAll(',', ''));
        if (n != null && n > ceiling) {
          issues.add('Reply contained a number far outside your data: $raw');
          break; // flag once
        }
      }
    }

    // 5) Numeric correspondence — catches hallucinated figures that sit under
    //    the wild ceiling but match nothing we actually sent. A number is
    //    accepted if it matches a sent amount within ~2% OR is a sane derived
    //    figure (≤ maxContextAmount * 1.5). Skipped entirely when no amounts
    //    were sent and no ceiling is configured (preserves the legacy no-op).
    if (_sentAmounts.isNotEmpty || hasCeiling) {
      final saneCeiling = (maxContextAmount ?? 0) * 1.5;
      for (final match in _numberRe.allMatches(restored)) {
        final raw = match.group(1)!;
        final n = double.tryParse(raw.replaceAll(',', ''));
        if (n == null) continue;
        if (_sentAmounts.any((s) => _withinTolerance(n, s))) continue;
        if (hasCeiling && n <= saneCeiling) continue;
        issues.add('Reply contained a figure not supported by your data: $raw');
        break; // flag once
      }
    }

    // 6) Hallucinated-name detection — only when real names were shared. Best-
    //    effort: extract capitalized words (not the first on a line, which is
    //    usually a heading/sentence start) and flag any that don't correspond
    //    to a sent name. Catches invented category/account/mode/tag names.
    if (_sentNameVocabulary != null && _sentNameVocabulary.isNotEmpty) {
      final candidates = _extractNameCandidates(restored);
      final vocabLower =
          _sentNameVocabulary.map((n) => n.toLowerCase()).toSet();
      for (final cand in candidates) {
        final c = cand.toLowerCase();
        if (_genericNameWords.contains(c)) continue;
        // Corresponds to a sent name if one contains the other (handles
        // "Food" vs the full "Food & Dining", and minor variants).
        final known = vocabLower.any((v) => v.contains(c) || c.contains(v));
        if (!known) {
          issues.add('Reply mentioned an unknown name: $cand');
          break; // flag once
        }
      }
    }

    return (
      issues: issues,
      severity: issues.isEmpty ? AiCheckSeverity.ok : AiCheckSeverity.flagged,
    );
  }

  /// True when [n] is within ~2% of [sent] (or both are zero).
  static bool _withinTolerance(double n, double sent) {
    if (sent == 0) return n == 0;
    return (n - sent).abs() / sent <= 0.02;
  }

  /// Extract candidate proper-name tokens from the reply: capitalized words of
  /// 3+ letters, skipping the first capitalized word on each line (usually a
  /// heading or sentence start) and skipping heading lines entirely.
  static List<String> _extractNameCandidates(String text) {
    final candidates = <String>[];
    final wordRe = RegExp(r"\b[A-Z][a-zA-Z]{2,}\b");
    for (final line in text.split('\n')) {
      if (line.trim().startsWith('#')) continue; // heading line
      final words = wordRe.allMatches(line).map((m) => m.group(0)!).toList();
      // Skip the first capitalized word on the line (sentence/heading start).
      for (var i = 1; i < words.length; i++) {
        candidates.add(words[i]);
      }
    }
    return candidates;
  }

  // Generic report/finance words that the prompts tell the LLM to use as
  // section headings or that are common in narrative text — never flagged as
  // invented names even when capitalized mid-sentence.
  static const _genericNameWords = {
    'overview', 'spending', 'budgets', 'budget', 'cashflow', 'cashflows',
    'takeaways', 'takeaway', 'summary', 'income', 'expense', 'expenses',
    'savings', 'saving', 'salary', 'net', 'total', 'month', 'months',
    'week', 'weekly', 'yearly', 'annual', 'report', 'trends', 'trend',
    'observation', 'observations', 'review', 'indian', 'india', 'today',
    'yesterday', 'tomorrow', 'note', 'notes', 'split', 'breakdown',
    'progress', 'balance', 'balances', 'target', 'goal', 'goals',
    'subscription', 'subscriptions', 'rent', 'modes', 'mode', 'tags', 'tag',
    'categories', 'category', 'accounts', 'account',
  };

  // 10+ consecutive digits (optionally with + / spaces / dashes) — phone-ish.
  static final _phoneRe =
      RegExp(r'(?:\+?\d[\d\s\-]{8,}\d)');
  static final _emailRe = RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b');
  // A path-like token ending in an image extension, or a leading /path/segment.
  static final _pathRe =
      RegExp(r'(?:\b\w+://\S+\.(?:png|jpe?g|webp)\b|\B/[\w\-/]+\.(?:png|jpe?g|webp)\b)');
  // Currency-ish numbers: 3+ digits, optional thousands separators / decimals.
  static final _numberRe = RegExp(r'\b(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d{4,}(?:\.\d+)?)\b');
}