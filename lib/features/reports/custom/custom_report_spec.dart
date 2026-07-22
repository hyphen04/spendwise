import 'dart:convert';

/// A user-authored, on-device report definition. The user picks a group-by
/// dimension, a metric, a transaction-kind filter, a date range, optional
/// account/category/mode filters, and a chart type; the
/// [CustomReportExecutor] runs it against the safe table subset and the result
/// is rendered with fl_chart.
///
/// **This spec is never sent to the LLM.** It carries only field references and
/// filter ids (UUIDs of the user's own accounts/categories/modes) — no
/// transaction notes, no contact names/phones, no receipt paths, no raw rows.
/// It is persisted in the `custom_reports` table as JSON.
///
/// The enum values are the only user-controllable dimension selectors; filter
/// ids are UUIDs sourced from the app's own pickers, so the executor's SQL is
/// built from a fixed vocabulary (no user-authored SQL, no injection surface).
class CustomReportSpec {
  CustomReportSpec({
    required this.name,
    required this.groupBy,
    required this.metric,
    required this.kind,
    required this.dateRange,
    required this.chartType,
    this.customFrom,
    this.customTo,
    this.accountId,
    this.categoryId,
    this.modeId,
  });

  /// Display name (also stored on the `custom_reports` row).
  String name;

  /// Dimension to group rows by.
  CustomGroupBy groupBy;

  /// How to aggregate the amount within each group.
  CustomMetric metric;

  /// Transaction kind filter.
  CustomKind kind;

  /// Date range preset (or [CustomDateRange.custom] with [customFrom]/[customTo]).
  CustomDateRange dateRange;

  /// Render hint for the preview / view screen.
  CustomChartType chartType;

  /// ISO date 'yyyy-MM-dd' — used only when [dateRange] is custom.
  String? customFrom;
  String? customTo;

  // ── Optional filters (UUIDs of the user's own entities) ────────────────────
  /// Mutable so the builder can toggle them in place before re-publishing the
  /// spec via `copy()`. Persisted with the spec; never sent to the LLM.
  String? accountId;
  String? categoryId;
  String? modeId;

  Map<String, Object?> toJson() => {
        'name': name,
        'groupBy': groupBy.name,
        'metric': metric.name,
        'kind': kind.name,
        'dateRange': dateRange.name,
        'chartType': chartType.name,
        if (customFrom != null) 'customFrom': customFrom,
        if (customTo != null) 'customTo': customTo,
        if (accountId != null) 'accountId': accountId,
        if (categoryId != null) 'categoryId': categoryId,
        if (modeId != null) 'modeId': modeId,
      };

  String toJsonString() => jsonEncode(toJson());

  static CustomReportSpec fromJson(Map<String, Object?> json) {
    return CustomReportSpec(
      name: (json['name'] as String?) ?? 'Custom report',
      groupBy: _enumFromString(CustomGroupBy.values, json['groupBy']),
      metric: _enumFromString(CustomMetric.values, json['metric']),
      kind: _enumFromString(CustomKind.values, json['kind']),
      dateRange: _enumFromString(CustomDateRange.values, json['dateRange']),
      chartType: _enumFromString(CustomChartType.values, json['chartType']),
      customFrom: json['customFrom'] as String?,
      customTo: json['customTo'] as String?,
      accountId: json['accountId'] as String?,
      categoryId: json['categoryId'] as String?,
      modeId: json['modeId'] as String?,
    );
  }

  static CustomReportSpec fromJsonString(String raw) =>
      fromJson(jsonDecode(raw) as Map<String, Object?>);

  /// A defensive copy so the builder can mutate `name` without aliasing the
  /// saved row's spec.
  CustomReportSpec copy() => CustomReportSpec(
        name: name,
        groupBy: groupBy,
        metric: metric,
        kind: kind,
        dateRange: dateRange,
        chartType: chartType,
        customFrom: customFrom,
        customTo: customTo,
        accountId: accountId,
        categoryId: categoryId,
        modeId: modeId,
      );

  /// Value identity so [customReportDataProvider] (a `FutureProvider.family`
  /// keyed by this spec) treats a re-parsed spec as the same key. Without this,
  /// the view screen rebuilds a fresh spec instance each frame via
  /// `fromJsonString`, family keys it by object identity, a brand-new provider
  /// starts in `loading`, resolves, triggers a rebuild, and loops forever — the
  /// chart never renders. Specs are never mutated in place (the builder always
  /// publishes via [copy]), so the hash stays stable while a spec is a key.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomReportSpec &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          groupBy == other.groupBy &&
          metric == other.metric &&
          kind == other.kind &&
          dateRange == other.dateRange &&
          chartType == other.chartType &&
          customFrom == other.customFrom &&
          customTo == other.customTo &&
          accountId == other.accountId &&
          categoryId == other.categoryId &&
          modeId == other.modeId;

  @override
  int get hashCode => Object.hash(
        name,
        groupBy,
        metric,
        kind,
        dateRange,
        chartType,
        customFrom,
        customTo,
        accountId,
        categoryId,
        modeId,
      );
}

T _enumFromString<T extends Enum>(List<T> values, Object? raw) {
  if (raw is String) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
  }
  return values.first;
}

/// Dimension to group rows by.
enum CustomGroupBy {
  category,
  account,
  mode,
  day,
  month,
}

/// How to aggregate the amount within each group.
enum CustomMetric {
  sum,
  count,
  avg,
}

/// Transaction kind filter. `all` = income + expense (transfers excluded).
enum CustomKind {
  expense,
  income,
  all,
}

/// Date range preset. `custom` uses [CustomReportSpec.customFrom]/[customTo].
enum CustomDateRange {
  thisMonth,
  last3,
  thisYear,
  custom,
}

/// Render hint for the preview / view screen.
enum CustomChartType {
  bar,
  pie,
  line,
  list,
  stat,
}