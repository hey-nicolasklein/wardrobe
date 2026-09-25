import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/features/wardrobe/item_edit.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/form_api.dart';

class ItemState {
  const ItemState({
    this.detail,
    this.stale = true,
    this.busy = false,
    this.failure,
    this.deleted = false,
    this.pending,
  });
  final ItemDetail? detail;
  final bool stale;
  final bool busy;
  final ApiFailure? failure;
  final bool deleted;
  final ItemCommand? pending;
  bool get canStartCommand => canMutate && pending == null;
  bool get canGenerate =>
      canStartCommand &&
      !detail!.generating &&
      detail!.wardrobeItem.state != 'archived';
  bool canRestore(String version) =>
      canStartCommand &&
      !detail!.generating &&
      version != detail!.wardrobeItem.currentShelfImageVersionId;
  bool get canMutate => detail != null && !stale && !busy && !deleted;
}

class ItemCubit extends Cubit<ItemState> {
  ItemCubit(this.repository, this.id) : super(const ItemState());
  final WardrobeRepository repository;
  final String id;
  int _availability = 0;
  Timer? _poll;
  bool _foreground = true;
  Future<void> _moves = Future.value();
  int _movesInFlight = 0;

  void setForeground({required bool foreground}) {
    _foreground = foreground;
    _schedulePoll(state);
  }

  void _schedulePoll(ItemState next) {
    _poll?.cancel();
    if (_foreground &&
        !next.stale &&
        !next.busy &&
        (next.detail?.generating ?? false)) {
      _poll = Timer(const Duration(seconds: 3), () => unawaited(refresh()));
    }
  }

  @override
  void onChange(Change<ItemState> change) {
    super.onChange(change);
    _schedulePoll(change.nextState);
  }

  Future<void> edit(ItemEdit edit) =>
      execute(ItemCommand.edit(state.detail!.wardrobeItem, edit.toJson()));

  /// Flips the collection at once and keeps the page interactive while the
  /// PATCH runs. Moves are sent in order against the last confirmed record
  /// version, and a failure falls back to the confirmed detail.
  Future<void> move(String collection) {
    final detail = state.detail;
    if (!state.canStartCommand || detail!.wardrobeItem.state == collection) {
      return _moves;
    }
    emit(
      ItemState(detail: _withCollection(detail, collection), stale: false),
    );
    _movesInFlight++;
    return _moves = _moves.then((_) => _sendMove(collection));
  }

  Future<void> _sendMove(String collection) async {
    try {
      // Superseded by a later toggle before it was sent.
      if (isClosed || state.detail?.wardrobeItem.state != collection) return;
      final confirmed = (await repository.cachedDetail(id))!;
      if (confirmed.wardrobeItem.state == collection) return;
      await repository.execute(
        id,
        ItemCommand.edit(confirmed.wardrobeItem, {'state': collection}),
      );
      final fresh = await repository.cachedDetail(id);
      if (!isClosed && _movesInFlight == 1) {
        emit(ItemState(detail: fresh, stale: state.stale));
      }
    } on Exception catch (error) {
      final failure = error is FormApiException
          ? error.failure
          : ApiFailure.unavailable;
      final confirmed = await repository.cachedDetail(id);
      if (!isClosed) {
        emit(
          ItemState(
            detail: confirmed ?? state.detail,
            stale: state.stale || failure == ApiFailure.unavailable,
            failure: failure,
          ),
        );
      }
    } finally {
      _movesInFlight--;
    }
  }

  static ItemDetail _withCollection(ItemDetail detail, String collection) {
    final item = detail.wardrobeItem;
    return ItemDetail(
      wardrobeItem: WardrobeItem(
        id: item.id,
        sourcePhotoId: item.sourcePhotoId,
        state: collection,
        status: item.status,
        metadata: item.metadata,
        currentShelfImageVersionId: item.currentShelfImageVersionId,
        recordVersion: item.recordVersion,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
      ),
      sourcePhoto: detail.sourcePhoto,
      shelfImageVersions: detail.shelfImageVersions,
      generationAttempts: detail.generationAttempts,
    );
  }

  Future<void> restore(String version) async {
    if (state.canRestore(version)) {
      await execute(ItemCommand.restore(state.detail!.wardrobeItem, version));
    }
  }

  Future<void> delete() =>
      execute(ItemCommand.delete(state.detail!.wardrobeItem));

  @override
  Future<void> close() async {
    _poll?.cancel();
    await super.close();
  }

  void markUnavailable() {
    _availability++;
    emit(
      ItemState(detail: state.detail, pending: state.pending, busy: state.busy),
    );
  }

  Future<void> load({required bool online}) async {
    final detail = await repository.cachedDetail(id);
    if (isClosed) return;
    emit(ItemState(detail: detail));
    if (online) await refresh();
  }

  Future<void> refresh() async {
    // A server snapshot taken mid-move would briefly undo the toggle.
    if (state.busy || isClosed || state.deleted || _movesInFlight > 0) return;
    final availability = _availability;
    emit(
      ItemState(
        detail: state.detail,
        stale: state.stale,
        busy: true,
        pending: state.pending,
      ),
    );
    try {
      final detail = await repository.detail(id);
      if (!isClosed) {
        emit(
          ItemState(
            detail: detail,
            stale: availability != _availability,
            pending: state.pending,
          ),
        );
      }
    } on Exception catch (error) {
      if (!isClosed) {
        emit(
          ItemState(
            detail: state.detail,
            pending: state.pending,
            failure: error is FormApiException
                ? error.failure
                : ApiFailure.unavailable,
          ),
        );
      }
    }
  }

  Future<void> execute(ItemCommand command) async {
    await _moves;
    if (!state.canMutate ||
        (state.pending != null && !identical(command, state.pending))) {
      return;
    }
    final availability = _availability;
    emit(
      ItemState(
        detail: state.detail,
        stale: false,
        busy: true,
        pending: command,
      ),
    );
    try {
      await repository.execute(id, command);
      final detail = command.method == 'DELETE'
          ? null
          : await repository.cachedDetail(id);
      if (!isClosed) {
        emit(
          ItemState(
            detail: detail,
            stale: availability != _availability,
            deleted: command.method == 'DELETE',
          ),
        );
      }
    } on Exception catch (error) {
      final failure = error is FormApiException
          ? error.failure
          : ApiFailure.unavailable;
      if (!isClosed) {
        emit(
          ItemState(
            detail: state.detail,
            stale:
                failure == ApiFailure.unavailable ||
                availability != _availability,
            failure: failure,
            pending: failure == ApiFailure.unavailable ? command : null,
          ),
        );
      }
    }
  }
}
