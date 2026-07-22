import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

/// Persistence for AI Copilot chat history (threads + messages).
///
/// Only the visible user/assistant messages are stored here — the hidden
/// system/context preamble (the anonymized financial summary) is rebuilt in
/// memory per session and is never persisted. Stored messages are local user
/// content; nothing here sends data anywhere.
class AiChatRepository {
  AiChatRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  static const int _previewLimit = 80;
  static const int _titleLimit = 48;

  // ── Threads ──────────────────────────────────────────────────────────────

  Stream<List<AiThread>> watchThreads() => _db.aiThreadsDao.watchAll();

  Stream<AiThread?> watchThread(String id) => _db.aiThreadsDao.watchById(id);

  /// One-shot fetch of a thread row (used by the auto-titler to detect a
  /// manual rename done while the title LLM call was in flight).
  Future<AiThread?> getThread(String id) => _db.aiThreadsDao.getById(id);

  Future<AiThread> createThread({String? title}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await _db.aiThreadsDao.upsert(AiThreadsCompanion.insert(
      id: id,
      createdAt: now,
      updatedAt: now,
      title: title == null ? const Value.absent() : Value(title),
    ));
    return AiThread(
      id: id,
      title: title ?? '',
      preview: '',
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      folder: '',
    );
  }

  Future<void> renameThread(String id, String title) =>
      _db.aiThreadsDao.rename(id, title.trim());

  /// Delete a thread and all of its messages in one transaction.
  Future<void> deleteThread(String id) async {
    await _db.transaction(() async {
      await _db.aiMessagesDao.deleteForThread(id);
      await _db.aiThreadsDao.hardDelete(id);
    });
  }

  /// Delete many threads (+ their messages) in one transaction.
  Future<void> bulkDelete(List<String> ids) async {
    if (ids.isEmpty) return;
    await _db.transaction(() async {
      for (final id in ids) {
        await _db.aiMessagesDao.deleteForThread(id);
        await _db.aiThreadsDao.hardDelete(id);
      }
    });
  }

  // ── Organization: pin / archive / folder ───────────────────────────────────
  // Local-only metadata on ai_threads; never reaches the AI (see DAO comments).

  Future<void> pinThread(String id, bool pinned) =>
      _db.aiThreadsDao.setPinned(id, pinned);

  Future<void> archiveThread(String id, bool archived) =>
      _db.aiThreadsDao.setArchived(id, archived);

  /// Move a thread into [folder]; pass '' to unfile.
  Future<void> moveToFolder(String id, String folder) =>
      _db.aiThreadsDao.setFolder(id, folder);

  Future<void> bulkPin(List<String> ids, bool pinned) =>
      _db.aiThreadsDao.bulkSetPinned(ids, pinned);

  Future<void> bulkArchive(List<String> ids, bool archived) =>
      _db.aiThreadsDao.bulkSetArchived(ids, archived);

  Future<void> bulkMove(List<String> ids, String folder) =>
      _db.aiThreadsDao.bulkSetFolder(ids, folder);

  Future<void> renameFolder(String oldName, String newName) =>
      _db.aiThreadsDao.renameFolder(oldName, newName);

  Future<void> deleteFolder(String name) =>
      _db.aiThreadsDao.deleteFolder(name);

  Stream<List<String>> watchFolders() => _db.aiThreadsDao.watchFolders();

  // ── Messages ─────────────────────────────────────────────────────────────

  Stream<List<AiMessage>> watchMessages(String threadId) =>
      _db.aiMessagesDao.watchForThread(threadId);

  Future<List<AiMessage>> getMessages(String threadId) =>
      _db.aiMessagesDao.forThread(threadId);

  Future<int> countMessages(String threadId) =>
      _db.aiMessagesDao.countForThread(threadId);

  /// Insert a user message. Auto-sets the thread title from this message when
  /// the title is still empty, and updates the thread's preview + updatedAt.
  Future<AiMessage> addUserMessage(String threadId, String content) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await _db.aiMessagesDao.insertRow(AiMessagesCompanion.insert(
      id: id,
      threadId: threadId,
      role: 'user',
      content: Value(content),
      createdAt: now,
    ));

    // Title from the first user message if not yet set.
    final thread = await _db.aiThreadsDao.getById(threadId);
    final preview = _preview(content);
    if (thread != null && thread.title.isEmpty) {
      await _db.aiThreadsDao.rename(threadId, _titleFrom(content));
    } else {
      await _db.aiThreadsDao.touch(threadId, preview: preview);
    }
    return AiMessage(
      id: id,
      threadId: threadId,
      role: 'user',
      content: content,
      isError: false,
      createdAt: now,
    );
  }

  /// Insert an assistant message (the final streamed reply, or an error bubble).
  Future<AiMessage> addAssistantMessage(
    String threadId,
    String content, {
    bool isError = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await _db.aiMessagesDao.insertRow(AiMessagesCompanion.insert(
      id: id,
      threadId: threadId,
      role: 'assistant',
      content: Value(content),
      isError: Value(isError),
      createdAt: now,
    ));
    await _db.aiThreadsDao.touch(threadId, preview: _preview(content));
    return AiMessage(
      id: id,
      threadId: threadId,
      role: 'assistant',
      content: content,
      isError: isError,
      createdAt: now,
    );
  }

  Future<void> updateMessageContent(String id, String content) =>
      _db.aiMessagesDao.updateContent(id, content);

  /// Delete a single message. If it's a user message, also delete the
  /// assistant reply that immediately followed it (keeps the thread coherent).
  Future<void> deleteMessage(String id) async {
    final msg = await (_db.select(_db.aiMessages)
          ..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    if (msg == null) return;
    await _db.aiMessagesDao.hardDelete(id);
    if (msg.role == 'user') {
      // Drop the next assistant message after this one, if any.
      final next = await (_db.select(_db.aiMessages)
            ..where((m) =>
                m.threadId.equals(msg.threadId) &
                m.createdAt.isBiggerThanValue(msg.createdAt))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)])
            ..limit(1))
          .getSingleOrNull();
      if (next != null && next.role == 'assistant') {
        await _db.aiMessagesDao.hardDelete(next.id);
      }
    }
    await _refreshPreview(msg.threadId);
  }

  /// Delete every message in [threadId] created strictly after [createdAt].
  Future<void> deleteMessagesAfter(String threadId, int createdAt) async {
    await _db.aiMessagesDao.deleteAfter(threadId, createdAt);
    await _refreshPreview(threadId);
  }

  /// Recompute the thread's preview from its newest message.
  Future<void> _refreshPreview(String threadId) async {
    final last = await (_db.select(_db.aiMessages)
          ..where((m) => m.threadId.equals(threadId))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    await _db.aiThreadsDao.touch(threadId, preview: _preview(last?.content ?? ''));
  }

  String _preview(String content) {
    final t = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= _previewLimit) return t;
    return '${t.substring(0, _previewLimit)}…';
  }

  String _titleFrom(String content) {
    final t = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= _titleLimit) return t;
    return '${t.substring(0, _titleLimit)}…';
  }
}