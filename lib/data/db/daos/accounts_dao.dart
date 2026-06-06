import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/accounts_table.dart';

part 'accounts_dao.g.dart';

@DriftAccessor(tables: [Accounts])
class AccountsDao extends DatabaseAccessor<AppDatabase>
    with _$AccountsDaoMixin {
  AccountsDao(super.db);

  Stream<List<Account>> watchAll() =>
      (select(accounts)
            ..where((a) => a.isArchived.equals(false))
            ..orderBy([(a) => OrderingTerm.asc(a.name)]))
          .watch();

  Future<List<Account>> getAllActive() =>
      (select(accounts)..where((a) => a.isArchived.equals(false))).get();

  Future<Account?> getById(String id) =>
      (select(accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<void> upsert(AccountsCompanion entry) =>
      into(accounts).insertOnConflictUpdate(entry);

  Future<void> archive(String id) =>
      (update(accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(
          isArchived: const Value(true),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<int> hardDelete(String id) =>
      (delete(accounts)..where((a) => a.id.equals(id))).go();
}
