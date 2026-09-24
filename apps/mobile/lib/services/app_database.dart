import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class CollectionSummaries extends Table {
  TextColumn get scope => text()();
  TextColumn get collection => text()();
  IntColumn get count => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {scope, collection};
}

class MediaCacheEntries extends Table {
  TextColumn get scope => text()();
  TextColumn get assetId => text()();
  TextColumn get localPath => text()();
  IntColumn get byteCount => integer()();
  DateTimeColumn get lastAccessedAt => dateTime()();
  BoolColumn get protected => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {scope, assetId};
}

class WardrobeRecords extends Table {
  TextColumn get scope => text()();
  TextColumn get id => text()();
  TextColumn get itemJson => text()();
  TextColumn get detailJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {scope, id};
}

@DriftDatabase(
  tables: [
    Preferences,
    CollectionSummaries,
    MediaCacheEntries,
    WardrobeRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.open() => AppDatabase(
    LazyDatabase(() async {
      final directory = await getApplicationSupportDirectory();
      return NativeDatabase.createInBackground(
        File(path.join(directory.path, 'form.sqlite')),
      );
    }),
  );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(wardrobeRecords);
    },
  );

  Future<String?> preference(String key) async => (await (select(
    preferences,
  )..where((row) => row.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setPreference(String key, String value) =>
      into(preferences).insertOnConflictUpdate(
        PreferencesCompanion.insert(key: key, value: value),
      );
}
