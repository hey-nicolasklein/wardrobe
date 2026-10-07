import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/features/intake/intake_bloc.dart';
import 'package:form_mobile/features/intake/intake_failure.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/credits_repository.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:image_picker/image_picker.dart';

/// Asks whether to take a photo or choose from the library. [message] sits
/// under the title, e.g. what adding costs. Null when the user cancels.
Future<bool?> pickPhotoSource(
  BuildContext context, {
  required String title,
  String? message,
}) => showCupertinoModalPopup<bool>(
  context: context,
  builder: (context) => CupertinoActionSheet(
    title: Text(title),
    message: message == null ? null : Text(message),
    actions: [
      CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context, false),
        child: Text(context.tr(LocaleKeys.intake_library)),
      ),
      CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context, true),
        child: Text(context.tr(LocaleKeys.intake_camera)),
      ),
    ],
    cancelButton: CupertinoActionSheetAction(
      onPressed: () => Navigator.pop(context),
      child: Text(context.tr(LocaleKeys.cancel)),
    ),
  ),
);

/// Picks photos with the camera or from the library. Picker failures show
/// as a toast, with a way to the system settings when access is missing.
Future<List<String>> pickPhotos(
  BuildContext context, {
  required bool camera,
}) async {
  try {
    final picker = ImagePicker();
    if (camera) {
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        requestFullMetadata: false,
      );
      return photo == null ? const [] : [photo.path];
    }
    return [
      for (final file in await picker.pickMultiImage(
        requestFullMetadata: false,
      ))
        file.path,
    ];
  } on Object catch (error) {
    if (context.mounted) {
      final key = intakeFailureKey(
        error,
        fallback: LocaleKeys.intake_invalidPhoto,
      );
      showFormToast(
        context,
        context.tr(key),
        action: key == LocaleKeys.intake_permission
            ? context.tr(LocaleKeys.intake_openSettings)
            : null,
        onAction: key == LocaleKeys.intake_permission
            ? AppSettings.openAppSettings
            : null,
      );
    }
    return const [];
  }
}

/// Adds clothes from photos without leaving the current page: the photos go
/// to [IntakeBloc], which detects and saves their pieces in the background.
/// [camera] skips the source question. Returns whether photos were added.
Future<bool> addClothesPhotos(BuildContext context, {bool? camera}) async {
  final source =
      camera ??
      await pickPhotoSource(
        context,
        title: context.tr(LocaleKeys.intake_title),
        // Pieces are saved without another step, so the cost is said here.
        message: context.tr(
          LocaleKeys.intake_costShort,
          namedArgs: {'credits': '$shelfImageCreditCost'},
        ),
      );
  if (source == null || !context.mounted) return false;
  final paths = await pickPhotos(context, camera: source);
  if (paths.isEmpty || !context.mounted) return false;
  unawaited(HapticFeedback.mediumImpact());
  context.read<IntakeBloc>().add(IntakeEvent(IntakeAction.add, paths: paths));
  showFormToast(
    context,
    context.plural(LocaleKeys.intake_arriving, paths.length),
  );
  return true;
}
