import 'package:drift/drift.dart';

class DueContacts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  TextColumn get color => text()();
  TextColumn get type => text().withDefault(const Constant('vendor'))(); // 'vendor' or 'person'
  RealColumn get defaultAmount => real().nullable()();
  TextColumn get defaultNote => text().nullable()();
  TextColumn get defaultCategoryId => text().nullable()();
  // Device-contact enrichment (schema v10). All nullable so existing rows
  // survive the migration without a default. Read-only from the address book:
  // phone is stored normalized (last-10-digit key), photoPath is an app-local
  // cached file, deviceContactId supports future re-sync. Never uploaded.
  TextColumn get phone => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get deviceContactId => text().nullable()();
  // Schema v11: every phone number from a device contact as a JSON array of
  // {number, label} (see ContactPhone in phone_utils.dart). `phone` above stays
  // as the denormalized primary for display/dedup; `phones` holds the full set
  // so the user can pick which to call/WhatsApp at action time.
  TextColumn get phones => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
