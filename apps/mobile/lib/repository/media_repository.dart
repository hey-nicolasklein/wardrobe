import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:path/path.dart' as path;

class MediaRepository {
  MediaRepository(
    this.database,
    this.api,
    this.scope,
    this.directory, {
    this.maxBytes = 200 * 1024 * 1024,
  });

  final AppDatabase database;
  final FormApi? api;
  final String scope;
  final Directory directory;
  final int maxBytes;
  final Map<String, Future<File?>> _pending = {};
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<File?> load(
    String identity, {
    String? previewPath,
    bool online = true,
  }) async {
    final cached = await _cachedFile(identity);
    if (cached != null || !online || api == null) return cached;
    return _pending.putIfAbsent(
      identity,
      () =>
          _serial(() async {
            final entry =
                await (database.select(database.mediaCacheEntries)..where(
                      (r) => r.scope.equals(scope) & r.assetId.equals(identity),
                    ))
                    .getSingleOrNull();
            try {
              final url =
                  previewPath ??
                  (await api!.request(
                        'v1/assets/$identity/download',
                      ))['downloadUrl']
                      as String;
              final bytes = await api!.bytes(url);
              if (bytes.length > maxBytes && !(entry?.protected ?? false)) {
                return null;
              }
              await directory.create(recursive: true);
              final file = File(
                path.join(
                  directory.path,
                  '${DateTime.now().microsecondsSinceEpoch}-'
                  '${identity.hashCode}.media',
                ),
              );
              await file.writeAsBytes(bytes, flush: true);
              await database
                  .into(database.mediaCacheEntries)
                  .insertOnConflictUpdate(
                    MediaCacheEntriesCompanion.insert(
                      scope: scope,
                      assetId: identity,
                      localPath: file.path,
                      byteCount: bytes.length,
                      lastAccessedAt: DateTime.now(),
                      protected: Value(entry?.protected ?? false),
                    ),
                  );
              await _evict(except: identity);
              return file;
            } on Exception {
              return null;
            }
          }).whenComplete(() {
            unawaited(_pending.remove(identity));
          }),
    );
  }

  Future<File?> _cachedFile(String identity) async {
    final entry =
        await (database.select(
              database.mediaCacheEntries,
            )..where((r) => r.scope.equals(scope) & r.assetId.equals(identity)))
            .getSingleOrNull();
    if (entry == null || !File(entry.localPath).existsSync()) return null;
    await (database.update(
      database.mediaCacheEntries,
    )..where((r) => r.scope.equals(scope) & r.assetId.equals(identity))).write(
      MediaCacheEntriesCompanion(lastAccessedAt: Value(DateTime.now())),
    );
    return File(entry.localPath);
  }

  Future<void> _remove(MediaCacheEntry entry) async {
    final file = File(entry.localPath);
    if (file.existsSync()) await file.delete();
    await (database.delete(database.mediaCacheEntries)..where(
          (r) => r.scope.equals(entry.scope) & r.assetId.equals(entry.assetId),
        ))
        .go();
  }

  Future<void> _evict({String? except}) async {
    final entries = await (database.select(
      database.mediaCacheEntries,
    )..orderBy([(r) => OrderingTerm.asc(r.lastAccessedAt)])).get();
    var total = entries.fold(0, (n, e) => n + e.byteCount);
    for (final entry in entries) {
      if (total <= maxBytes) break;
      if (entry.protected ||
          (entry.scope == scope && entry.assetId == except)) {
        continue;
      }
      await _remove(entry);
      total -= entry.byteCount;
    }
  }

  Future<void> protect(String identity, {required bool protected}) => _serial(
    () async {
      await (database.update(database.mediaCacheEntries)
            ..where((r) => r.scope.equals(scope) & r.assetId.equals(identity)))
          .write(MediaCacheEntriesCompanion(protected: Value(protected)));
    },
  );

  Future<void> settle() => _queue;

  Future<void> clearDownloaded() => _serial(() async {
    final entries = await (database.select(
      database.mediaCacheEntries,
    )..where((r) => r.protected.equals(false))).get();
    for (final entry in entries) {
      await _remove(entry);
    }
  });

  Future<void> clearScope() => _serial(() async {
    final entries = await (database.select(
      database.mediaCacheEntries,
    )..where((r) => r.scope.equals(scope))).get();
    for (final entry in entries) {
      await _remove(entry);
    }
  });
}
