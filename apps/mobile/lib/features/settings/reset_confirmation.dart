/// Locale-independent value sent to `POST /v1/personal/reset` after local validation.
const personalResetApiConfirmation = 'DELETE EVERYTHING';

const _phrases = {'de': 'ALLES LÖSCHEN', 'en': 'DELETE EVERYTHING'};

String requiredResetPhrase(String languageCode) =>
    _phrases[languageCode] ?? _phrases['de']!;

/// Ignores surrounding whitespace, letter case and doubled spaces, so a
/// keyboard that types "ö" or adds a trailing space still matches.
bool matchesResetPhrase(String languageCode, String input) =>
    input.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase() ==
    requiredResetPhrase(languageCode);
