import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:uuid/uuid.dart';

import 'daos/accounts_dao.dart';
import 'daos/ai_messages_dao.dart';
import 'daos/ai_threads_dao.dart';
import 'daos/budgets_dao.dart';
import 'daos/categories_dao.dart';
import 'daos/custom_reports_dao.dart';
import 'daos/dues_dao.dart';
import 'daos/goals_dao.dart';
import 'daos/modes_dao.dart';
import 'daos/recurring_items_dao.dart';
import 'daos/transactions_dao.dart';
import 'tables/accounts_table.dart';
import 'tables/ai_messages_table.dart';
import 'tables/ai_threads_table.dart';
import 'tables/budgets_table.dart';
import 'tables/categories_table.dart';
import 'tables/custom_reports_table.dart';
import 'tables/due_contacts_table.dart';
import 'tables/due_entries_table.dart';
import 'tables/due_settlements_table.dart';
import 'tables/goals_table.dart';
import 'tables/ignored_recurring_table.dart';
import 'tables/modes_table.dart';
import 'tables/recurring_items_table.dart';
import 'tables/transactions_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Modes,
    Transactions,
    Budgets,
    DueContacts,
    DueEntries,
    DueSettlements,
    AiThreads,
    AiMessages,
    RecurringItems,
    Goals,
    CustomReports,
    IgnoredRecurring,
  ],
  daos: [
    AccountsDao,
    CategoriesDao,
    ModesDao,
    TransactionsDao,
    BudgetsDao,
    DuesDao,
    AiThreadsDao,
    AiMessagesDao,
    RecurringItemsDao,
    GoalsDao,
    CustomReportsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// Well-known ID for the internal "Transfer" category.
  /// Archived so it never appears in user-facing pickers.
  static const kTransferCategoryId = 'system-transfer-cat-0000-000000000001';

  @override
  int get schemaVersion => 18;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (details.wasCreated) {
            await _seedDefaults();
          }
        },
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await _migrateV1toV2(m);
          }
          if (from < 4) {
            await customStatement('DROP TABLE IF EXISTS recurring_rules');
          }
          if (from < 5) {
            // ignore: experimental_member_use
            await m.alterTable(TableMigration(transactions));
          }
          if (from == 5) {
            // ignore: experimental_member_use
            await m.alterTable(TableMigration(transactions));
          }
          if (from < 7) {
            // Safely create the 3 new Dues tables
            await m.createAll();
          }
          if (from < 8) {
            final result = await customSelect('PRAGMA table_info(due_contacts)').get();
            final hasColumn = result.any((row) => row.data['name'] == 'default_category_id');
            if (!hasColumn) {
              await m.addColumn(dueContacts, dueContacts.defaultCategoryId);
            }
          }
          if (from < 9) {
            // Migrate transfer kinds
            await customStatement('''
              UPDATE transactions SET kind = 'transfer_out' 
              WHERE kind = 'transfer' 
              AND id IN (
                SELECT t1.id FROM transactions t1
                JOIN transactions t2 ON t1.transfer_pair_id = t2.id
                WHERE t1.kind = 'transfer' AND t1.rowid < t2.rowid
              )
            ''');
            await customStatement('''
              UPDATE transactions SET kind = 'transfer_in'
              WHERE kind = 'transfer'
            ''');
          }
          if (from < 10) {
            // Device-contact enrichment: add phone / photoPath / deviceContactId
            // to due_contacts. All nullable, so no DEFAULT is needed and existing
            // rows are untouched. Guard each column so re-runs are safe.
            final cols = await customSelect('PRAGMA table_info(due_contacts)').get();
            final names = cols.map((r) => r.data['name'] as String).toSet();
            if (!names.contains('phone')) {
              await m.addColumn(dueContacts, dueContacts.phone);
            }
            if (!names.contains('photo_path')) {
              await m.addColumn(dueContacts, dueContacts.photoPath);
            }
            if (!names.contains('device_contact_id')) {
              await m.addColumn(dueContacts, dueContacts.deviceContactId);
            }
          }
          if (from < 11) {
            // Multi-number support: add `phones` (JSON array of {number, label})
            // so a contact can keep every number from a device contact and the
            // user picks which to call/WhatsApp at action time. Nullable → no
            // DEFAULT needed; the legacy `phone` column stays as the primary.
            final cols =
                await customSelect('PRAGMA table_info(due_contacts)').get();
            final names = cols.map((r) => r.data['name'] as String).toSet();
            if (!names.contains('phones')) {
              await m.addColumn(dueContacts, dueContacts.phones);
            }
          }
          if (from < 12) {
            // AI Copilot chat history: two brand-new tables (no existing rows
            // to migrate, so plain createTable is safe — no ALTER COLUMN
            // concerns). Threads hold metadata; messages hold the per-chat
            // turns. Deletion of a thread removes its messages in a transaction
            // in the repository (no FK declared).
            await m.createTable(aiThreads);
            await m.createTable(aiMessages);
          }
          if (from < 13) {
            // Bills & subscription reminders: a brand-new table (no existing
            // rows to migrate). All nullable-or-defaulted columns except the
            // required id/name/amount/categoryId/nextDueDate/createdAt/updatedAt,
            // so plain createTable is safe — no NOT NULL-without-DEFAULT risk.
            // Detected items are seeded lazily from the user's expense history
            // by RecurringRepository.autoRefreshFromTransactions() on first
            // open post-upgrade (idempotent).
            await m.createTable(recurringItems);
          }
          if (from < 14) {
            // Goals & savings targets: a brand-new table (no existing rows to
            // migrate). All nullable-or-defaulted columns except the required
            // id/name/targetAmount/createdAt/updatedAt, so plain createTable is
            // safe — no NOT NULL-without-DEFAULT risk. No PII; never in the AI
            // schema metadata.
            await m.createTable(goals);
          }
          if (from < 15) {
            // Custom Reports: a brand-new table (no existing rows to migrate).
            // Stores user-authored report specs as JSON — field refs + filters
            // only, no PII (no notes / contact names / receipt paths / raw
            // rows), and never sent to the AI. All columns are non-nullable but
            // have no NOT NULL-without-DEFAULT risk: id/name/specJson/
            // createdAt/updatedAt are required at insert by the DAO, so plain
            // createTable is safe.
            await m.createTable(customReports);
          }
          if (from < 16) {
            // Tags feature removal: the tags + transaction_tags tables had no
            // UI to create or assign tags, so they are dropped entirely. Order
            // matters — drop the join table (transaction_tags) before its parent
            // (tags). IF EXISTS makes this safe to re-run. Any tag data a user
            // previously imported via JSON backup is deleted on upgrade.
            await customStatement('DROP TABLE IF EXISTS transaction_tags');
            await customStatement('DROP TABLE IF EXISTS tags');
          }
          if (from < 17) {
            // `ignored_recurring` — categories the user marked "not a bill" so
            // the recurring detector skips them on re-detect. Additive; no PII
            // (category id only); never queried by AI tools / schema_metadata.
            await m.createTable(ignoredRecurring);
          }
          if (from < 18) {
            // Chat organization: pin, archive, named folder on `ai_threads`.
            // Additive; all columns defaulted so existing rows are untouched.
            // Local-only organizational metadata — never in schema_metadata,
            // never read by AiPayloadBuilder / AI tools (ai_threads is a PII
            // table kept off the AI schema entirely).
            //
            // Guard each column: `m.createTable(aiThreads)` at `from < 12`
            // (and `m.createAll()` at `from < 7`) build the FULL current
            // schema, which already includes pinned/archived/folder. So for
            // anyone upgrading from before ai_threads existed (e.g. v2.14,
            // schema v9), these columns are already present and a blind
            // `ALTER TABLE ... ADD COLUMN` throws "duplicate column name",
            // aborting onUpgrade BEFORE Drift bumps user_version (Drift only
            // sets user_version after onUpgrade returns cleanly). That leaves
            // the DB half-migrated (new tables created, version still 9) and
            // un-openable — every launch re-runs the migration and throws
            // again, so the Recovery screen's restore (which copies an old
            // replica back) just re-triggers the same crash. Only add what's
            // missing. This also recovers users already stuck in that
            // half-migrated state on the next launch: the guarded adds no-op,
            // onUpgrade completes, and user_version finally advances to 18.
            final aiThreadsCols =
                await customSelect('PRAGMA table_info(ai_threads)').get();
            final aiThreadsColNames =
                aiThreadsCols.map((r) => r.data['name'] as String).toSet();
            if (!aiThreadsColNames.contains('pinned')) {
              await m.addColumn(aiThreads, aiThreads.pinned);
            }
            if (!aiThreadsColNames.contains('archived')) {
              await m.addColumn(aiThreads, aiThreads.archived);
            }
            if (!aiThreadsColNames.contains('folder')) {
              await m.addColumn(aiThreads, aiThreads.folder);
            }
          }
        },
      );

  // ── Migration v1 → v2 ───────────────────────────────────────────────────

  Future<void> _migrateV1toV2(Migrator m) async {
    final uuidGen = const Uuid();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Step 1: Read all old data (FKs still OFF at this point)
    List<QueryRow> oldModes = [];
    List<QueryRow> oldCategories = [];
    List<QueryRow> oldTransactions = [];

    try {
      oldModes =
          await customSelect('SELECT * FROM transaction_modes').get();
    } catch (_) {}
    try {
      oldCategories =
          await customSelect('SELECT * FROM categories').get();
    } catch (_) {}
    try {
      oldTransactions =
          await customSelect('SELECT * FROM transactions').get();
    } catch (_) {}

    // Step 2: Drop old tables so m.createAll() can recreate with new schema
    await customStatement('DROP TABLE IF EXISTS transactions');
    await customStatement('DROP TABLE IF EXISTS categories');
    await customStatement('DROP TABLE IF EXISTS transaction_modes');

    // Step 3: Create all 8 new tables
    await m.createAll();

    // System categories (must exist before any transaction is inserted)
    await _seedSystemCategories(now);

    // Step 4: Default Cash account (all old transactions are assigned here)
    final cashId = uuidGen.v4();
    await into(accounts).insert(AccountsCompanion.insert(
      id: cashId,
      name: 'Cash',
      icon: '💵',
      color: '#059669',
      openingBalance: const Value(0.0),
      currency: const Value('INR'),
      createdAt: now,
      updatedAt: now,
    ));

    // Step 5: "Income" catch-all category (replaces old categoryId = 0)
    final incomeCatId = uuidGen.v4();
    await into(categories).insert(CategoriesCompanion.insert(
      id: incomeCatId,
      name: 'Income',
      icon: '💰',
      color: const Value('#059669'),
      kind: const Value('income'),
      createdAt: now,
      updatedAt: now,
    ));

    // Step 6: Migrate old categories; build int→UUID map
    final categoryIdMap = <int, String>{0: incomeCatId};
    for (final row in oldCategories) {
      final oldIntId = row.data['id'] as int;
      final newId = uuidGen.v4();
      categoryIdMap[oldIntId] = newId;
      await into(categories).insert(CategoriesCompanion.insert(
        id: newId,
        name: row.data['name'] as String,
        icon: row.data['icon'] as String,
        color: const Value('#059669'),
        kind: const Value('expense'),
        createdAt: now,
        updatedAt: now,
      ));
    }

    // Step 7: Migrate old modes; build int→UUID map
    final modeIdMap = <int, String>{};
    for (final row in oldModes) {
      final oldIntId = row.data['id'] as int;
      final newId = uuidGen.v4();
      modeIdMap[oldIntId] = newId;
      await into(modes).insert(ModesCompanion.insert(
        id: newId,
        name: row.data['name'] as String,
        icon: row.data['icon'] as String,
        createdAt: now,
        updatedAt: now,
      ));
    }

    // Fallback mode ID if modeIdMap is empty or a transaction references unknown mode
    final fallbackModeId = modeIdMap.values.isNotEmpty
        ? modeIdMap.values.first
        : uuidGen.v4();
    if (modeIdMap.isEmpty) {
      await into(modes).insert(ModesCompanion.insert(
        id: fallbackModeId,
        name: 'Cash',
        icon: '💵',
        createdAt: now,
        updatedAt: now,
      ));
    }

    // Fallback category (if old data had unknown categories)
    final fallbackCatId = categoryIdMap[1] ?? incomeCatId;

    // Step 8: Migrate old transactions
    for (final row in oldTransactions) {
      final rawCatId = row.data['categoryId'];
      final rawModeId = row.data['modeId'];
      final oldCatInt = rawCatId is int ? rawCatId : 0;
      final oldModeInt = rawModeId is int ? rawModeId : 1;
      final isExpenseInt = row.data['isExpense'] as int? ?? 1;
      final isExpense = isExpenseInt == 1;

      final newCatId = categoryIdMap[oldCatInt] ?? fallbackCatId;
      final newModeId = modeIdMap[oldModeInt] ?? fallbackModeId;
      final txKind = isExpense ? 'expense' : 'income';
      final legacyId = row.data['id']?.toString();

      await into(transactions).insert(TransactionsCompanion.insert(
        id: uuidGen.v4(),
        amount: (row.data['amount'] as num?)?.toDouble() ?? 0.0,
        transactionDate: row.data['date'] as String? ?? DateTime.now().toIso8601String(),
        accountId: cashId,
        categoryId: newCatId,
        modeId: newModeId,
        kind: Value(txKind),
        legacyId: Value(legacyId),
        createdAt: now,
        updatedAt: now,
      ));
    }

    // Step 9: Seed defaults for modes/categories if old data was empty
    if (oldCategories.isEmpty) {
      await _seedDefaultCategories(uuidGen, now, skipIncome: true);
    }
    if (oldModes.isEmpty) {
      await _seedDefaultModes(uuidGen, now);
    }

    debugPrint('Migration v1 → v2 complete: '
        '${oldTransactions.length} transactions, '
        '${oldCategories.length} categories, '
        '${oldModes.length} modes migrated.');
  }

  // ── Seeding (fresh install) ──────────────────────────────────────────────

  Future<void> _seedDefaults() async {
    final uuidGen = const Uuid();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Default Cash account
    await into(accounts).insert(AccountsCompanion.insert(
      id: uuidGen.v4(),
      name: 'Cash',
      icon: '💵',
      color: '#059669',
      createdAt: now,
      updatedAt: now,
    ));

    // Default Bank account
    await into(accounts).insert(AccountsCompanion.insert(
      id: uuidGen.v4(),
      name: 'Bank Account',
      icon: '🏦',
      color: '#0284C7',
      createdAt: now,
      updatedAt: now,
    ));

    await _seedSystemCategories(now);
    await _seedDefaultCategories(uuidGen, now, skipIncome: false);
    await _seedDefaultModes(uuidGen, now);
  }

  Future<void> _seedDefaultCategories(
    Uuid uuidGen,
    int now, {
    required bool skipIncome,
  }) async {
    final expenseSeeds = [
      ('Food & Dining', '🍴', '#DC2626'),
      ('Transport', '🚗', '#D97706'),
      ('Rent & Housing', '🏠', '#7C3AED'),
      ('Shopping', '🛍️', '#EC4899'),
      ('Entertainment', '🎬', '#0284C7'),
      ('Health', '💊', '#059669'),
      ('Education', '📚', '#B45309'),
      ('Other', '📦', '#475569'),
    ];
    final incomeSeeds = [
      ('Income', '💰', '#059669'),
      ('Salary', '💼', '#059669'),
      ('Freelance', '💻', '#0284C7'),
      ('Investment', '📈', '#7C3AED'),
    ];

    for (final (name, icon, color) in expenseSeeds) {
      await into(categories).insert(CategoriesCompanion.insert(
        id: uuidGen.v4(),
        name: name,
        icon: icon,
        color: Value(color),
        kind: const Value('expense'),
        createdAt: now,
        updatedAt: now,
      ));
    }

    if (!skipIncome) {
      for (final (name, icon, color) in incomeSeeds) {
        await into(categories).insert(CategoriesCompanion.insert(
          id: uuidGen.v4(),
          name: name,
          icon: icon,
          color: Value(color),
          kind: const Value('income'),
          createdAt: now,
          updatedAt: now,
        ));
      }
    }
  }

  Future<void> _seedSystemCategories(int now) async {
    await into(categories).insertOnConflictUpdate(CategoriesCompanion.insert(
      id: kTransferCategoryId,
      name: 'Transfer',
      icon: '⇄',
      color: const Value('#0284C7'),
      kind: const Value('both'),
      isArchived: const Value(true),
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> _seedDefaultModes(Uuid uuidGen, int now) async {
    final modeSeeds = [
      ('Cash', '💵'),
      ('Online / UPI', '📱'),
      ('Card', '💳'),
      ('Net Banking', '🌐'),
      ('Cheque', '📄'),
      ('Other', '💰'),
    ];
    for (final (name, icon) in modeSeeds) {
      await into(modes).insert(ModesCompanion.insert(
        id: uuidGen.v4(),
        name: name,
        icon: icon,
        createdAt: now,
        updatedAt: now,
      ));
    }
  }
}

// ── Database connection ────────────────────────────────────────────────────

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'expenses.db'));

    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        // Journal mode WAL for better concurrent read performance
        rawDb.execute('PRAGMA journal_mode=WAL');
      },
    );
  });
}
