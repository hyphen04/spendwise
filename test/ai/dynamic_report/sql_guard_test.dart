import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/features/ai/dynamic_report/sql_guard.dart';

void main() {
  group('SqlGuard.validate', () {
    final db = AppDatabase(NativeDatabase.memory());
    final guard = SqlGuard(db);
    tearDownAll(() => db.close());

    test('plain SELECT passes', () {
      expect(guard.validate('SELECT 1 AS n'), isNull);
    });

    test('must start with SELECT', () {
      expect(guard.validate('PRAGMA foreign_keys'), isNotNull);
      expect(guard.validate('WITH x AS (SELECT 1) SELECT * FROM x'),
          isNotNull); // doesn't start with SELECT
    });

    test('DELETE blocked', () {
      expect(guard.validate('DELETE FROM transactions'), isNotNull);
    });

    test('DROP blocked', () {
      expect(guard.validate('SELECT 1; DROP TABLE transactions'),
          isNotNull); // also multi-statement
    });

    test('UPDATE / INSERT / ALTER blocked', () {
      for (final kw in ['UPDATE x SET y=1', 'INSERT INTO x VALUES(1)',
                        'ALTER TABLE x RENAME TO y']) {
        expect(guard.validate(kw), isNotNull, reason: kw);
      }
    });

    test('blocked table (due_contacts) rejected', () {
      expect(
          guard.validate('SELECT id FROM due_contacts'), isNotNull);
    });

    test('blocked table (ai_messages) rejected', () {
      expect(
          guard.validate('SELECT id FROM ai_messages'), isNotNull);
    });

    test('on-device-only tables (goals, recurring_items) rejected', () {
      expect(guard.validate('SELECT id, name FROM goals'), isNotNull);
      expect(guard.validate('SELECT id, amount FROM recurring_items'),
          isNotNull);
    });

    test('blocked column (note) rejected', () {
      expect(guard.validate('SELECT note FROM transactions'), isNotNull);
    });

    test('blocked column (phone) rejected', () {
      expect(guard.validate('SELECT phone FROM due_contacts'), isNotNull);
    });

    test('multi-statement rejected', () {
      expect(guard.validate('SELECT 1; SELECT 2'), isNotNull);
    });

    test('trailing semicolon alone is fine', () {
      expect(guard.validate('SELECT 1;'), isNull);
    });

    test('PRAGMA / ATTACH blocked', () {
      expect(guard.validate('SELECT 1; ATTACH DATABASE \':mem:\' AS x'),
          isNotNull);
    });
  });

  group('SqlGuard.run', () {
    late AppDatabase db;
    late SqlGuard guard;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      guard = SqlGuard(db);
    });
    tearDown(() => db.close());

    test('allowed SELECT returns rows', () async {
      final r = await guard.run('SELECT 1 AS n');
      expect(r.ok, isTrue);
      expect(r.rows, hasLength(1));
      expect(r.rows.first['n'], 1);
      expect(r.columns, contains('n'));
    });

    test('destructive SQL fails (not executed)', () async {
      final r = await guard.run('DELETE FROM transactions');
      expect(r.ok, isFalse);
      expect(r.error, isNotNull);
    });

    test('blocked-table query fails', () async {
      final r = await guard.run('SELECT id FROM due_contacts');
      expect(r.ok, isFalse);
      expect(r.error, contains('private'));
    });

    test('LIMIT is auto-injected (no error, rows returned)', () async {
      // A query with no LIMIT still runs and is wrapped to cap at 500 rows.
      final r = await guard.run('SELECT 1 AS n');
      expect(r.ok, isTrue);
      expect(r.rows.length, lessThanOrEqualTo(500));
    });
  });
}