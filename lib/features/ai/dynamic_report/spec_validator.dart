import 'dart:convert';

import '../domain/ai_gatekeeper.dart';
import 'chart_spec.dart';

/// Outcome of validating a raw LLM JSON blob into a [DynamicReportSpec].
sealed class ValidationResult {
  const ValidationResult();
}

class ValidSpec extends ValidationResult {
  const ValidSpec(this.spec, {this.restoredTitles});
  final DynamicReportSpec spec;

  /// Per-chart restored titles/captions (gatekeeper applied), in chart order.
  /// Phase 2 uses these so the renderer shows real names without re-running
  /// the gatekeeper. Null entries mean no restore was applied.
  final List<({String title, String? caption})>? restoredTitles;
}

class InvalidSpec extends ValidationResult {
  const InvalidSpec(this.errors);
  final List<String> errors;
}

/// Stage A validation: parses LLM JSON into a [DynamicReportSpec] and checks it
/// against a strict allow-list before any data is touched. Pure Dart, unit-
/// testable. The Dart validator is the source of truth — provider structured-
/// output enforcement is uneven, so we never trust it alone.
///
/// Pass an [AiGatekeeper] (Phase 2, built from the AI context legend) to restore
/// opaque labels in titles/captions on-device and scrub for leaked PII. When
/// `gatekeeper` is null (Phase 1 default spec, no LLM), titles are used as-is.
class SpecValidator {
  const SpecValidator({this.gatekeeper, this.customSqlEnabled = false});
  final AiGatekeeper? gatekeeper;
  final bool customSqlEnabled;

  /// Param keys allowed per provider. Anything else → reject.
  static const _allowedParams = <DataProvider, Set<String>>{
    DataProvider.topCategories: {'limit'},
    DataProvider.cashflow6mo: {'count'},
    DataProvider.budgets: {},
    DataProvider.modes: {'kind'},
    DataProvider.monthlySummary: {},
    DataProvider.customSql: {'sql'},
  };

  /// Parse + validate a raw JSON blob. Returns [ValidSpec] or [InvalidSpec].
  ValidationResult parse(String raw) {
    final errors = <String>[];

    dynamic json;
    try {
      json = jsonDecode(raw);
    } catch (e) {
      return InvalidSpec(['Response was not valid JSON: $e']);
    }
    if (json is! Map<String, Object?>) {
      return InvalidSpec(['Response must be a JSON object.']);
    }

    final chartsJson = json['charts'];
    if (chartsJson is! List || chartsJson.isEmpty) {
      return InvalidSpec(['"charts" must be a non-empty array.']);
    }

    final charts = <ChartSpec>[];
    final restored = <({String title, String? caption})>[];

    for (var i = 0; i < chartsJson.length; i++) {
      final c = chartsJson[i];
      if (c is! Map<String, Object?>) {
        errors.add('Chart #$i must be an object.');
        continue;
      }
      final type = _enum<ChartType>(c['type'], ChartType.values, 'type', errors, i);
      final provider = _enum<DataProvider>(
          c['provider'], DataProvider.values, 'provider', errors, i);
      if (type == null || provider == null) continue;

      final titleRaw = c['title'];
      if (titleRaw is! String || titleRaw.trim().isEmpty) {
        errors.add('Chart #$i is missing a title.');
        continue;
      }

      // Params: must be an object with only allow-listed keys.
      final params = <String, Object>{};
      final paramsJson = c['params'];
      if (paramsJson != null) {
        if (paramsJson is! Map<String, Object?>) {
          errors.add('Chart #$i "params" must be an object.');
        } else {
          final allowed = _allowedParams[provider]!;
          for (final entry in paramsJson.entries) {
            if (!allowed.contains(entry.key)) {
              errors.add('Chart #$i: unknown param "${entry.key}" for '
                  '${provider.name}.');
            } else if (entry.value != null) {
              params[entry.key] = entry.value!;
            }
          }
        }
      }

      // customSql requires a sql param + the setting enabled.
      if (provider == DataProvider.customSql) {
        final sql = params['sql'];
        if (sql is! String || sql.trim().isEmpty) {
          errors.add('Chart #$i (customSql) requires a non-empty "sql" param.');
        } else if (!customSqlEnabled) {
          errors.add('Chart #$i uses customSql, which is not enabled in '
              'settings.');
        }
      }

      // Gatekeeper: restore labels in title/caption, scrub PII. `bad`
      // severity (empty after restore) → reject the chart.
      String title = titleRaw;
      String? caption;
      final capRaw = c['caption'];
      if (capRaw is String) caption = capRaw;
      if (gatekeeper != null) {
        final restoredTitle = gatekeeper!.restore(title);
        final check = gatekeeper!.check(restoredTitle);
        if (check.severity == AiCheckSeverity.bad) {
          errors.add('Chart #$i title came back empty after on-device restore.');
          continue;
        }
        title = restoredTitle;
        if (caption != null) caption = gatekeeper!.restore(caption);
      }

      // Series (optional): each must have a non-empty "field".
      final series = <ChartSeries>[];
      final seriesJson = c['series'];
      if (seriesJson != null) {
        if (seriesJson is! List) {
          errors.add('Chart #$i "series" must be an array.');
        } else {
          for (var s = 0; s < seriesJson.length; s++) {
            final sj = seriesJson[s];
            if (sj is! Map<String, Object?>) {
              errors.add('Chart #$i series #$s must be an object.');
              continue;
            }
            final field = sj['field'];
            if (field is! String || field.trim().isEmpty) {
              errors.add('Chart #$i series #$s needs a non-empty "field".');
              continue;
            }
            series.add(ChartSeries(
              field: field,
              labelField: sj['labelField'] as String?,
              colorField: sj['colorField'] as String?,
              iconField: sj['iconField'] as String?,
              name: sj['name'] as String?,
            ));
          }
        }
      }

      charts.add(ChartSpec(
        type: type,
        title: title,
        provider: provider,
        params: params,
        series: series,
        highlight: c['highlight'] as String?,
        comparison: c['comparison'] as String?,
        caption: caption,
      ));
      restored.add((title: title, caption: caption));
    }

    if (charts.isEmpty) {
      return InvalidSpec(errors.isEmpty
          ? const ['No valid charts in the response.']
          : errors);
    }
    if (errors.isNotEmpty) {
      // Some charts failed; reject the whole spec (one retry, then fallback).
      return InvalidSpec(errors);
    }

    // `narrativeSeed` is used ONLY as an outbound hint to the narrative LLM
    // (it is never shown to the user), so it MUST stay in opaque-label form.
    // Restoring it here would leak real category/mode names to the LLM when the
    // user has NOT opted into sharing names (shareNames=false, the default) —
    // the anonymize-by-default contract. Any opaque labels the LLM echoes into
    // the streamed narrative are restored to real names on-device by the
    // AiGatekeeper during streaming. Chart titles/captions above ARE restored
    // because they are displayed on-device in SpecChart and never sent out.
    final seed = json['narrativeSeed'];

    return ValidSpec(
      DynamicReportSpec(
          charts: charts, narrativeSeed: seed is String ? seed : null),
      restoredTitles: restored,
    );
  }

  T? _enum<T extends Enum>(Object? v, List<T> values, String label,
      List<String> errors, int i) {
    if (v is! String) {
      errors.add('Chart #$i is missing a "$label".');
      return null;
    }
    for (final e in values) {
      if (e.name == v) return e;
    }
    errors.add('Chart #$i has unknown $label "$v".');
    return null;
  }
}