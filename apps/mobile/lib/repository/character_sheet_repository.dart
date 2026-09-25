import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/services/form_api.dart';

class CharacterSheetRepository {
  CharacterSheetRepository(this.api);

  final FormApi? api;

  Future<List<CharacterSheet>> fetch() async {
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    final response = await api!.request('v1/character-sheets');
    try {
      return (response['characterSheets'] as List<dynamic>)
          .map(
            (value) => CharacterSheet.fromJson(value as Map<String, dynamic>),
          )
          .toList();
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
  }

  Future<CharacterSheet?> activeReady() async {
    final sheets = await fetch();
    for (final sheet in sheets) {
      if (sheet.isActiveReady) return sheet;
    }
    return null;
  }
}
