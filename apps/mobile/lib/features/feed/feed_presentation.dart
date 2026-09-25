import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:form_mobile/features/feed/composer_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/services/look_output_service.dart';
import 'package:form_mobile/widgets/form_components.dart';

/// "Today", "3 days ago", or a short date after one week, as in the PWA.
String lookDateText(BuildContext context, DateTime createdAt) {
  final days = lookAgeDays(createdAt);
  return switch (days) {
    0 => context.tr(LocaleKeys.lookDateToday),
    1 => context.tr(LocaleKeys.lookDateOneDay),
    <= 7 => context.tr(
      LocaleKeys.lookDateDays,
      namedArgs: {'count': '$days'},
    ),
    _ => DateFormat.yMd(context.locale.toString()).format(createdAt.toLocal()),
  };
}

FlatLayLabels flatLayLabels(BuildContext context, Look look, int pieces) =>
    FlatLayLabels(
      heading: context.tr(LocaleKeys.flatLayHeading),
      moodFallback: context.tr(LocaleKeys.flatLayMoodFallback),
      meta: context.tr(
        LocaleKeys.flatLayMeta,
        namedArgs: {
          'count': '$pieces',
          'date': DateFormat.yMd(
            context.locale.toString(),
          ).format(look.createdAt.toLocal()),
        },
      ),
    );

/// The composer footer line, e.g. "2 pieces + wardrobe · 1 categories for a
/// night out".
String composerSummaryText(BuildContext context, ComposerState state) {
  final count = state.selectedIds.length;
  final categories = state.categories.length;
  final String summary;
  if (count > 0) {
    summary = [
      if (count == 1)
        context.tr(LocaleKeys.composerSummaryOnePiece)
      else
        context.tr(
          LocaleKeys.composerSummaryPieces,
          namedArgs: {'count': '$count'},
        ),
      context.tr(
        state.completeWithWardrobe
            ? LocaleKeys.composerSummaryWithWardrobe
            : LocaleKeys.composerSummaryFreeCompletion,
      ),
      if (categories > 0)
        context.tr(
          LocaleKeys.composerSummaryCategories,
          namedArgs: {'count': '$categories'},
        ),
    ].join(' ');
  } else if (categories > 0) {
    summary = context.tr(
      LocaleKeys.composerSummaryCategoriesOnly,
      namedArgs: {'count': '$categories'},
    );
  } else {
    summary = context.tr(LocaleKeys.composerSummaryDefault);
  }
  final occasion = switch (state.occasion) {
    'night-out' => context.tr(LocaleKeys.composerOccasionSuffixNightOut),
    'party' => context.tr(LocaleKeys.composerOccasionSuffixParty),
    'casual' => context.tr(LocaleKeys.composerOccasionSuffixCasual),
    _ => null,
  };
  return occasion == null ? summary : '$summary $occasion';
}

String apiFailureText(BuildContext context, ApiFailure failure) =>
    context.tr(switch (failure) {
      ApiFailure.unavailable => LocaleKeys.unavailable,
      ApiFailure.missingSession => LocaleKeys.missingSession,
      ApiFailure.incompatible ||
      ApiFailure.rejected => LocaleKeys.feedActionFailed,
    });

/// Runs a feed action and reports its outcome as a toast. Server, share, and
/// Photos failures become localized messages instead of unhandled errors.
Future<void> runFeedAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  String? message;
  try {
    await action();
    message = success;
  } on FormApiException catch (error) {
    if (!context.mounted) return;
    message = apiFailureText(context, error.failure);
  } on LookOutputException catch (error) {
    if (!context.mounted) return;
    message = context.tr(switch (error.failure) {
      LookOutputFailure.missingPieces => LocaleKeys.lookFlatMissingPieces,
      LookOutputFailure.missingImage => LocaleKeys.lookImageUnavailable,
      LookOutputFailure.photosDenied => LocaleKeys.lookPhotosDenied,
    });
  } on Exception {
    if (!context.mounted) return;
    message = context.tr(LocaleKeys.feedActionFailed);
  }
  if (message != null && context.mounted) showFormToast(context, message);
}
