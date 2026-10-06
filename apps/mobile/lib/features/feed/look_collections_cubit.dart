import 'package:bloc/bloc.dart';
import 'package:form_mobile/repository/look_collection_repository.dart';
import 'package:form_mobile/services/form_api.dart';

/// The user's Sammlungen, oldest first. Changes show right away and roll back
/// when the server refuses them.
class LookCollectionsCubit extends Cubit<List<LookCollection>> {
  LookCollectionsCubit(this.repository) : super(const []);

  final LookCollectionRepository repository;

  Future<void> loadCache() async {
    final cached = await repository.cached();
    if (!isClosed) emit(cached);
  }

  Future<void> load() async {
    try {
      final fresh = await repository.refresh();
      if (!isClosed) emit(fresh);
    } on FormApiException {
      // The cached list stays until the next load.
    }
  }

  /// Creates a Sammlung and, with [lookId], files that look into it.
  Future<LookCollection> create({
    required String name,
    required String emoji,
    String? lookId,
  }) async {
    var collection = await repository.create(name: name, emoji: emoji);
    if (lookId != null) {
      await repository.setLook(collection.id, lookId, included: true);
      collection = collection.withLook(lookId, included: true);
    }
    if (!isClosed) emit([...state, collection]);
    await repository.remember(state);
    return collection;
  }

  Future<void> remove(String collectionId) async {
    final before = state;
    emit([
      for (final c in state)
        if (c.id != collectionId) c,
    ]);
    try {
      await repository.delete(collectionId);
      await repository.remember(state);
    } on FormApiException {
      if (!isClosed) emit(before);
      rethrow;
    }
  }

  Future<void> toggle(String collectionId, String lookId) async {
    final before = state;
    final included = !before
        .firstWhere((c) => c.id == collectionId)
        .lookIds
        .contains(lookId);
    emit([
      for (final c in state)
        c.id == collectionId ? c.withLook(lookId, included: included) : c,
    ]);
    try {
      await repository.setLook(collectionId, lookId, included: included);
      await repository.remember(state);
    } on FormApiException {
      if (!isClosed) emit(before);
      rethrow;
    }
  }
}

/// The Sammlungen [lookId] is filed in.
List<LookCollection> collectionsOf(
  List<LookCollection> collections,
  String lookId,
) => [
  for (final c in collections)
    if (c.lookIds.contains(lookId)) c,
];
