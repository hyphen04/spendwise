import 'package:drift/drift.dart';

/// A single AI Copilot chat conversation (a "thread").
///
/// Stores only the thread metadata here — messages live in [AiMessages].
/// `title` is auto-set from the first user message and is user-editable;
/// `preview` is a short snippet of the last message for the chat list.
class AiThreads extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get preview => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}