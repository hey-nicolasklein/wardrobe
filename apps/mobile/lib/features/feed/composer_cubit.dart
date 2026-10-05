import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/features/feed/look_commands.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/idempotency_key.dart';

/// The contract accepts at most this many exact pieces per look.
const maxComposerPieces = 12;

/// Photo styles the API accepts for a look, in picker order.
const lookStyles = ['candid', 'street', 'mirror'];

/// The style an automatic look uses for [occasion]: everyday looks become
/// street-style fit pics, everything else a candid snapshot (with flash at
/// night, which the server derives from the occasion).
String autoLookStyle(String? occasion) =>
    occasion == 'casual' ? 'street' : 'candid';

/// What fills the outfit around the picked pieces: more wardrobe pieces,
/// garments the image model invents, or nothing, with the photo framed on the
/// picked pieces.
const lookCompletions = ['wardrobe', 'model', 'selected'];

/// Whether a `selected` photo can frame [categories] in one body zone. Mirrors
/// `lookFocus` in packages/service: tops with shoes, or a dress, need a
/// full-body photo. Bags and accessories fit any zone.
bool canFrameOnly(Iterable<String> categories) {
  bool has(Set<String> wanted) => categories.any(wanted.contains);
  final upper = has(const {'top', 'jacket', 'hat', 'scarf'});
  final lowerOrShoes = has(const {'pants', 'skirt', 'shoes'});
  return !has(const {'dress'}) && !(upper && lowerOrShoes);
}

class ComposerState {
  const ComposerState({
    this.selectedIds = const {},
    this.categories = const {},
    this.occasion,
    this.style,
    this.quality = 'low',
    this.completion = 'wardrobe',
    this.selectedOnly = false,
    this.tryOn = false,
    this.tryOnBases = const [],
    this.baseAssetId,
    this.uploadingBase = false,
    this.itemCategory,
    this.itemColor,
    this.query = '',
    this.previewExpanded = false,
    this.selectedPieceId,
    this.submitting = false,
    this.limitReached = false,
    this.failure,
    this.createdLookId,
    this.proposed = false,
  });

  /// The pieces and choices [look] was made with, so it can be redone as is.
  factory ComposerState.fromLook(Look look) {
    final settings = look.settings;
    final occasion = settings?.occasion;
    return ComposerState(
      selectedIds: look.wardrobeItemIds.take(maxComposerPieces).toSet(),
      categories: settings?.categories.toSet() ?? const {},
      occasion: occasion,
      // A style that matches the occasion stays automatic, as it was picked.
      style: settings?.style == autoLookStyle(occasion)
          ? null
          : settings?.style,
      quality: look.quality,
      completion: settings?.completion ?? 'wardrobe',
      tryOn: look.isTryOn,
      baseAssetId: look.baseAssetId,
    );
  }

  final Set<String> selectedIds;

  /// Categories the look must include. Only sent while completing from the
  /// wardrobe, matching the PWA.
  final Set<String> categories;
  final String? occasion;

  /// How the feed image is photographed. One of [lookStyles], or null to
  /// follow the occasion, see [autoLookStyle].
  final String? style;
  String get resolvedStyle => style ?? autoLookStyle(occasion);

  /// Chosen per look, as in the PWA composer. The Settings default arrives in
  /// Slice 6.
  final String quality;

  /// One of [lookCompletions].
  final String completion;
  bool get completeWithWardrobe => completion == 'wardrobe';
  final bool selectedOnly;

  /// Try-on mode: dress one of the user's own photos in the picked pieces 1:1
  /// instead of generating a new scene.
  final bool tryOn;

  /// Photos earlier try-ons used, newest first, see
  /// [LookRepository.tryOnBases].
  final List<String> tryOnBases;
  final String? baseAssetId;
  final bool uploadingBase;

  /// A try-on needs a photo and at least one piece to put on it.
  bool get canSubmit =>
      !tryOn || (baseAssetId != null && selectedIds.isNotEmpty);

  /// The picker's category filter. Unrelated to [categories].
  final String? itemCategory;

  /// The picker's colour family filter, see [colorFamilies]. A colour often
  /// is the starting point of a look.
  final String? itemColor;
  final String query;
  final bool previewExpanded;
  final String? selectedPieceId;
  final bool submitting;

  /// The last tap tried to add a piece beyond [maxComposerPieces].
  final bool limitReached;
  final ApiFailure? failure;

  /// Set once the server accepted the look. The page closes on it.
  final String? createdLookId;

  /// Set once outfits were proposed instead of a look created. The page then
  /// switches to the proposals, where the user picks what to render.
  final bool proposed;

