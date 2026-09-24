import 'package:flutter/services.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';

String intakeFailureKey(Object error, {required String fallback}) {
  if (error is MissingPluginException ||
      (error is PlatformException && error.code == 'channel-error')) {
    return LocaleKeys.intake_restartRequired;
  }
  if (error is PlatformException && error.code.contains('access')) {
    return LocaleKeys.intake_permission;
  }
  if (error is FormatException && error.message == 'intake.fileSize') {
    return LocaleKeys.intake_fileSize;
  }
  return fallback;
}
