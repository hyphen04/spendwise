import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/ai_threads_table.dart';

part 'ai_threads_dao.g.dart';

@DriftAccessor(tables: [AiThreads])
class AiThreadsDao extends DatabaseAccessor<AppDatabase> with _$AiThreadsDaoMixin {
  AiThreadsDao(super.db);

  /// All threads that have at least one message, most-recently-active first.
  ///
  /// Empty threads (created up-front when "New chat" is tapped but never sent
  /// to) are excluded so they never flash in the chat list before the
  /// notifier's dispose-time prune removes the row. The prune still runs for
  /// DB hygiene; this filter just keeps them out of the UI. It also hides any
  /// thread whose messages were all deleted.
  Stream<List<AiThread>> watchAll() {
    final db = attachedDatabase;
    final threadsWithMessages = db.selectOnly(db.aiMessages)
      ..addColumns([db.aiMessages.threadId])
      ..groupBy([db.aiMessages.threadId]);
    return (select(aiThreads)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..where((t) => t.id.isInQuery(threadsWithMessages)))
        .watch();
  }

  Future<AiThread?> getById(String id) =>
      (select(aiThreads)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<AiThread?> watchById(String id) =>
      (select(aiThreads)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> upsert(AiThreadsCompanion entry) =>
      into(aiThreads).insertOnConflictUpdate(entry);

  Future<void> rename(String id, String title) =>
      (update(aiThreads)..where((t) => t.id.equals(id))).write(
        AiThreadsCompanion(
          title: Value(title),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> setPreview(String id, String preview) =>
      (update(aiThreads)..where((t) => t.id.equals(id))).write(
        AiThreadsCompanion(preview: Value(preview)),
      );

  /// Bump `updatedAt` (and optionally set preview) without changing the title.
  Future<void> touch(String id, {String? preview}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final companion = preview == null
        ? AiThreadsCompanion(updatedAt: Value(now))
        : AiThreadsCompanion(updatedAt: Value(now), preview: Value(preview));
    return (update(aiThreads)..where((t) => t.id.equals(id))).write(companion);
  }

  Future<int> hardDelete(String id) =>
      (delete(aiThreads)..where((t) => t.id.equals(id))).go();
}