  /// Without picked pieces there is nothing to complete freely or frame alone.
  bool get canChooseCompletion => selectedIds.isNotEmpty;

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
            (itemColor == null ||
                item.metadata.colors.any(
                  (color) => colorFamilies(color).contains(itemColor),
                )) &&
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
    String? Function()? style,
    String? quality,
    String? completion,
    bool? selectedOnly,
    bool? tryOn,
    List<String>? tryOnBases,
    String? Function()? baseAssetId,
    bool? uploadingBase,
    String? Function()? itemCategory,
    String? Function()? itemColor,
    String? query,
    bool? previewExpanded,
    String? Function()? selectedPieceId,
    bool? submitting,
    bool? limitReached,
    ApiFailure? Function()? failure,
    String? createdLookId,
    bool? proposed,
  }) => ComposerState(
    selectedIds: selectedIds ?? this.selectedIds,
    categories: categories ?? this.categories,
    occasion: occasion == null ? this.occasion : occasion(),
    style: style == null ? this.style : style(),
    quality: quality ?? this.quality,
    completion: completion ?? this.completion,
    selectedOnly: selectedOnly ?? this.selectedOnly,
    tryOn: tryOn ?? this.tryOn,
    tryOnBases: tryOnBases ?? this.tryOnBases,
    baseAssetId: baseAssetId == null ? this.baseAssetId : baseAssetId(),
    uploadingBase: uploadingBase ?? this.uploadingBase,
    itemCategory: itemCategory == null ? this.itemCategory : itemCategory(),
    itemColor: itemColor == null ? this.itemColor : itemColor(),
    query: query ?? this.query,
    previewExpanded: previewExpanded ?? this.previewExpanded,
    selectedPieceId: selectedPieceId == null
        ? this.selectedPieceId
        : selectedPieceId(),
    submitting: submitting ?? this.submitting,
    limitReached: limitReached ?? false,
    failure: failure == null ? this.failure : failure(),
    createdLookId: createdLookId ?? this.createdLookId,
    proposed: proposed ?? this.proposed,
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
    String? defaultStyle,
    bool tryOn = false,
    Look? from,
  }) : idempotencyKey = idempotencyKey ?? newIdempotencyKey(),
       _defaultQuality = defaultQuality,
       _defaultStyle = defaultStyle,
       super(
         from != null
             ? ComposerState.fromLook(from)
             : ComposerState(
                 selectedIds: preselectedIds.toSet(),
                 quality: defaultQuality,
                 style: defaultStyle,
                 tryOn: tryOn,
               ),
       ) {
    unawaited(_loadBases());
  }

  Future<void> _loadBases() async {
    final bases = await looks.tryOnBases();
    if (isClosed) return;
    emit(
      state.copyWith(
        tryOnBases: bases,
        // The latest photo keeps new try-ons comparable with the last ones.
        baseAssetId: () => state.baseAssetId ?? bases.firstOrNull,
      ),
    );
  }

  final LookRepository looks;
  final String idempotencyKey;
  final String _defaultQuality;
  final String? _defaultStyle;

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
        completion: next.isEmpty ? 'wardrobe' : null,
        selectedPieceId: state.selectedPieceId == id ? () => null : null,
      ),
    );
  }

  void setTryOn({required bool tryOn}) => emit(state.copyWith(tryOn: tryOn));

  void selectBase(String assetId) =>
      emit(state.copyWith(baseAssetId: () => assetId));

  /// Uploads a new photo of the user and selects it as the try-on base.
  Future<void> addBase(Future<Uint8List> Function() prepare) async {
    if (state.uploadingBase) return;
    emit(state.copyWith(uploadingBase: true, failure: () => null));
    try {
      final assetId = await looks.uploadTryOnPhoto(await prepare());
      if (isClosed) return;
      emit(
        state.copyWith(
          uploadingBase: false,
          tryOnBases: [assetId, ...state.tryOnBases],
          baseAssetId: () => assetId,
        ),
      );
    } on FormApiException catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(uploadingBase: false, failure: () => error.failure),
        );
      }
    }
  }

  void setOccasion(String? occasion) =>
      emit(state.copyWith(occasion: () => occasion));

  /// Null returns to the automatic style.
  void setStyle(String? style) => emit(state.copyWith(style: () => style));

  void setQuality(String quality) => emit(state.copyWith(quality: quality));

  void setQuery(String query) => emit(state.copyWith(query: query));

  void setItemCategory(String? category) => emit(
    state.copyWith(itemCategory: () => category, selectedOnly: false),
  );

  /// Tapping the active colour again clears it.
  void setItemColor(String family) => emit(
    state.copyWith(
      itemColor: () => state.itemColor == family ? null : family,
      selectedOnly: false,
    ),
  );

  void toggleSelectedOnly() =>
      emit(state.copyWith(selectedOnly: !state.selectedOnly));

  /// Leaving `wardrobe` also drops required categories, as in the PWA.
  void setCompletion(String completion) {
    if (!state.canChooseCompletion) return;
    emit(
      state.copyWith(
        completion: completion,
        categories: completion == 'wardrobe' ? null : const {},
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

  void reset() => emit(
    ComposerState(
      quality: _defaultQuality,
      style: _defaultStyle,
      tryOn: state.tryOn,
      tryOnBases: state.tryOnBases,
      baseAssetId: state.baseAssetId,
    ),
  );

  LookCommand command() => state.tryOn
      ? LookCommand.create(
          exactItemIds: state.selectedIds.toList(),
          categories: const [],
          occasion: null,
          baseAssetId: state.baseAssetId,
          quality: state.quality,
          idempotencyKey: idempotencyKey,
        )
      : LookCommand.create(
          exactItemIds: state.selectedIds.toList(),
          categories: state.completeWithWardrobe
              ? state.categories.toList()
              : [],
          occasion: state.occasion,
          style: state.resolvedStyle,
          completion: state.completion,
          quality: state.quality,
          idempotencyKey: idempotencyKey,
        );

  Future<void> submit() async {
    if (state.submitting ||
        state.createdLookId != null ||
        state.proposed ||
        !state.canSubmit) {
      return;
    }
    emit(state.copyWith(submitting: true, failure: () => null));
    try {
      // New scenes are proposed first; a try-on has nothing to choose.
      if (!state.tryOn) {
        await looks.propose(command().body);
        emit(state.copyWith(submitting: false, proposed: true));
        return;
      }
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
