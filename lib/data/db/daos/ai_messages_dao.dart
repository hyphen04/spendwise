import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/ai_messages_table.dart';

part 'ai_messages_dao.g.dart';

@DriftAccessor(tables: [AiMessages])
class AiMessagesDao extends DatabaseAccessor<AppDatabase>
    with _$AiMessagesDaoMixin {
  AiMessagesDao(super.db);

  /// Messages for a thread, oldest first (chat order).
  Stream<List<AiMessage>> watchForThread(String threadId) =>
      (select(aiMessages)
            ..where((m) => m.threadId.equals(threadId))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .watch();

  Future<List<AiMessage>> forThread(String threadId) =>
      (select(aiMessages)
            ..where((m) => m.threadId.equals(threadId))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .get();

  Future<void> insertRow(AiMessagesCompanion entry) =>
      into(aiMessages).insert(entry);

  Future<void> updateContent(String id, String content) =>
      (update(aiMessages)..where((m) => m.id.equals(id))).write(
        AiMessagesCompanion(content: Value(content)),
      );

  Future<int> hardDelete(String id) =>
      (delete(aiMessages)..where((m) => m.id.equals(id))).go();

  /// Delete every message in a thread created strictly after [createdAt].
  /// Used by edit-and-regenerate to drop the old reply and everything after.
  Future<int> deleteAfter(String threadId, int createdAt) =>
      (delete(aiMessages)
            ..where((m) =>
                m.threadId.equals(threadId) & m.createdAt.isBiggerThanValue(createdAt)))
          .go();

  Future<int> deleteForThread(String threadId) =>
      (delete(aiMessages)..where((m) => m.threadId.equals(threadId))).go();

  Future<int> countForThread(String threadId) async {
    final row = await (customSelect(
      'SELECT COUNT(*) AS cnt FROM ai_messages WHERE thread_id = ?',
      variables: [Variable.withString(threadId)],
    )).getSingle();
    return row.read<int>('cnt');
  }
}