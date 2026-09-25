import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/settings/reset_confirmation.dart';

void main() {
  test('reset phrases match locale and API value stays independent', () {
    expect(requiredResetPhrase('de'), 'ALLES LÖSCHEN');
    expect(requiredResetPhrase('en'), 'DELETE EVERYTHING');
    expect(matchesResetPhrase('de', 'ALLES LÖSCHEN'), isTrue);
    expect(matchesResetPhrase('en', 'DELETE EVERYTHING'), isTrue);
    expect(matchesResetPhrase('de', 'DELETE EVERYTHING'), isFalse);
    expect(personalResetApiConfirmation, 'DELETE EVERYTHING');
  });
}
