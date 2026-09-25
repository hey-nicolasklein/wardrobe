import 'package:bloc/bloc.dart';
import 'package:form_mobile/features/feed/look_commands.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/idempotency_key.dart';

/// The contract accepts at most this many exact pieces per look.
const maxComposerPieces = 12;

class ComposerState {
  const ComposerState({
    this.selectedIds = const {},
    this.categories = const {},
    this.occasion,
    this.quality = 'low',
    this.completeWithWardrobe = true,
    this.selectedOnly = false,
    this.itemCategory,
    this.query = '',
    this.previewExpanded = false,
    this.selectedPieceId,
    this.submitting = false,
    this.limitReached = false,
    this.failure,
    this.createdLookId,
  });

  final Set<String> selectedIds;

  /// Categories the look must include. Only sent while completing from the
  /// wardrobe, matching the PWA.
  final Set<String> categories;
  final String? occasion;

  /// Chosen per look, as in the PWA composer. The Settings default arrives in
  /// Slice 6.
  final String quality;
  final bool completeWithWardrobe;
  final bool selectedOnly;

  /// The picker's category filter. Unrelated to [categories].
  final String? itemCategory;
  final String query;
  final bool previewExpanded;
  final String? selectedPieceId;
  final bool submitting;

  /// The last tap tried to add a piece beyond [maxComposerPieces].
  final bool limitReached;
  final ApiFailure? failure;

  /// Set once the server accepted the look. The page closes on it.
  final String? createdLookId;

  bool get canToggleCompletion => selectedIds.isNotEmpty;

  /// Pieces the picker shows. Selected-only mode ignores search and category,
  /// as in the PWA.
  List<WardrobeItem> visible(List<WardrobeItem> eligible) {
    if (selectedOnly) {
      return [
        for (final item in eligible)
          if (selectedIds.contains(item.id)) item,
      ];
    }
    final needle = query.trim().toLowerCase();
    return [
      for (final item in eligible)
        if ((itemCategory == null || item.metadata.category == itemCategory) &&
            _searchText(item).contains(needle))
          item,
    ];
  }

  List<WardrobeItem> selectedItems(List<WardrobeItem> eligible) => [
    for (final item in eligible)
      if (selectedIds.contains(item.id)) item,
  ];

  static String _searchText(WardrobeItem item) => [
    item.metadata.name,
    ...item.metadata.colors,
    item.metadata.notes ?? '',
  ].join(' ').toLowerCase();

  ComposerState copyWith({
    Set<String>? selectedIds,
    Set<String>? categories,
    String? Function()? occasion,
    String? quality,
    bool? completeWithWardrobe,
    bool? selectedOnly,
    String? Function()? itemCategory,
    String? query,
    bool? previewExpanded,
    String? Function()? selectedPieceId,
    bool? submitting,
    bool? limitReached,
    ApiFailure? Function()? failure,
    String? createdLookId,
  }) => ComposerState(
    selectedIds: selectedIds ?? this.selectedIds,
    categories: categories ?? this.categories,
    occasion: occasion == null ? this.occasion : occasion(),
    quality: quality ?? this.quality,
    completeWithWardrobe: completeWithWardrobe ?? this.completeWithWardrobe,
    selectedOnly: selectedOnly ?? this.selectedOnly,
    itemCategory: itemCategory == null ? this.itemCategory : itemCategory(),
    query: query ?? this.query,
    previewExpanded: previewExpanded ?? this.previewExpanded,
    selectedPieceId: selectedPieceId == null
        ? this.selectedPieceId
        : selectedPieceId(),
    submitting: submitting ?? this.submitting,
    limitReached: limitReached ?? false,
    failure: failure == null ? this.failure : failure(),
    createdLookId: createdLookId ?? this.createdLookId,
  );
}

/// Owns one look-composer session. The session keeps a single idempotency key,
/// so resubmitting after a failure can never create a second look.
class ComposerCubit extends Cubit<ComposerState> {
  ComposerCubit(
    this.looks, {
    List<String> preselectedIds = const [],
    String? idempotencyKey,
    String defaultQuality = 'low',
  }) : idempotencyKey = idempotencyKey ?? newIdempotencyKey(),
       _defaultQuality = defaultQuality,
       super(
         ComposerState(
           selectedIds: preselectedIds.toSet(),
           quality: defaultQuality,
         ),
       );

  final LookRepository looks;
  final String idempotencyKey;
  final String _defaultQuality;

  void toggleItem(String id) {
    final next = {...state.selectedIds};
    if (!next.remove(id)) {
      if (next.length >= maxComposerPieces) {
        emit(state.copyWith(limitReached: true));
        return;
      }
      next.add(id);
    }
    emit(
      state.copyWith(
        selectedIds: next,
        // With nothing selected the model has nothing to complete freely.
        completeWithWardrobe: next.isEmpty ? true : null,
        selectedPieceId: state.selectedPieceId == id ? () => null : null,
      ),
    );
  }

  void setOccasion(String? occasion) =>
      emit(state.copyWith(occasion: () => occasion));

  void setQuality(String quality) => emit(state.copyWith(quality: quality));

  void setQuery(String query) => emit(state.copyWith(query: query));

  void setItemCategory(String? category) => emit(
    state.copyWith(itemCategory: () => category, selectedOnly: false),
  );

  void toggleSelectedOnly() =>
      emit(state.copyWith(selectedOnly: !state.selectedOnly));

  /// Turning completion off also drops required categories, as in the PWA.
  void toggleCompleteWithWardrobe() {
    if (!state.canToggleCompletion) return;
    final value = !state.completeWithWardrobe;
    emit(
      state.copyWith(
        completeWithWardrobe: value,
        categories: value ? null : const {},
      ),
    );
  }

  void toggleCategory(String category) {
    final next = {...state.categories};
    if (!next.remove(category)) next.add(category);
    emit(state.copyWith(categories: next));
  }

  void openPreview() => emit(state.copyWith(previewExpanded: true));

  void closePreview() => emit(state.copyWith(previewExpanded: false));

  /// Tapping the highlighted piece again clears the highlight.
  void selectPiece(String? id) => emit(
    state.copyWith(
      selectedPieceId: () => id == state.selectedPieceId ? null : id,
    ),
  );

  void reset() => emit(ComposerState(quality: _defaultQuality));

  LookCommand command() => LookCommand.create(
    exactItemIds: state.selectedIds.toList(),
    categories: state.completeWithWardrobe ? state.categories.toList() : [],
    occasion: state.occasion,
    completeWithWardrobe: state.completeWithWardrobe,
    quality: state.quality,
    idempotencyKey: idempotencyKey,
  );

  Future<void> submit() async {
    if (state.submitting || state.createdLookId != null) return;
    emit(state.copyWith(submitting: true, failure: () => null));
    try {
      final lookId = await looks.create(
        command(),
        state.selectedIds.toList(),
      );
      emit(state.copyWith(submitting: false, createdLookId: lookId));
    } on FormApiException catch (error) {
      emit(state.copyWith(submitting: false, failure: () => error.failure));
    }
  }
}
