/// Declarative chart spec for the AI-orchestrated dynamic report.
///
/// Instead of the report screen hardcoding which charts to show, a
/// [DynamicReportSpec] describes them: a list of [ChartSpec]s, each picking a
/// chart [ChartType] and a named on-device [DataProvider] (plus optional params).
/// The app executes the spec locally and renders the chosen charts from real
/// data — the LLM never sees raw rows. (Phase 2 lets the LLM emit this spec;
/// Phase 1 just establishes the format + a safe default so the screen is
/// spec-driven before any AI is wired in.)
///
/// Design notes:
/// - `provider` is an allow-list of *named on-device aggregations* — the LLM
///   picks from a menu of pre-built, validated providers rather than authoring
///   SQL. `customSql` is the opt-in escape hatch (gated by a setting + the
///   [SqlGuard] safety pipeline).
/// - `series` is optional. Named providers have a known row shape, so the
///   renderer uses sensible default fields per [ChartType]; `series` overrides
///   those (mainly for `customSql`, where the columns are LLM-defined).
/// - `title`/`caption` are plain text the LLM writes using opaque labels; the
///   [AiGatekeeper] restores labels → real names on-device and scrubs for PII.
///   They never carry raw user data.
library;

enum ChartType { pie, bar, line, progress, list, stat }

enum DataProvider {
  topCategories, // top expense categories for the month
  cashflow6mo, // rolling 6-month income/expense
  budgets, // budget progress for the month
  modes, // payment-mode breakdown for the month
  monthlySummary, // month income/expense/net/opening/closing
  customSql, // opt-in: LLM-authored read-only SELECT (gated + validated)
}

class ChartSeries {
  const ChartSeries({
    required this.field,
    this.labelField,
    this.colorField,
    this.iconField,
    this.name,
  });

  /// Column holding the primary numeric value.
  final String field;

  /// Column holding the row label (defaults per chart type, e.g. 'name').
  final String? labelField;

  /// Column holding a hex color (e.g. '#059669').
  final String? colorField;

  /// Column holding an emoji/icon.
  final String? iconField;

  /// Human name for this series (legend). Mainly for multi-series bar/line.
  final String? name;

  Map<String, Object?> toJson() => {
        'field': field,
        if (labelField != null) 'labelField': labelField,
        if (colorField != null) 'colorField': colorField,
        if (iconField != null) 'iconField': iconField,
        if (name != null) 'name': name,
      };
}

class ChartSpec {
  const ChartSpec({
    required this.type,
    required this.title,
    required this.provider,
    this.params = const {},
    this.series = const [],
    this.highlight,
    this.comparison,
    this.caption,
  });

  final ChartType type;
  final String title;
  final DataProvider provider;

  /// Provider-specific params. Allow-listed per provider by [SpecValidator]:
  /// - topCategories: {limit:int}
  /// - cashflow6mo: {count:int}
  /// - modes: {kind:string}
  /// - budgets: {}
  /// - monthlySummary: {}
  /// - customSql: {sql:string}
  final Map<String, Object> params;

  /// Optional series overrides (mainly for customSql). Empty for named
  /// providers → the renderer uses default fields per [ChartType].
  final List<ChartSeries> series;

  /// An opaque label (e.g. 'cat_0') or token (e.g. 'over_budget') to emphasize.
  /// Advisory — the renderer highlights it when it can.
  final String? highlight;

  /// Optional comparison hint, e.g. 'vs_last_month'. Advisory.
  final String? comparison;

  /// Optional one-line caption (gatekeeper-restored on-device).
  final String? caption;

  Map<String, Object?> toJson() => {
        'type': type.name,
        'title': title,
        'provider': provider.name,
        'params': params,
        if (series.isNotEmpty) 'series': series.map((s) => s.toJson()).toList(),
        if (highlight != null) 'highlight': highlight,
        if (comparison != null) 'comparison': comparison,
        if (caption != null) 'caption': caption,
      };
}

class DynamicReportSpec {
  const DynamicReportSpec({required this.charts, this.narrativeSeed});

  /// Ordered charts to render. Empty list is invalid.
  final List<ChartSpec> charts;

  /// Optional plain-text seed the LLM suggests for the narrative section.
  /// Gatekeeper-restored on-device. Phase 2 uses this; Phase 1 ignores it.
  final String? narrativeSeed;
}