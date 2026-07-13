import 'package:drift/drift.dart';

/// One message in an AI Copilot chat thread.
///
/// `role` is 'user' or 'assistant' (the hidden system/context preamble is
/// rebuilt in memory per session and is never persisted). `isError` marks an
/// assistant error bubble. No foreign key is declared here — thread deletion
/// removes its messages in a transaction in the repository (matches the
/// codebase style; `PRAGMA foreign_keys = ON` is set in `beforeOpen`).
class AiMessages extends Table {
  TextColumn get id => text()();
  TextColumn get threadId => text()();
  TextColumn get role => text()(); // 'user' | 'assistant'
  TextColumn get content => text().withDefault(const Constant(''))();
  BoolColumn get isError => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}