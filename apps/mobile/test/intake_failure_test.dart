import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/intake/intake_failure.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';

void main() {
  test(
    'missing native plugins ask for a fresh build, not a different photo',
    () {
      for (final error in [
        MissingPluginException(),
        PlatformException(code: 'channel-error'),
      ]) {
        expect(
          intakeFailureKey(error, fallback: LocaleKeys.intake_invalidPhoto),
          LocaleKeys.intake_restartRequired,
        );
      }
    },
  );
  test('permission and size failures retain their specific recovery', () {
    expect(
      intakeFailureKey(
        PlatformException(code: 'camera_access_denied'),
        fallback: LocaleKeys.intake_invalidPhoto,
      ),
      LocaleKeys.intake_permission,
    );
    expect(
      intakeFailureKey(
        const FormatException('intake.fileSize'),
        fallback: LocaleKeys.intake_invalidPhoto,
      ),
      LocaleKeys.intake_fileSize,
    );
  });
}
