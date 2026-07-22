import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../../features/ai/domain/local_insight_engine.dart';
import 'reports_repository.dart';

/// Repository for [RecurringItem]s (bills & subscriptions).
///
/// Detected items are seeded on-device from the user's own expense history via
/// [LocalInsightEngine.detectRecurring] — nothing leaves the device. Manual
/// items are user-authored. All amounts/notes stay local; this table is never
/// part of the AI schema metadata.
class RecurringRepository {
  RecurringRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<RecurringItem>> watchAll() => _db.recurringItemsDao.watchAll();
  Future<List<RecurringItem>> getAll() => _db.recurringItemsDao.getAll();

  Future<RecurringItem?> getById(String id) =>
      _db.recurringItemsDao.getById(id);

  Future<void> create({
    required String name,
    required double amount,
    required String categoryId,
    String? accountId,
    String? modeId,
    String cadence = 'monthly',
    required DateTime nextDueDate,
    String source = 'manual',
    String note = '',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.recurringItemsDao.upsert(RecurringItemsCompanion.insert(
      id: _uuid.v4(),
      name: name,
      amount: amount,
      categoryId: categoryId,
      accountId: Value(accountId),
      modeId: Value(modeId),
      cadence: Value(cadence),
      nextDueDate: _day(nextDueDate),
      source: Value(source),
      note: Value(note),
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> update(
    RecurringItem existing, {
    required String name,
    required double amount,
    required String categoryId,
    String? accountId,
    String? modeId,
    required String cadence,
    required DateTime nextDueDate,
    String? note,
    bool? isActive,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.recurringItemsDao.upsert(RecurringItemsCompanion(
      id: Value(existing.id),
      name: Value(name),
      amount: Value(amount),
      categoryId: Value(categoryId),
      accountId: Value(accountId),
      modeId: Value(modeId),
      cadence: Value(cadence),
      nextDueDate: Value(_day(nextDueDate)),
      source: Value(existing.source),
      isActive: Value(isActive ?? existing.isActive),
      note: Value(note ?? existing.note),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(now),
    ));
  }

  Future<int> delete(String id) => _db.recurringItemsDao.deleteById(id);

  // ── "Not a bill" ignore list ───────────────────────────────────────────────
  // A category the user marked as not-a-recurring-bill. The detector skips it
  // (see [autoRefreshFromTransactions]) so a false positive like Fuel isn't
  // re-seeded on re-detect. Category id only — no PII, never sent to the AI.

  Future<Set<String>> ignoredCategoryIds() async {
    final rows = await _db.select(_db.ignoredRecurring).get();
    return rows.map((r) => r.categoryId).toSet();
  }

  Future<void> ignoreCategory(String categoryId) async {
    await _db.into(_db.ignoredRecurring).insertOnConflictUpdate(
          IgnoredRecurringCompanion.insert(
            categoryId: categoryId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> unignoreCategory(String categoryId) async {
    await (_db.delete(_db.ignoredRecurring)
          ..where((r) => r.categoryId.equals(categoryId)))
        .go();
  }

  /// Mark [item]'s category as "not a bill" and remove the detected row in one
  /// step. Only meaningful for `source == 'detected'` rows. Manual re-add in the
  /// same category is still allowed — this only suppresses auto-detection.
  Future<void> ignoreDetected(RecurringItem item) async {
    await ignoreCategory(item.categoryId);
    await delete(item.id);
  }

  /// Active items whose next due date falls within [days] days from today
  /// (inclusive of today). Used for the "upcoming bills" reminder surface.
  Future<List<RecurringItem>> dueInDays(int days) async {
    final all = await getAll();
    final now = _today();
    final horizon = now.add(Duration(days: days));
    return all.where((r) {
      if (!r.isActive) return false;
      final due = DateTime.tryParse(r.nextDueDate);
      if (due == null) return false;
      final d = DateTime(due.year, due.month, due.day);
      return !d.isBefore(now) && !d.isAfter(horizon);
    }).toList();
  }

  /// Days until the next due date (negative if overdue). Null if unparseable.
  int? daysUntilDue(RecurringItem r) {
    final due = DateTime.tryParse(r.nextDueDate);
    if (due == null) return null;
    final d = DateTime(due.year, due.month, due.day);
    return DateTime(d.year, d.month, d.day).difference(_today()).inDays;
  }

  /// Advance a due date by one cadence interval, returning the next due date.
  DateTime advanceDueDate(RecurringItem r) {
    final due = DateTime.tryParse(r.nextDueDate) ?? DateTime.now();
    return _addCadence(due, r.cadence);
  }

  /// Detect recurring payments from the last 12 months of expenses and seed any
  /// that aren't already tracked. Idempotent by (name, amount, cadence): a
  /// matching existing item (manual or detected) is never duplicated. Returns
  /// the number of newly inserted detected items.
  ///
  /// Category/mode names from the detector are resolved to ids on-device; a
  /// detected group whose category no longer exists is skipped (no valid FK).
  /// Categories the user marked "not a bill" ([ignoredCategoryIds]) are skipped
  /// too, so a dismissed false positive isn't re-seeded on re-detect.
  Future<int> autoRefreshFromTransactions(ReportsRepository reports) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 12).toIso8601String();
    final to = DateTime(now.year, now.month + 1).toIso8601String();
    final expenses = await reports.transactionsForExport(
        from: from, to: to, kind: 'expense');
    final detected = LocalInsightEngine.detectRecurring(expenses);
    if (detected.isEmpty) return 0;

    final cats = await _db.categoriesDao.getAllActive();
    final catByName = {for (final c in cats) c.name: c};
    final modes = await _db.modesDao.getAllActive();
    final modeByName = {for (final m in modes) m.name: m};

    final existing = await getAll();
    final existingKeys = {
      for (final r in existing) _key(r.name, r.amount, r.cadence),
    };

    // Skip categories the user has marked "not a bill" so false positives
    // (e.g. Fuel bought at a regular price) aren't re-seeded.
    final ignored = await ignoredCategoryIds();

    var inserted = 0;
    for (final d in detected) {
      final key = _key(d.categoryName, d.amount, d.cadence);
      if (existingKeys.contains(key)) continue;
      final cat = catByName[d.categoryName];
      if (cat == null) continue; // category gone — can't create a valid FK
      if (ignored.contains(cat.id)) continue; // user marked "not a bill"

      final last = DateTime.tryParse(d.lastDate);
      var nextDue = last != null ? _addCadence(last, d.cadence) : now;
      // Roll forward until the due date is today or later.
      while (nextDue.isBefore(_today())) {
        nextDue = _addCadence(nextDue, d.cadence);
      }

      final ms = now.millisecondsSinceEpoch;
      await _db.recurringItemsDao.upsert(RecurringItemsCompanion.insert(
        id: _uuid.v4(),
        name: d.categoryName,
        amount: d.amount,
        categoryId: cat.id,
        modeId: Value(modeByName[d.modeName]?.id),
        cadence: Value(d.cadence),
        nextDueDate: _day(nextDue),
        lastSeenDate: Value(d.lastDate),
        source: const Value('detected'),
        createdAt: ms,
        updatedAt: ms,
      ));
      existingKeys.add(key);
      inserted++;
    }
    return inserted;
  }

  String _key(String name, double amount, String cadence) =>
      '${name.toLowerCase()}|${amount.toStringAsFixed(2)}|$cadence';

  DateTime _addCadence(DateTime d, String cadence) {
    switch (cadence) {
      case 'weekly':
        return d.add(const Duration(days: 7));
      case 'fortnightly':
        return d.add(const Duration(days: 14));
      case 'monthly':
        return DateTime(d.year, d.month + 1, d.day);
      case 'quarterly':
        return DateTime(d.year, d.month + 3, d.day);
      case 'yearly':
        return DateTime(d.year + 1, d.month, d.day);
      default:
        // "every N days" → parse N; fall back to 30 days.
        final n = RegExp(r'(\d+)').firstMatch(cadence)?.group(1);
        return d.add(Duration(days: n == null ? 30 : int.parse(n)));
    }
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _day(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();
}
