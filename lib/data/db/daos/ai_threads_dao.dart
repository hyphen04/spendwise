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

  // ── Organization (v18): pin / archive / folder ─────────────────────────────
  // These columns are local-only metadata; ai_threads is never part of the AI
  // schema. Single-row setters bump `updatedAt` so sorting stays fresh.

  Future<void> setPinned(String id, bool pinned) =>
      (update(aiThreads)..where((t) => t.id.equals(id))).write(
        AiThreadsCompanion(
          pinned: Value(pinned),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> setArchived(String id, bool archived) =>
      (update(aiThreads)..where((t) => t.id.equals(id))).write(
        AiThreadsCompanion(
          archived: Value(archived),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Set the folder name. Pass an empty string to unfile.
  Future<void> setFolder(String id, String folder) =>
      (update(aiThreads)..where((t) => t.id.equals(id))).write(
        AiThreadsCompanion(
          folder: Value(folder),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  // ── Bulk (one statement per op) ────────────────────────────────────────────

  Future<void> bulkSetPinned(List<String> ids, bool pinned) {
    if (ids.isEmpty) return Future.value();
    return (update(aiThreads)..where((t) => t.id.isIn(ids))).write(
      AiThreadsCompanion(
        pinned: Value(pinned),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> bulkSetArchived(List<String> ids, bool archived) {
    if (ids.isEmpty) return Future.value();
    return (update(aiThreads)..where((t) => t.id.isIn(ids))).write(
      AiThreadsCompanion(
        archived: Value(archived),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> bulkSetFolder(List<String> ids, String folder) {
    if (ids.isEmpty) return Future.value();
    return (update(aiThreads)..where((t) => t.id.isIn(ids))).write(
      AiThreadsCompanion(
        folder: Value(folder),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  // ── Folder management (folder is a text column, not a separate table) ───────

  /// Rename a folder by rewriting every thread currently in [oldName].
  Future<void> renameFolder(String oldName, String newName) {
    if (oldName.isEmpty || oldName == newName) return Future.value();
    return (update(aiThreads)..where((t) => t.folder.equals(oldName))).write(
      AiThreadsCompanion(folder: Value(newName)),
    );
  }

  /// Delete a folder by clearing `folder` on every thread in [name] (they fall
  /// back to "unfiled"). The folder text value disappears from `watchFolders`.
  Future<void> deleteFolder(String name) {
    if (name.isEmpty) return Future.value();
    return (update(aiThreads)..where((t) => t.folder.equals(name))).write(
      AiThreadsCompanion(folder: const Value('')),
    );
  }

  /// Distinct non-empty folder names, alpha-sorted. Emits on any ai_threads
  /// change (Drift watches the table the query reads).
  Stream<List<String>> watchFolders() {
    final q = selectOnly(aiThreads)
      ..addColumns([aiThreads.folder])
      ..where(aiThreads.folder.isNotIn(const ['']))
      ..groupBy([aiThreads.folder])
      ..orderBy([OrderingTerm.asc(aiThreads.folder)]);
    return q.map((row) => row.read(aiThreads.folder)!).watch();
  }
}