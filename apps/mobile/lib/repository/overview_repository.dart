import 'package:drift/drift.dart';
import 'package:form_mobile/repository/cached_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

enum Collection { feed, wardrobe }

class OverviewRepository {
  const OverviewRepository(this._database, this._api, this._scope);

  final AppDatabase _database;
  final FormApi? _api;
  final String _scope;

  CachedRepository<int> collection(Collection collection) => CachedRepository(
    readCache: () async =>
        (await (_database.select(_database.collectionSummaries)..where(
                  (row) =>
                      row.scope.equals(_scope) &
                      row.collection.equals(collection.name),
                ))
                .getSingleOrNull())
            ?.count,
    fetch: () async {
      final api = _api;
      if (api == null) throw const FormApiException(ApiFailure.unavailable);
      return api.collectionCount(feed: collection == Collection.feed);
    },
    writeCache: (count) async {
      await _database
          .into(_database.collectionSummaries)
          .insertOnConflictUpdate(
            CollectionSummariesCompanion.insert(
              scope: _scope,
              collection: collection.name,
              count: count,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
    },
  );
}
