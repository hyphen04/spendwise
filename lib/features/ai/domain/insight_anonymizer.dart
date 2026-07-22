import '../../ai/domain/local_insight_engine.dart';
import 'label_replacer.dart';

/// A pair of insight text fields, in title/body order.
typedef InsightText = ({String title, String body});

/// The privacy boundary for the Phase 5 insight-polish pass.
///
/// The local [AiInsight]s are generated on-device and their text contains real
/// category and payment-mode names (e.g. "Food spending spiked", "recurring
/// charge in Subscriptions paid via UPI"). Before that text is sent to the LLM
/// for rewriting, [anonymizeInsights] replaces every real name with an opaque
/// label (`cat_0`, `mode_1`). After the LLM rewrites the text, [restore]
/// reverses the labels back to real names — entirely on-device. The legend
/// (name ↔ label) never leaves the device.
///
/// Pure Dart, no Flutter, no IO — unit-testable in isolation.
class InsightAnonymizer {
  /// Constructs the anonymizer from the real-name vocabulary that can appear in
  /// any local insight: category names and payment-mode names (gathered from the
  /// same aggregations the [LocalInsightEngine] reads). Empty/blank names are
  /// ignored.
  InsightAnonymizer({
    required Set<String> categories,
    required Set<String> modes,
  }) {
    // Single unified map so a name that appears as both a category and a mode
    // gets one stable label (category prefix wins) and can't collide.
    void register(String name, String label) {
      final clean = name.trim();
      if (clean.isEmpty) return;
      _nameToLabel.putIfAbsent(clean, () => label);
    }

    var catN = 0, modeN = 0;
    for (final c
        in (categories.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))) {
      register(c, 'cat_$catN');
      catN++;
    }
    for (final m
        in (modes.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))) {
      // Reuse the existing label if this name was already registered as a
      // category; otherwise mint a mode_ label.
      if (!_nameToLabel.containsKey(m.trim())) {
        register(m, 'mode_$modeN');
        modeN++;
      }
    }
    // Inverse map for restore.
    _labelToName = {
      for (final e in _nameToLabel.entries) e.value: e.key,
    };
  }

  final Map<String, String> _nameToLabel = {};
  late final Map<String, String> _labelToName;

  /// Whether any names were registered (i.e. anonymization is active).
  bool get hasVocabulary => _nameToLabel.isNotEmpty;

  /// The on-device `label → real-name` legend, used to build an [AiGatekeeper]
  /// for the polish/digest path so its reply is restored AND checked (PII-scrub
  /// + numeric sanity) through the same warden as the chat/report surfaces.
  /// The legend itself never left the device (only opaque labels were sent).
  Map<String, String> get labelToName => Map.unmodifiable(_labelToName);

  /// The real names that were anonymized — the vocabulary an LLM reply may
  /// legitimately mention when `shareNames` was on. Used as the gatekeeper's
  /// `sentNameVocabulary`.
  Set<String> get names => Set.unmodifiable(_nameToLabel.keys);

  /// Replace every real name in each insight's title/body with its opaque
  /// label. Longer names are replaced first so "HDFC Card" is handled before
  /// "HDFC" and "Food & Dining" before "Food".
  List<InsightText> anonymizeInsights(List<AiInsight> insights) {
    return insights
        .map((i) => (
              title: LabelReplacer.replace(i.title, _nameToLabel),
              body: LabelReplacer.replace(i.body, _nameToLabel),
            ))
        .toList();
  }

  /// Reverse every opaque label back to its real name. Longer labels are
  /// replaced first so `cat_10` is handled before `cat_1` (the latter is a
  /// prefix of the former and would corrupt it). Case-insensitive + fuzzy so
  /// `Cat_0` / `cate_0` / `category_0` / `cat 0` also restore, and unresolvable
  /// label-shaped tokens are scrubbed to a noun.
  List<InsightText> restore(List<InsightText> polished) {
    return polished
        .map((p) => (
              title: LabelReplacer.replace(p.title, _labelToName,
                  caseInsensitive: true, fuzzy: true),
              body: LabelReplacer.replace(p.body, _labelToName,
                  caseInsensitive: true, fuzzy: true),
            ))
        .toList();
  }
}