import 'package:bloc/bloc.dart';
import 'package:form_mobile/repository/preferences_repository.dart';

class QualityPreferences {
  const QualityPreferences({
    required this.feed,
    required this.wardrobe,
    this.lookStyle,
  });

  final String feed;
  final String wardrobe;

  /// The photo style new looks use, or null to follow the occasion.
  final String? lookStyle;
}

class QualityCubit extends Cubit<QualityPreferences> {
  QualityCubit(this._repository, QualityPreferences initial) : super(initial);

  final PreferencesRepository _repository;

  Future<void> setFeed(String quality) async {
    if (state.feed == quality) return;
    await _repository.setFeedQuality(quality);
    if (!isClosed) {
      emit(
        QualityPreferences(
          feed: quality,
          wardrobe: state.wardrobe,
          lookStyle: state.lookStyle,
        ),
      );
    }
  }

  Future<void> setWardrobe(String quality) async {
    if (state.wardrobe == quality) return;
    await _repository.setWardrobeQuality(quality);
    if (!isClosed) {
      emit(
        QualityPreferences(
          feed: state.feed,
          wardrobe: quality,
          lookStyle: state.lookStyle,
        ),
      );
    }
  }

  Future<void> setLookStyle(String? style) async {
    if (state.lookStyle == style) return;
    await _repository.setLookStyle(style);
    if (!isClosed) {
      emit(
        QualityPreferences(
          feed: state.feed,
          wardrobe: state.wardrobe,
          lookStyle: style,
        ),
      );
    }
  }
}
