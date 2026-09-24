import 'package:bloc/bloc.dart';
import 'package:form_mobile/repository/preferences_repository.dart';

class LanguageCubit extends Cubit<String> {
  LanguageCubit(this._repository, super.initialState);

  final PreferencesRepository _repository;

  Future<void> select(String language) async {
    if (state == language) return;
    await _repository.setLanguage(language);
    if (!isClosed) emit(language);
  }
}
