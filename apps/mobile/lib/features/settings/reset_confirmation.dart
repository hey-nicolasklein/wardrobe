/// Locale-independent value sent to `POST /v1/personal/reset` after local validation.
const personalResetApiConfirmation = 'DELETE EVERYTHING';

const _phrases = {'de': 'ALLES LÖSCHEN', 'en': 'DELETE EVERYTHING'};

String requiredResetPhrase(String languageCode) =>
    _phrases[languageCode] ?? _phrases['de']!;

bool matchesResetPhrase(String languageCode, String input) =>
    input == requiredResetPhrase(languageCode);
