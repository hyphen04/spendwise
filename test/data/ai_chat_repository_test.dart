import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/db/app_database.dart';
import 'package:spendwise/data/repositories/ai_chat_repository.dart';

/// Direct DAO access for verification (the repository exposes streams, but the
/// tests assert on the persisted row state).
Future<AiThread?> _thread(AppDatabase db, String id) =>
    db.aiThreadsDao.getById(id);

void main() {
  late AppDatabase db;
  late AiChatRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get(); // force creation
    repo = AiChatRepository(db);
  });

  tearDown(() => db.close());

  group('pin / archive', () {
    test('pinThread toggles pinned and leaves other fields', () async {
      final t = await repo.createThread();
      await repo.pinThread(t.id, true);
      expect((await _thread(db, t.id))!.pinned, isTrue);
      await repo.pinThread(t.id, false);
      expect((await _thread(db, t.id))!.pinned, isFalse);
    });

    test('archiveThread toggles archived', () async {
      final t = await repo.createThread();
      await repo.archiveThread(t.id, true);
      expect((await _thread(db, t.id))!.archived, isTrue);
      await repo.archiveThread(t.id, false);
      expect((await _thread(db, t.id))!.archived, isFalse);
    });
  });

  group('folders', () {
    test('moveToFolder sets folder; watchFolders lists distinct names sorted',
        () async {
      final a = await repo.createThread();
      final b = await repo.createThread();
      await repo.moveToFolder(a.id, 'Reports');
      await repo.moveToFolder(b.id, 'Budget');
      expect((await _thread(db, a.id))!.folder, 'Reports');
      expect((await _thread(db, b.id))!.folder, 'Budget');

      final folders = await repo.watchFolders().first;
      expect(folders, ['Budget', 'Reports']); // alpha-sorted
    });

    test('moveToFolder with empty string unfiles', () async {
      final t = await repo.createThread();
      await repo.moveToFolder(t.id, 'Budget');
      await repo.moveToFolder(t.id, '');
      expect((await _thread(db, t.id))!.folder, '');
      expect(await repo.watchFolders().first, isEmpty);
    });

    test('renameFolder rewrites every thread in the old name', () async {
      final a = await repo.createThread();
      final b = await repo.createThread();
      await repo.moveToFolder(a.id, 'Old');
      await repo.moveToFolder(b.id, 'Old');
      await repo.renameFolder('Old', 'New');
      expect((await _thread(db, a.id))!.folder, 'New');
      expect((await _thread(db, b.id))!.folder, 'New');
      expect(await repo.watchFolders().first, ['New']);
    });

    test('deleteFolder clears folder on its threads', () async {
      final a = await repo.createThread();
      await repo.moveToFolder(a.id, 'Tmp');
      await repo.deleteFolder('Tmp');
      expect((await _thread(db, a.id))!.folder, '');
      expect(await repo.watchFolders().first, isEmpty);
    });
  });

  group('bulk ops', () {
    test('bulkDelete removes the threads and their messages', () async {
      final a = await repo.createThread();
      final b = await repo.createThread();
      final c = await repo.createThread();
      await repo.addUserMessage(a.id, 'hi a');
      await repo.addUserMessage(b.id, 'hi b');
      await repo.addUserMessage(c.id, 'hi c');

      await repo.bulkDelete([a.id, b.id]);

      expect(await _thread(db, a.id), isNull);
      expect(await _thread(db, b.id), isNull);
      expect(await _thread(db, c.id), isNotNull);
      expect(await db.aiMessagesDao.countForThread(a.id), 0);
      expect(await db.aiMessagesDao.countForThread(b.id), 0);
      expect(await db.aiMessagesDao.countForThread(c.id), greaterThan(0));
    });

    test('bulkPin / bulkArchive / bulkMove update only the listed ids',
        () async {
      final a = await repo.createThread();
      final b = await repo.createThread();
      final c = await repo.createThread();

      await repo.bulkPin([a.id, b.id], true);
      expect((await _thread(db, a.id))!.pinned, isTrue);
      expect((await _thread(db, b.id))!.pinned, isTrue);
      expect((await _thread(db, c.id))!.pinned, isFalse);

      await repo.bulkPin([a.id], false);
      expect((await _thread(db, a.id))!.pinned, isFalse);
      expect((await _thread(db, b.id))!.pinned, isTrue);

      await repo.bulkArchive([a.id, c.id], true);
      expect((await _thread(db, a.id))!.archived, isTrue);
      expect((await _thread(db, c.id))!.archived, isTrue);
      expect((await _thread(db, b.id))!.archived, isFalse);

      await repo.bulkMove([a.id, b.id], 'Budget');
      expect((await _thread(db, a.id))!.folder, 'Budget');
      expect((await _thread(db, b.id))!.folder, 'Budget');
      expect((await _thread(db, c.id))!.folder, '');
    });

    test('bulk ops are no-ops on an empty id list', () async {
      final a = await repo.createThread();
      await repo.bulkPin([], true);
      await repo.bulkArchive([], true);
      await repo.bulkMove([], 'Budget');
      await repo.bulkDelete([]);
      final t = await _thread(db, a.id);
      expect(t, isNotNull);
      expect(t!.pinned, isFalse);
      expect(t.archived, isFalse);
      expect(t.folder, '');
    });
  });
}