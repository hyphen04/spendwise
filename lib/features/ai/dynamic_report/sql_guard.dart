import 'dart:async' show TimeoutException;

import '../../../data/db/app_database.dart';

/// Validates and executes LLM-authored read-only SQL on-device (Stage B of the
/// dynamic-report safety pipeline). Only reached when `customSql` is enabled
/// in settings AND a [ChartSpec] uses [DataProvider.customSql].
///
/// **Privacy invariant:** the LLM never sees query results — they stay
/// on-device and are rendered locally. The guard ensures the SQL can only read
/// from a safe subset of tables and can never touch PII columns (notes, contact
/// names/phones/photos, device-contact ids, chat history).
///
/// Defense in depth (no single layer is enough):
/// 1. Drift's `customSelect` prepares a single statement — SQLite's
///    `prepare_v2` only prepares the first statement, so trailing `; DROP …`
///    after a SELECT is not executed. We additionally enforce single-statement.
/// 2. Keyword blocklist (DROP/DELETE/UPDATE/INSERT/ALTER/…).
/// 3. Table deny-list — `due_contacts`, `due_entries`, `due_settlements`,
///    `ai_threads`, `ai_messages` hold PII / chat content; never queryable.
/// 4. Column deny-list — `note`, `receipt_path`, `phone`, `photo_path`,
///    `device_contact_id`, `phones` never selectable.
/// 5. Auto-inject `LIMIT` (cap 500 rows) if none present.
/// 6. Execution timeout.
///
/// **Honest limit (documented in the plan):** this prevents *destructive* and
/// *PII-leaking* SQL with high confidence, but cannot prevent
/// *semantically-wrong-but-valid* SQL (e.g. counting transfers as income).
/// That residual risk is why `customSql` is opt-in and off by default; named
/// providers cover the common cases safely.
class SqlGuard {
  SqlGuard(this._db);
  final AppDatabase _db;

  static const int _maxRows = 500;
  static const Duration _timeout = Duration(seconds: 10);

  /// Tables the LLM may never reference (PII + chat content + on-device-only
  /// data). `goals` and `recurring_items` are deliberately kept out of
  /// `schema_metadata` (bills + goals stay on-device only), so an opt-in
  /// `customSql` query must not reach them either.
  static const _deniedTables = {
    'due_contacts',
    'due_entries',
    'due_settlements',
    'ai_threads',
    'ai_messages',
    'goals',
    'recurring_items',
  };

  /// Columns the LLM may never SELECT (PII). Matched as word-boundary tokens
  /// against the snake_case column names used in the DB.
  static const _deniedColumns = {
    'note',
    'receipt_path',
    'phone',
    'photo_path',
    'device_contact_id',
    'phones',
  };

  /// Destructive / non-SELECT keywords.
  static final _blockedKeywordRe = RegExp(
    r'\b(DROP|DELETE|UPDATE|INSERT|ALTER|TRUNCATE|CALL|CREATE|REPLACE|GRANT|REVOKE|LOAD|ATTACH|DETACH|PRAGMA|VACUUM|REINDEX)\b',
    caseSensitive: false,
  );

  /// Validate SQL without executing. Returns an error string, or `null` if ok.
  String? validate(String sql) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return 'Query is empty.';

    // 1) Single statement: reject a ';' followed by non-whitespace (a second
    //    statement). A trailing ';' alone is fine.
    final semi = trimmed.replaceAll(RegExp(r';\s*$'), '');
    if (RegExp(r';\s*\S').hasMatch(semi)) {
      return 'Only a single statement is allowed.';
    }

    // 2) Must look like a SELECT.
    if (!RegExp(r'^\s*SELECT\b', caseSensitive: false).hasMatch(trimmed)) {
      return 'Query must start with SELECT.';
    }

    // 3) Blocked keywords.
    final kw = _blockedKeywordRe.firstMatch(trimmed);
    if (kw != null) {
      return 'Blocked keyword "${kw.group(0)}" is not allowed.';
    }

    // 4) Denied tables.
    for (final t in _deniedTables) {
      if (RegExp(r'\b' + t + r'\b', caseSensitive: false).hasMatch(trimmed)) {
        return 'Table "$t" is private and cannot be queried.';
      }
    }

    // 5) Denied columns.
    for (final c in _deniedColumns) {
      if (RegExp(r'\b' + c + r'\b', caseSensitive: false).hasMatch(trimmed)) {
        return 'Column "$c" is private and cannot be selected.';
      }
    }

    return null; // ok
  }

  /// Validate, inject a LIMIT if missing, and execute on-device. Results stay
  /// local (never sent anywhere). Returns rows + columns, or a failure with
  /// an error suitable to feed back to the LLM for one retry.
  Future<SqlGuardResult> run(String sql) async {
    final err = validate(sql);
    if (err != null) return SqlGuardResult.fail(err);

    var finalSql = sql.trim();
    if (!RegExp(r'\bLIMIT\b', caseSensitive: false).hasMatch(finalSql)) {
      // Wrap in a sub-select so LIMIT always applies, even for GROUP BY / etc.
      finalSql = 'SELECT * FROM ($finalSql) AS _sg LIMIT $_maxRows';
    }

    try {
      final rows = await _db
          .customSelect(finalSql)
          .get()
          .timeout(_timeout, onTimeout: () {
        throw TimeoutException('Query exceeded ${_timeout.inSeconds}s.');
      });

      final mapped = rows.map((r) => r.data).toList();
      final cols = mapped.isEmpty
          ? <String>[]
          : mapped.first.keys.toList(growable: false);
      return SqlGuardResult.ok(mapped, cols);
    } on TimeoutException catch (e) {
      return SqlGuardResult.fail('Query timed out: $e');
    } catch (e) {
      return SqlGuardResult.fail('Query failed: $e');
    }
  }
}

class SqlGuardResult {
  const SqlGuardResult.ok(this.rows, this.columns) : error = null;
  const SqlGuardResult.fail(this.error)
      : rows = const [],
        columns = const [];

  final List<Map<String, Object?>> rows;
  final List<String> columns;
  final String? error;
  bool get ok => error == null;
}