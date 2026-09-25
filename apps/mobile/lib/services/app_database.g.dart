// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PreferencesTable extends Preferences
    with TableInfo<$PreferencesTable, Preference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<Preference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Preference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Preference(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $PreferencesTable createAlias(String alias) {
    return $PreferencesTable(attachedDatabase, alias);
  }
}

class Preference extends DataClass implements Insertable<Preference> {
  final String key;
  final String value;
  const Preference({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  PreferencesCompanion toCompanion(bool nullToAbsent) {
    return PreferencesCompanion(key: Value(key), value: Value(value));
  }

  factory Preference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Preference(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Preference copyWith({String? key, String? value}) =>
      Preference(key: key ?? this.key, value: value ?? this.value);
  Preference copyWithCompanion(PreferencesCompanion data) {
    return Preference(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Preference(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Preference &&
          other.key == this.key &&
          other.value == this.value);
}

class PreferencesCompanion extends UpdateCompanion<Preference> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const PreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PreferencesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Preference> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PreferencesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return PreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionSummariesTable extends CollectionSummaries
    with TableInfo<$CollectionSummariesTable, CollectionSummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionSummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _collectionMeta = const VerificationMeta(
    'collection',
  );
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
    'collection',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [scope, collection, count, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collection_summaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionSummary> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('collection')) {
      context.handle(
        _collectionMeta,
        collection.isAcceptableOrUnknown(data['collection']!, _collectionMeta),
      );
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    } else if (isInserting) {
      context.missing(_countMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, collection};
  @override
  CollectionSummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionSummary(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      collection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CollectionSummariesTable createAlias(String alias) {
    return $CollectionSummariesTable(attachedDatabase, alias);
  }
}

class CollectionSummary extends DataClass
    implements Insertable<CollectionSummary> {
  final String scope;
  final String collection;
  final int count;
  final DateTime updatedAt;
  const CollectionSummary({
    required this.scope,
    required this.collection,
    required this.count,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['collection'] = Variable<String>(collection);
    map['count'] = Variable<int>(count);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CollectionSummariesCompanion toCompanion(bool nullToAbsent) {
    return CollectionSummariesCompanion(
      scope: Value(scope),
      collection: Value(collection),
      count: Value(count),
      updatedAt: Value(updatedAt),
    );
  }

  factory CollectionSummary.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionSummary(
      scope: serializer.fromJson<String>(json['scope']),
      collection: serializer.fromJson<String>(json['collection']),
      count: serializer.fromJson<int>(json['count']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'collection': serializer.toJson<String>(collection),
      'count': serializer.toJson<int>(count),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CollectionSummary copyWith({
    String? scope,
    String? collection,
    int? count,
    DateTime? updatedAt,
  }) => CollectionSummary(
    scope: scope ?? this.scope,
    collection: collection ?? this.collection,
    count: count ?? this.count,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CollectionSummary copyWithCompanion(CollectionSummariesCompanion data) {
    return CollectionSummary(
      scope: data.scope.present ? data.scope.value : this.scope,
      collection: data.collection.present
          ? data.collection.value
          : this.collection,
      count: data.count.present ? data.count.value : this.count,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionSummary(')
          ..write('scope: $scope, ')
          ..write('collection: $collection, ')
          ..write('count: $count, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scope, collection, count, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionSummary &&
          other.scope == this.scope &&
          other.collection == this.collection &&
          other.count == this.count &&
          other.updatedAt == this.updatedAt);
}

class CollectionSummariesCompanion extends UpdateCompanion<CollectionSummary> {
  final Value<String> scope;
  final Value<String> collection;
  final Value<int> count;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CollectionSummariesCompanion({
    this.scope = const Value.absent(),
    this.collection = const Value.absent(),
    this.count = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionSummariesCompanion.insert({
    required String scope,
    required String collection,
    required int count,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       collection = Value(collection),
       count = Value(count),
       updatedAt = Value(updatedAt);
  static Insertable<CollectionSummary> custom({
    Expression<String>? scope,
    Expression<String>? collection,
    Expression<int>? count,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (collection != null) 'collection': collection,
      if (count != null) 'count': count,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionSummariesCompanion copyWith({
    Value<String>? scope,
    Value<String>? collection,
    Value<int>? count,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CollectionSummariesCompanion(
      scope: scope ?? this.scope,
      collection: collection ?? this.collection,
      count: count ?? this.count,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionSummariesCompanion(')
          ..write('scope: $scope, ')
          ..write('collection: $collection, ')
          ..write('count: $count, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaCacheEntriesTable extends MediaCacheEntries
    with TableInfo<$MediaCacheEntriesTable, MediaCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteCountMeta = const VerificationMeta(
    'byteCount',
  );
  @override
  late final GeneratedColumn<int> byteCount = GeneratedColumn<int>(
    'byte_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAccessedAtMeta = const VerificationMeta(
    'lastAccessedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAccessedAt =
      GeneratedColumn<DateTime>(
        'last_accessed_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _protectedMeta = const VerificationMeta(
    'protected',
  );
  @override
  late final GeneratedColumn<bool> protected = GeneratedColumn<bool>(
    'protected',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("protected" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    scope,
    assetId,
    localPath,
    byteCount,
    lastAccessedAt,
    protected,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('byte_count')) {
      context.handle(
        _byteCountMeta,
        byteCount.isAcceptableOrUnknown(data['byte_count']!, _byteCountMeta),
      );
    } else if (isInserting) {
      context.missing(_byteCountMeta);
    }
    if (data.containsKey('last_accessed_at')) {
      context.handle(
        _lastAccessedAtMeta,
        lastAccessedAt.isAcceptableOrUnknown(
          data['last_accessed_at']!,
          _lastAccessedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessedAtMeta);
    }
    if (data.containsKey('protected')) {
      context.handle(
        _protectedMeta,
        protected.isAcceptableOrUnknown(data['protected']!, _protectedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, assetId};
  @override
  MediaCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaCacheEntry(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      byteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_count'],
      )!,
      lastAccessedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_accessed_at'],
      )!,
      protected: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}protected'],
      )!,
    );
  }

  @override
  $MediaCacheEntriesTable createAlias(String alias) {
    return $MediaCacheEntriesTable(attachedDatabase, alias);
  }
}

class MediaCacheEntry extends DataClass implements Insertable<MediaCacheEntry> {
  final String scope;
  final String assetId;
  final String localPath;
  final int byteCount;
  final DateTime lastAccessedAt;
  final bool protected;
  const MediaCacheEntry({
    required this.scope,
    required this.assetId,
    required this.localPath,
    required this.byteCount,
    required this.lastAccessedAt,
    required this.protected,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['asset_id'] = Variable<String>(assetId);
    map['local_path'] = Variable<String>(localPath);
    map['byte_count'] = Variable<int>(byteCount);
    map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt);
    map['protected'] = Variable<bool>(protected);
    return map;
  }

  MediaCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return MediaCacheEntriesCompanion(
      scope: Value(scope),
      assetId: Value(assetId),
      localPath: Value(localPath),
      byteCount: Value(byteCount),
      lastAccessedAt: Value(lastAccessedAt),
      protected: Value(protected),
    );
  }

  factory MediaCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaCacheEntry(
      scope: serializer.fromJson<String>(json['scope']),
      assetId: serializer.fromJson<String>(json['assetId']),
      localPath: serializer.fromJson<String>(json['localPath']),
      byteCount: serializer.fromJson<int>(json['byteCount']),
      lastAccessedAt: serializer.fromJson<DateTime>(json['lastAccessedAt']),
      protected: serializer.fromJson<bool>(json['protected']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'assetId': serializer.toJson<String>(assetId),
      'localPath': serializer.toJson<String>(localPath),
      'byteCount': serializer.toJson<int>(byteCount),
      'lastAccessedAt': serializer.toJson<DateTime>(lastAccessedAt),
      'protected': serializer.toJson<bool>(protected),
    };
  }

  MediaCacheEntry copyWith({
    String? scope,
    String? assetId,
    String? localPath,
    int? byteCount,
    DateTime? lastAccessedAt,
    bool? protected,
  }) => MediaCacheEntry(
    scope: scope ?? this.scope,
    assetId: assetId ?? this.assetId,
    localPath: localPath ?? this.localPath,
    byteCount: byteCount ?? this.byteCount,
    lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    protected: protected ?? this.protected,
  );
  MediaCacheEntry copyWithCompanion(MediaCacheEntriesCompanion data) {
    return MediaCacheEntry(
      scope: data.scope.present ? data.scope.value : this.scope,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      byteCount: data.byteCount.present ? data.byteCount.value : this.byteCount,
      lastAccessedAt: data.lastAccessedAt.present
          ? data.lastAccessedAt.value
          : this.lastAccessedAt,
      protected: data.protected.present ? data.protected.value : this.protected,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaCacheEntry(')
          ..write('scope: $scope, ')
          ..write('assetId: $assetId, ')
          ..write('localPath: $localPath, ')
          ..write('byteCount: $byteCount, ')
          ..write('lastAccessedAt: $lastAccessedAt, ')
          ..write('protected: $protected')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    scope,
    assetId,
    localPath,
    byteCount,
    lastAccessedAt,
    protected,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaCacheEntry &&
          other.scope == this.scope &&
          other.assetId == this.assetId &&
          other.localPath == this.localPath &&
          other.byteCount == this.byteCount &&
          other.lastAccessedAt == this.lastAccessedAt &&
          other.protected == this.protected);
}

class MediaCacheEntriesCompanion extends UpdateCompanion<MediaCacheEntry> {
  final Value<String> scope;
  final Value<String> assetId;
  final Value<String> localPath;
  final Value<int> byteCount;
  final Value<DateTime> lastAccessedAt;
  final Value<bool> protected;
  final Value<int> rowid;
  const MediaCacheEntriesCompanion({
    this.scope = const Value.absent(),
    this.assetId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.byteCount = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
    this.protected = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaCacheEntriesCompanion.insert({
    required String scope,
    required String assetId,
    required String localPath,
    required int byteCount,
    required DateTime lastAccessedAt,
    this.protected = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       assetId = Value(assetId),
       localPath = Value(localPath),
       byteCount = Value(byteCount),
       lastAccessedAt = Value(lastAccessedAt);
  static Insertable<MediaCacheEntry> custom({
    Expression<String>? scope,
    Expression<String>? assetId,
    Expression<String>? localPath,
    Expression<int>? byteCount,
    Expression<DateTime>? lastAccessedAt,
    Expression<bool>? protected,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (assetId != null) 'asset_id': assetId,
      if (localPath != null) 'local_path': localPath,
      if (byteCount != null) 'byte_count': byteCount,
      if (lastAccessedAt != null) 'last_accessed_at': lastAccessedAt,
      if (protected != null) 'protected': protected,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaCacheEntriesCompanion copyWith({
    Value<String>? scope,
    Value<String>? assetId,
    Value<String>? localPath,
    Value<int>? byteCount,
    Value<DateTime>? lastAccessedAt,
    Value<bool>? protected,
    Value<int>? rowid,
  }) {
    return MediaCacheEntriesCompanion(
      scope: scope ?? this.scope,
      assetId: assetId ?? this.assetId,
      localPath: localPath ?? this.localPath,
      byteCount: byteCount ?? this.byteCount,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      protected: protected ?? this.protected,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (byteCount.present) {
      map['byte_count'] = Variable<int>(byteCount.value);
    }
    if (lastAccessedAt.present) {
      map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt.value);
    }
    if (protected.present) {
      map['protected'] = Variable<bool>(protected.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaCacheEntriesCompanion(')
          ..write('scope: $scope, ')
          ..write('assetId: $assetId, ')
          ..write('localPath: $localPath, ')
          ..write('byteCount: $byteCount, ')
          ..write('lastAccessedAt: $lastAccessedAt, ')
          ..write('protected: $protected, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WardrobeRecordsTable extends WardrobeRecords
    with TableInfo<$WardrobeRecordsTable, WardrobeRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WardrobeRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemJsonMeta = const VerificationMeta(
    'itemJson',
  );
  @override
  late final GeneratedColumn<String> itemJson = GeneratedColumn<String>(
    'item_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailJsonMeta = const VerificationMeta(
    'detailJson',
  );
  @override
  late final GeneratedColumn<String> detailJson = GeneratedColumn<String>(
    'detail_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [scope, id, itemJson, detailJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wardrobe_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<WardrobeRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_json')) {
      context.handle(
        _itemJsonMeta,
        itemJson.isAcceptableOrUnknown(data['item_json']!, _itemJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_itemJsonMeta);
    }
    if (data.containsKey('detail_json')) {
      context.handle(
        _detailJsonMeta,
        detailJson.isAcceptableOrUnknown(data['detail_json']!, _detailJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, id};
  @override
  WardrobeRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WardrobeRecord(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      itemJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_json'],
      )!,
      detailJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail_json'],
      ),
    );
  }

  @override
  $WardrobeRecordsTable createAlias(String alias) {
    return $WardrobeRecordsTable(attachedDatabase, alias);
  }
}

class WardrobeRecord extends DataClass implements Insertable<WardrobeRecord> {
  final String scope;
  final String id;
  final String itemJson;
  final String? detailJson;
  const WardrobeRecord({
    required this.scope,
    required this.id,
    required this.itemJson,
    this.detailJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['id'] = Variable<String>(id);
    map['item_json'] = Variable<String>(itemJson);
    if (!nullToAbsent || detailJson != null) {
      map['detail_json'] = Variable<String>(detailJson);
    }
    return map;
  }

  WardrobeRecordsCompanion toCompanion(bool nullToAbsent) {
    return WardrobeRecordsCompanion(
      scope: Value(scope),
      id: Value(id),
      itemJson: Value(itemJson),
      detailJson: detailJson == null && nullToAbsent
          ? const Value.absent()
          : Value(detailJson),
    );
  }

  factory WardrobeRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WardrobeRecord(
      scope: serializer.fromJson<String>(json['scope']),
      id: serializer.fromJson<String>(json['id']),
      itemJson: serializer.fromJson<String>(json['itemJson']),
      detailJson: serializer.fromJson<String?>(json['detailJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'id': serializer.toJson<String>(id),
      'itemJson': serializer.toJson<String>(itemJson),
      'detailJson': serializer.toJson<String?>(detailJson),
    };
  }

  WardrobeRecord copyWith({
    String? scope,
    String? id,
    String? itemJson,
    Value<String?> detailJson = const Value.absent(),
  }) => WardrobeRecord(
    scope: scope ?? this.scope,
    id: id ?? this.id,
    itemJson: itemJson ?? this.itemJson,
    detailJson: detailJson.present ? detailJson.value : this.detailJson,
  );
  WardrobeRecord copyWithCompanion(WardrobeRecordsCompanion data) {
    return WardrobeRecord(
      scope: data.scope.present ? data.scope.value : this.scope,
      id: data.id.present ? data.id.value : this.id,
      itemJson: data.itemJson.present ? data.itemJson.value : this.itemJson,
      detailJson: data.detailJson.present
          ? data.detailJson.value
          : this.detailJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WardrobeRecord(')
          ..write('scope: $scope, ')
          ..write('id: $id, ')
          ..write('itemJson: $itemJson, ')
          ..write('detailJson: $detailJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scope, id, itemJson, detailJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WardrobeRecord &&
          other.scope == this.scope &&
          other.id == this.id &&
          other.itemJson == this.itemJson &&
          other.detailJson == this.detailJson);
}

class WardrobeRecordsCompanion extends UpdateCompanion<WardrobeRecord> {
  final Value<String> scope;
  final Value<String> id;
  final Value<String> itemJson;
  final Value<String?> detailJson;
  final Value<int> rowid;
  const WardrobeRecordsCompanion({
    this.scope = const Value.absent(),
    this.id = const Value.absent(),
    this.itemJson = const Value.absent(),
    this.detailJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WardrobeRecordsCompanion.insert({
    required String scope,
    required String id,
    required String itemJson,
    this.detailJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       id = Value(id),
       itemJson = Value(itemJson);
  static Insertable<WardrobeRecord> custom({
    Expression<String>? scope,
    Expression<String>? id,
    Expression<String>? itemJson,
    Expression<String>? detailJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (id != null) 'id': id,
      if (itemJson != null) 'item_json': itemJson,
      if (detailJson != null) 'detail_json': detailJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WardrobeRecordsCompanion copyWith({
    Value<String>? scope,
    Value<String>? id,
    Value<String>? itemJson,
    Value<String?>? detailJson,
    Value<int>? rowid,
  }) {
    return WardrobeRecordsCompanion(
      scope: scope ?? this.scope,
      id: id ?? this.id,
      itemJson: itemJson ?? this.itemJson,
      detailJson: detailJson ?? this.detailJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemJson.present) {
      map['item_json'] = Variable<String>(itemJson.value);
    }
    if (detailJson.present) {
      map['detail_json'] = Variable<String>(detailJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WardrobeRecordsCompanion(')
          ..write('scope: $scope, ')
          ..write('id: $id, ')
          ..write('itemJson: $itemJson, ')
          ..write('detailJson: $detailJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IntakeRecordsTable extends IntakeRecords
    with TableInfo<$IntakeRecordsTable, IntakeRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IntakeRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _draftJsonMeta = const VerificationMeta(
    'draftJson',
  );
  @override
  late final GeneratedColumn<String> draftJson = GeneratedColumn<String>(
    'draft_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [scope, id, draftJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'intake_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<IntakeRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('draft_json')) {
      context.handle(
        _draftJsonMeta,
        draftJson.isAcceptableOrUnknown(data['draft_json']!, _draftJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_draftJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, id};
  @override
  IntakeRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IntakeRecord(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      draftJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_json'],
      )!,
    );
  }

  @override
  $IntakeRecordsTable createAlias(String alias) {
    return $IntakeRecordsTable(attachedDatabase, alias);
  }
}

class IntakeRecord extends DataClass implements Insertable<IntakeRecord> {
  final String scope;
  final String id;
  final String draftJson;
  const IntakeRecord({
    required this.scope,
    required this.id,
    required this.draftJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['id'] = Variable<String>(id);
    map['draft_json'] = Variable<String>(draftJson);
    return map;
  }

  IntakeRecordsCompanion toCompanion(bool nullToAbsent) {
    return IntakeRecordsCompanion(
      scope: Value(scope),
      id: Value(id),
      draftJson: Value(draftJson),
    );
  }

  factory IntakeRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IntakeRecord(
      scope: serializer.fromJson<String>(json['scope']),
      id: serializer.fromJson<String>(json['id']),
      draftJson: serializer.fromJson<String>(json['draftJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'id': serializer.toJson<String>(id),
      'draftJson': serializer.toJson<String>(draftJson),
    };
  }

  IntakeRecord copyWith({String? scope, String? id, String? draftJson}) =>
      IntakeRecord(
        scope: scope ?? this.scope,
        id: id ?? this.id,
        draftJson: draftJson ?? this.draftJson,
      );
  IntakeRecord copyWithCompanion(IntakeRecordsCompanion data) {
    return IntakeRecord(
      scope: data.scope.present ? data.scope.value : this.scope,
      id: data.id.present ? data.id.value : this.id,
      draftJson: data.draftJson.present ? data.draftJson.value : this.draftJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IntakeRecord(')
          ..write('scope: $scope, ')
          ..write('id: $id, ')
          ..write('draftJson: $draftJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scope, id, draftJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IntakeRecord &&
          other.scope == this.scope &&
          other.id == this.id &&
          other.draftJson == this.draftJson);
}

class IntakeRecordsCompanion extends UpdateCompanion<IntakeRecord> {
  final Value<String> scope;
  final Value<String> id;
  final Value<String> draftJson;
  final Value<int> rowid;
  const IntakeRecordsCompanion({
    this.scope = const Value.absent(),
    this.id = const Value.absent(),
    this.draftJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IntakeRecordsCompanion.insert({
    required String scope,
    required String id,
    required String draftJson,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       id = Value(id),
       draftJson = Value(draftJson);
  static Insertable<IntakeRecord> custom({
    Expression<String>? scope,
    Expression<String>? id,
    Expression<String>? draftJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (id != null) 'id': id,
      if (draftJson != null) 'draft_json': draftJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IntakeRecordsCompanion copyWith({
    Value<String>? scope,
    Value<String>? id,
    Value<String>? draftJson,
    Value<int>? rowid,
  }) {
    return IntakeRecordsCompanion(
      scope: scope ?? this.scope,
      id: id ?? this.id,
      draftJson: draftJson ?? this.draftJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (draftJson.present) {
      map['draft_json'] = Variable<String>(draftJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IntakeRecordsCompanion(')
          ..write('scope: $scope, ')
          ..write('id: $id, ')
          ..write('draftJson: $draftJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LookRecordsTable extends LookRecords
    with TableInfo<$LookRecordsTable, LookRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LookRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lookJsonMeta = const VerificationMeta(
    'lookJson',
  );
  @override
  late final GeneratedColumn<String> lookJson = GeneratedColumn<String>(
    'look_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [scope, id, lookJson, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'look_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<LookRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('look_json')) {
      context.handle(
        _lookJsonMeta,
        lookJson.isAcceptableOrUnknown(data['look_json']!, _lookJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_lookJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, id};
  @override
  LookRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LookRecord(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      lookJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}look_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LookRecordsTable createAlias(String alias) {
    return $LookRecordsTable(attachedDatabase, alias);
  }
}

class LookRecord extends DataClass implements Insertable<LookRecord> {
  final String scope;
  final String id;
  final String lookJson;
  final DateTime createdAt;
  const LookRecord({
    required this.scope,
    required this.id,
    required this.lookJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['id'] = Variable<String>(id);
    map['look_json'] = Variable<String>(lookJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LookRecordsCompanion toCompanion(bool nullToAbsent) {
    return LookRecordsCompanion(
      scope: Value(scope),
      id: Value(id),
      lookJson: Value(lookJson),
      createdAt: Value(createdAt),
    );
  }

  factory LookRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LookRecord(
      scope: serializer.fromJson<String>(json['scope']),
      id: serializer.fromJson<String>(json['id']),
      lookJson: serializer.fromJson<String>(json['lookJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'id': serializer.toJson<String>(id),
      'lookJson': serializer.toJson<String>(lookJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LookRecord copyWith({
    String? scope,
    String? id,
    String? lookJson,
    DateTime? createdAt,
  }) => LookRecord(
    scope: scope ?? this.scope,
    id: id ?? this.id,
    lookJson: lookJson ?? this.lookJson,
    createdAt: createdAt ?? this.createdAt,
  );
  LookRecord copyWithCompanion(LookRecordsCompanion data) {
    return LookRecord(
      scope: data.scope.present ? data.scope.value : this.scope,
      id: data.id.present ? data.id.value : this.id,
      lookJson: data.lookJson.present ? data.lookJson.value : this.lookJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LookRecord(')
          ..write('scope: $scope, ')
          ..write('id: $id, ')
          ..write('lookJson: $lookJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scope, id, lookJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LookRecord &&
          other.scope == this.scope &&
          other.id == this.id &&
          other.lookJson == this.lookJson &&
          other.createdAt == this.createdAt);
}

class LookRecordsCompanion extends UpdateCompanion<LookRecord> {
  final Value<String> scope;
  final Value<String> id;
  final Value<String> lookJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LookRecordsCompanion({
    this.scope = const Value.absent(),
    this.id = const Value.absent(),
    this.lookJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LookRecordsCompanion.insert({
    required String scope,
    required String id,
    required String lookJson,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       id = Value(id),
       lookJson = Value(lookJson),
       createdAt = Value(createdAt);
  static Insertable<LookRecord> custom({
    Expression<String>? scope,
    Expression<String>? id,
    Expression<String>? lookJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (id != null) 'id': id,
      if (lookJson != null) 'look_json': lookJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LookRecordsCompanion copyWith({
    Value<String>? scope,
    Value<String>? id,
    Value<String>? lookJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return LookRecordsCompanion(
      scope: scope ?? this.scope,
      id: id ?? this.id,
      lookJson: lookJson ?? this.lookJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (lookJson.present) {
      map['look_json'] = Variable<String>(lookJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LookRecordsCompanion(')
          ..write('scope: $scope, ')
          ..write('id: $id, ')
          ..write('lookJson: $lookJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CharacterRecordsTable extends CharacterRecords
    with TableInfo<$CharacterRecordsTable, CharacterRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharacterRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sheetJsonMeta = const VerificationMeta(
    'sheetJson',
  );
  @override
  late final GeneratedColumn<String> sheetJson = GeneratedColumn<String>(
    'sheet_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [scope, id, sheetJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'character_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<CharacterRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sheet_json')) {
      context.handle(
        _sheetJsonMeta,
        sheetJson.isAcceptableOrUnknown(data['sheet_json']!, _sheetJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_sheetJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, id};
  @override
  CharacterRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CharacterRecord(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sheetJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sheet_json'],
      )!,
    );
  }

  @override
  $CharacterRecordsTable createAlias(String alias) {
    return $CharacterRecordsTable(attachedDatabase, alias);
  }
}

class CharacterRecord extends DataClass implements Insertable<CharacterRecord> {
  final String scope;
  final String id;
  final String sheetJson;
  const CharacterRecord({
    required this.scope,
    required this.id,
    required this.sheetJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['id'] = Variable<String>(id);
    map['sheet_json'] = Variable<String>(sheetJson);
    return map;
  }

  CharacterRecordsCompanion toCompanion(bool nullToAbsent) {
    return CharacterRecordsCompanion(
      scope: Value(scope),
      id: Value(id),
      sheetJson: Value(sheetJson),
    );
  }

  factory CharacterRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CharacterRecord(
      scope: serializer.fromJson<String>(json['scope']),
      id: serializer.fromJson<String>(json['id']),
      sheetJson: serializer.fromJson<String>(json['sheetJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'id': serializer.toJson<String>(id),
      'sheetJson': serializer.toJson<String>(sheetJson),
    };
  }

  CharacterRecord copyWith({String? scope, String? id, String? sheetJson}) =>
      CharacterRecord(
        scope: scope ?? this.scope,
        id: id ?? this.id,
        sheetJson: sheetJson ?? this.sheetJson,
      );
  CharacterRecord copyWithCompanion(CharacterRecordsCompanion data) {
    return CharacterRecord(
      scope: data.scope.present ? data.scope.value : this.scope,
      id: data.id.present ? data.id.value : this.id,
      sheetJson: data.sheetJson.present ? data.sheetJson.value : this.sheetJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CharacterRecord(')
          ..write('scope: $scope, ')
          ..write('id: $id, ')
          ..write('sheetJson: $sheetJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scope, id, sheetJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CharacterRecord &&
          other.scope == this.scope &&
          other.id == this.id &&
          other.sheetJson == this.sheetJson);
}

class CharacterRecordsCompanion extends UpdateCompanion<CharacterRecord> {
  final Value<String> scope;
  final Value<String> id;
  final Value<String> sheetJson;
  final Value<int> rowid;
  const CharacterRecordsCompanion({
    this.scope = const Value.absent(),
    this.id = const Value.absent(),
    this.sheetJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CharacterRecordsCompanion.insert({
    required String scope,
    required String id,
    required String sheetJson,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       id = Value(id),
       sheetJson = Value(sheetJson);
  static Insertable<CharacterRecord> custom({
    Expression<String>? scope,
    Expression<String>? id,
    Expression<String>? sheetJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (id != null) 'id': id,
      if (sheetJson != null) 'sheet_json': sheetJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CharacterRecordsCompanion copyWith({
    Value<String>? scope,
    Value<String>? id,
    Value<String>? sheetJson,
    Value<int>? rowid,
  }) {
    return CharacterRecordsCompanion(
      scope: scope ?? this.scope,
      id: id ?? this.id,
      sheetJson: sheetJson ?? this.sheetJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sheetJson.present) {
      map['sheet_json'] = Variable<String>(sheetJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CharacterRecordsCompanion(')
          ..write('scope: $scope, ')
          ..write('id: $id, ')
          ..write('sheetJson: $sheetJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PreferencesTable preferences = $PreferencesTable(this);
  late final $CollectionSummariesTable collectionSummaries =
      $CollectionSummariesTable(this);
  late final $MediaCacheEntriesTable mediaCacheEntries =
      $MediaCacheEntriesTable(this);
  late final $WardrobeRecordsTable wardrobeRecords = $WardrobeRecordsTable(
    this,
  );
  late final $IntakeRecordsTable intakeRecords = $IntakeRecordsTable(this);
  late final $LookRecordsTable lookRecords = $LookRecordsTable(this);
  late final $CharacterRecordsTable characterRecords = $CharacterRecordsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    preferences,
    collectionSummaries,
    mediaCacheEntries,
    wardrobeRecords,
    intakeRecords,
    lookRecords,
    characterRecords,
  ];
}

typedef $$PreferencesTableCreateCompanionBuilder =
    PreferencesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$PreferencesTableUpdateCompanionBuilder =
    PreferencesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$PreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$PreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PreferencesTable,
          Preference,
          $$PreferencesTableFilterComposer,
          $$PreferencesTableOrderingComposer,
          $$PreferencesTableAnnotationComposer,
          $$PreferencesTableCreateCompanionBuilder,
          $$PreferencesTableUpdateCompanionBuilder,
          (
            Preference,
            BaseReferences<_$AppDatabase, $PreferencesTable, Preference>,
          ),
          Preference,
          PrefetchHooks Function()
        > {
  $$PreferencesTableTableManager(_$AppDatabase db, $PreferencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PreferencesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => PreferencesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PreferencesTable, Preference>(table),
                  BaseReferences<_$AppDatabase, $PreferencesTable, Preference>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PreferencesTable,
      Preference,
      $$PreferencesTableFilterComposer,
      $$PreferencesTableOrderingComposer,
      $$PreferencesTableAnnotationComposer,
      $$PreferencesTableCreateCompanionBuilder,
      $$PreferencesTableUpdateCompanionBuilder,
      (
        Preference,
        BaseReferences<_$AppDatabase, $PreferencesTable, Preference>,
      ),
      Preference,
      PrefetchHooks Function()
    >;
typedef $$CollectionSummariesTableCreateCompanionBuilder =
    CollectionSummariesCompanion Function({
      required String scope,
      required String collection,
      required int count,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CollectionSummariesTableUpdateCompanionBuilder =
    CollectionSummariesCompanion Function({
      Value<String> scope,
      Value<String> collection,
      Value<int> count,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CollectionSummariesTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionSummariesTable> {
  $$CollectionSummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CollectionSummariesTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionSummariesTable> {
  $$CollectionSummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionSummariesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionSummariesTable> {
  $$CollectionSummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => column,
  );

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CollectionSummariesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionSummariesTable,
          CollectionSummary,
          $$CollectionSummariesTableFilterComposer,
          $$CollectionSummariesTableOrderingComposer,
          $$CollectionSummariesTableAnnotationComposer,
          $$CollectionSummariesTableCreateCompanionBuilder,
          $$CollectionSummariesTableUpdateCompanionBuilder,
          (
            CollectionSummary,
            BaseReferences<
              _$AppDatabase,
              $CollectionSummariesTable,
              CollectionSummary
            >,
          ),
          CollectionSummary,
          PrefetchHooks Function()
        > {
  $$CollectionSummariesTableTableManager(
    _$AppDatabase db,
    $CollectionSummariesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionSummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionSummariesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CollectionSummariesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> collection = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionSummariesCompanion(
                scope: scope,
                collection: collection,
                count: count,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required String collection,
                required int count,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CollectionSummariesCompanion.insert(
                scope: scope,
                collection: collection,
                count: count,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CollectionSummariesTable, CollectionSummary>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $CollectionSummariesTable,
                    CollectionSummary
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CollectionSummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionSummariesTable,
      CollectionSummary,
      $$CollectionSummariesTableFilterComposer,
      $$CollectionSummariesTableOrderingComposer,
      $$CollectionSummariesTableAnnotationComposer,
      $$CollectionSummariesTableCreateCompanionBuilder,
      $$CollectionSummariesTableUpdateCompanionBuilder,
      (
        CollectionSummary,
        BaseReferences<
          _$AppDatabase,
          $CollectionSummariesTable,
          CollectionSummary
        >,
      ),
      CollectionSummary,
      PrefetchHooks Function()
    >;
typedef $$MediaCacheEntriesTableCreateCompanionBuilder =
    MediaCacheEntriesCompanion Function({
      required String scope,
      required String assetId,
      required String localPath,
      required int byteCount,
      required DateTime lastAccessedAt,
      Value<bool> protected,
      Value<int> rowid,
    });
typedef $$MediaCacheEntriesTableUpdateCompanionBuilder =
    MediaCacheEntriesCompanion Function({
      Value<String> scope,
      Value<String> assetId,
      Value<String> localPath,
      Value<int> byteCount,
      Value<DateTime> lastAccessedAt,
      Value<bool> protected,
      Value<int> rowid,
    });

class $$MediaCacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $MediaCacheEntriesTable> {
  $$MediaCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get protected => $composableBuilder(
    column: $table.protected,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaCacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaCacheEntriesTable> {
  $$MediaCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get protected => $composableBuilder(
    column: $table.protected,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaCacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaCacheEntriesTable> {
  $$MediaCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get byteCount =>
      $composableBuilder(column: $table.byteCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get protected =>
      $composableBuilder(column: $table.protected, builder: (column) => column);
}

class $$MediaCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaCacheEntriesTable,
          MediaCacheEntry,
          $$MediaCacheEntriesTableFilterComposer,
          $$MediaCacheEntriesTableOrderingComposer,
          $$MediaCacheEntriesTableAnnotationComposer,
          $$MediaCacheEntriesTableCreateCompanionBuilder,
          $$MediaCacheEntriesTableUpdateCompanionBuilder,
          (
            MediaCacheEntry,
            BaseReferences<
              _$AppDatabase,
              $MediaCacheEntriesTable,
              MediaCacheEntry
            >,
          ),
          MediaCacheEntry,
          PrefetchHooks Function()
        > {
  $$MediaCacheEntriesTableTableManager(
    _$AppDatabase db,
    $MediaCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaCacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaCacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<int> byteCount = const Value.absent(),
                Value<DateTime> lastAccessedAt = const Value.absent(),
                Value<bool> protected = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaCacheEntriesCompanion(
                scope: scope,
                assetId: assetId,
                localPath: localPath,
                byteCount: byteCount,
                lastAccessedAt: lastAccessedAt,
                protected: protected,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required String assetId,
                required String localPath,
                required int byteCount,
                required DateTime lastAccessedAt,
                Value<bool> protected = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaCacheEntriesCompanion.insert(
                scope: scope,
                assetId: assetId,
                localPath: localPath,
                byteCount: byteCount,
                lastAccessedAt: lastAccessedAt,
                protected: protected,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaCacheEntriesTable, MediaCacheEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $MediaCacheEntriesTable,
                    MediaCacheEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaCacheEntriesTable,
      MediaCacheEntry,
      $$MediaCacheEntriesTableFilterComposer,
      $$MediaCacheEntriesTableOrderingComposer,
      $$MediaCacheEntriesTableAnnotationComposer,
      $$MediaCacheEntriesTableCreateCompanionBuilder,
      $$MediaCacheEntriesTableUpdateCompanionBuilder,
      (
        MediaCacheEntry,
        BaseReferences<_$AppDatabase, $MediaCacheEntriesTable, MediaCacheEntry>,
      ),
      MediaCacheEntry,
      PrefetchHooks Function()
    >;
typedef $$WardrobeRecordsTableCreateCompanionBuilder =
    WardrobeRecordsCompanion Function({
      required String scope,
      required String id,
      required String itemJson,
      Value<String?> detailJson,
      Value<int> rowid,
    });
typedef $$WardrobeRecordsTableUpdateCompanionBuilder =
    WardrobeRecordsCompanion Function({
      Value<String> scope,
      Value<String> id,
      Value<String> itemJson,
      Value<String?> detailJson,
      Value<int> rowid,
    });

class $$WardrobeRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $WardrobeRecordsTable> {
  $$WardrobeRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemJson => $composableBuilder(
    column: $table.itemJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailJson => $composableBuilder(
    column: $table.detailJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WardrobeRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $WardrobeRecordsTable> {
  $$WardrobeRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemJson => $composableBuilder(
    column: $table.itemJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailJson => $composableBuilder(
    column: $table.detailJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WardrobeRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WardrobeRecordsTable> {
  $$WardrobeRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get itemJson =>
      $composableBuilder(column: $table.itemJson, builder: (column) => column);

  GeneratedColumn<String> get detailJson => $composableBuilder(
    column: $table.detailJson,
    builder: (column) => column,
  );
}

class $$WardrobeRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WardrobeRecordsTable,
          WardrobeRecord,
          $$WardrobeRecordsTableFilterComposer,
          $$WardrobeRecordsTableOrderingComposer,
          $$WardrobeRecordsTableAnnotationComposer,
          $$WardrobeRecordsTableCreateCompanionBuilder,
          $$WardrobeRecordsTableUpdateCompanionBuilder,
          (
            WardrobeRecord,
            BaseReferences<
              _$AppDatabase,
              $WardrobeRecordsTable,
              WardrobeRecord
            >,
          ),
          WardrobeRecord,
          PrefetchHooks Function()
        > {
  $$WardrobeRecordsTableTableManager(
    _$AppDatabase db,
    $WardrobeRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WardrobeRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WardrobeRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WardrobeRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> itemJson = const Value.absent(),
                Value<String?> detailJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WardrobeRecordsCompanion(
                scope: scope,
                id: id,
                itemJson: itemJson,
                detailJson: detailJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required String id,
                required String itemJson,
                Value<String?> detailJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WardrobeRecordsCompanion.insert(
                scope: scope,
                id: id,
                itemJson: itemJson,
                detailJson: detailJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WardrobeRecordsTable, WardrobeRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $WardrobeRecordsTable,
                    WardrobeRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WardrobeRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WardrobeRecordsTable,
      WardrobeRecord,
      $$WardrobeRecordsTableFilterComposer,
      $$WardrobeRecordsTableOrderingComposer,
      $$WardrobeRecordsTableAnnotationComposer,
      $$WardrobeRecordsTableCreateCompanionBuilder,
      $$WardrobeRecordsTableUpdateCompanionBuilder,
      (
        WardrobeRecord,
        BaseReferences<_$AppDatabase, $WardrobeRecordsTable, WardrobeRecord>,
      ),
      WardrobeRecord,
      PrefetchHooks Function()
    >;
typedef $$IntakeRecordsTableCreateCompanionBuilder =
    IntakeRecordsCompanion Function({
      required String scope,
      required String id,
      required String draftJson,
      Value<int> rowid,
    });
typedef $$IntakeRecordsTableUpdateCompanionBuilder =
    IntakeRecordsCompanion Function({
      Value<String> scope,
      Value<String> id,
      Value<String> draftJson,
      Value<int> rowid,
    });

class $$IntakeRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $IntakeRecordsTable> {
  $$IntakeRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get draftJson => $composableBuilder(
    column: $table.draftJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IntakeRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $IntakeRecordsTable> {
  $$IntakeRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get draftJson => $composableBuilder(
    column: $table.draftJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IntakeRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $IntakeRecordsTable> {
  $$IntakeRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get draftJson =>
      $composableBuilder(column: $table.draftJson, builder: (column) => column);
}

class $$IntakeRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IntakeRecordsTable,
          IntakeRecord,
          $$IntakeRecordsTableFilterComposer,
          $$IntakeRecordsTableOrderingComposer,
          $$IntakeRecordsTableAnnotationComposer,
          $$IntakeRecordsTableCreateCompanionBuilder,
          $$IntakeRecordsTableUpdateCompanionBuilder,
          (
            IntakeRecord,
            BaseReferences<_$AppDatabase, $IntakeRecordsTable, IntakeRecord>,
          ),
          IntakeRecord,
          PrefetchHooks Function()
        > {
  $$IntakeRecordsTableTableManager(_$AppDatabase db, $IntakeRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IntakeRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IntakeRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IntakeRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> draftJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IntakeRecordsCompanion(
                scope: scope,
                id: id,
                draftJson: draftJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required String id,
                required String draftJson,
                Value<int> rowid = const Value.absent(),
              }) => IntakeRecordsCompanion.insert(
                scope: scope,
                id: id,
                draftJson: draftJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IntakeRecordsTable, IntakeRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $IntakeRecordsTable,
                    IntakeRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IntakeRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IntakeRecordsTable,
      IntakeRecord,
      $$IntakeRecordsTableFilterComposer,
      $$IntakeRecordsTableOrderingComposer,
      $$IntakeRecordsTableAnnotationComposer,
      $$IntakeRecordsTableCreateCompanionBuilder,
      $$IntakeRecordsTableUpdateCompanionBuilder,
      (
        IntakeRecord,
        BaseReferences<_$AppDatabase, $IntakeRecordsTable, IntakeRecord>,
      ),
      IntakeRecord,
      PrefetchHooks Function()
    >;
typedef $$LookRecordsTableCreateCompanionBuilder =
    LookRecordsCompanion Function({
      required String scope,
      required String id,
      required String lookJson,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$LookRecordsTableUpdateCompanionBuilder =
    LookRecordsCompanion Function({
      Value<String> scope,
      Value<String> id,
      Value<String> lookJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$LookRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $LookRecordsTable> {
  $$LookRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lookJson => $composableBuilder(
    column: $table.lookJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LookRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $LookRecordsTable> {
  $$LookRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lookJson => $composableBuilder(
    column: $table.lookJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LookRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LookRecordsTable> {
  $$LookRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get lookJson =>
      $composableBuilder(column: $table.lookJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LookRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LookRecordsTable,
          LookRecord,
          $$LookRecordsTableFilterComposer,
          $$LookRecordsTableOrderingComposer,
          $$LookRecordsTableAnnotationComposer,
          $$LookRecordsTableCreateCompanionBuilder,
          $$LookRecordsTableUpdateCompanionBuilder,
          (
            LookRecord,
            BaseReferences<_$AppDatabase, $LookRecordsTable, LookRecord>,
          ),
          LookRecord,
          PrefetchHooks Function()
        > {
  $$LookRecordsTableTableManager(_$AppDatabase db, $LookRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LookRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LookRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LookRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> lookJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LookRecordsCompanion(
                scope: scope,
                id: id,
                lookJson: lookJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required String id,
                required String lookJson,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => LookRecordsCompanion.insert(
                scope: scope,
                id: id,
                lookJson: lookJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LookRecordsTable, LookRecord>(table),
                  BaseReferences<_$AppDatabase, $LookRecordsTable, LookRecord>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LookRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LookRecordsTable,
      LookRecord,
      $$LookRecordsTableFilterComposer,
      $$LookRecordsTableOrderingComposer,
      $$LookRecordsTableAnnotationComposer,
      $$LookRecordsTableCreateCompanionBuilder,
      $$LookRecordsTableUpdateCompanionBuilder,
      (
        LookRecord,
        BaseReferences<_$AppDatabase, $LookRecordsTable, LookRecord>,
      ),
      LookRecord,
      PrefetchHooks Function()
    >;
typedef $$CharacterRecordsTableCreateCompanionBuilder =
    CharacterRecordsCompanion Function({
      required String scope,
      required String id,
      required String sheetJson,
      Value<int> rowid,
    });
typedef $$CharacterRecordsTableUpdateCompanionBuilder =
    CharacterRecordsCompanion Function({
      Value<String> scope,
      Value<String> id,
      Value<String> sheetJson,
      Value<int> rowid,
    });

class $$CharacterRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $CharacterRecordsTable> {
  $$CharacterRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sheetJson => $composableBuilder(
    column: $table.sheetJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CharacterRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $CharacterRecordsTable> {
  $$CharacterRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sheetJson => $composableBuilder(
    column: $table.sheetJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CharacterRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CharacterRecordsTable> {
  $$CharacterRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sheetJson =>
      $composableBuilder(column: $table.sheetJson, builder: (column) => column);
}

class $$CharacterRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CharacterRecordsTable,
          CharacterRecord,
          $$CharacterRecordsTableFilterComposer,
          $$CharacterRecordsTableOrderingComposer,
          $$CharacterRecordsTableAnnotationComposer,
          $$CharacterRecordsTableCreateCompanionBuilder,
          $$CharacterRecordsTableUpdateCompanionBuilder,
          (
            CharacterRecord,
            BaseReferences<
              _$AppDatabase,
              $CharacterRecordsTable,
              CharacterRecord
            >,
          ),
          CharacterRecord,
          PrefetchHooks Function()
        > {
  $$CharacterRecordsTableTableManager(
    _$AppDatabase db,
    $CharacterRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharacterRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharacterRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CharacterRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> sheetJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CharacterRecordsCompanion(
                scope: scope,
                id: id,
                sheetJson: sheetJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required String id,
                required String sheetJson,
                Value<int> rowid = const Value.absent(),
              }) => CharacterRecordsCompanion.insert(
                scope: scope,
                id: id,
                sheetJson: sheetJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CharacterRecordsTable, CharacterRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CharacterRecordsTable,
                    CharacterRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CharacterRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CharacterRecordsTable,
      CharacterRecord,
      $$CharacterRecordsTableFilterComposer,
      $$CharacterRecordsTableOrderingComposer,
      $$CharacterRecordsTableAnnotationComposer,
      $$CharacterRecordsTableCreateCompanionBuilder,
      $$CharacterRecordsTableUpdateCompanionBuilder,
      (
        CharacterRecord,
        BaseReferences<_$AppDatabase, $CharacterRecordsTable, CharacterRecord>,
      ),
      CharacterRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PreferencesTableTableManager get preferences =>
      $$PreferencesTableTableManager(_db, _db.preferences);
  $$CollectionSummariesTableTableManager get collectionSummaries =>
      $$CollectionSummariesTableTableManager(_db, _db.collectionSummaries);
  $$MediaCacheEntriesTableTableManager get mediaCacheEntries =>
      $$MediaCacheEntriesTableTableManager(_db, _db.mediaCacheEntries);
  $$WardrobeRecordsTableTableManager get wardrobeRecords =>
      $$WardrobeRecordsTableTableManager(_db, _db.wardrobeRecords);
  $$IntakeRecordsTableTableManager get intakeRecords =>
      $$IntakeRecordsTableTableManager(_db, _db.intakeRecords);
  $$LookRecordsTableTableManager get lookRecords =>
      $$LookRecordsTableTableManager(_db, _db.lookRecords);
  $$CharacterRecordsTableTableManager get characterRecords =>
      $$CharacterRecordsTableTableManager(_db, _db.characterRecords);
}
