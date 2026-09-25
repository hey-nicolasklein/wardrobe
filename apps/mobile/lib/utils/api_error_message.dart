import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/services/form_api.dart';

String localizedApiError(BuildContext context, FormApiException error) {
  final key = _messageKey(error.code);
  if (key != null) return context.tr(key);
  return apiFailureText(context, error.failure);
}

String? _messageKey(String? code) => switch (code) {
  'active-character-sheet' => LocaleKeys.apiErrors_activeCharacterSheet,
  'asset-content-missing' => LocaleKeys.apiErrors_assetContentMissing,
  'asset-not-found' => LocaleKeys.apiErrors_assetNotFound,
  'authentication-required' => LocaleKeys.missingSession,
  'character-sheet-processing' => LocaleKeys.apiErrors_characterSheetProcessing,
  'confirmation-required' => LocaleKeys.apiErrors_confirmationRequired,
  'generation-in-progress' => LocaleKeys.apiErrors_generationInProgress,
  'idempotency-key-reused' => LocaleKeys.apiErrors_idempotencyKeyReused,
  'invalid-activation' => LocaleKeys.apiErrors_invalidActivation,
  'invalid-character-sheet' => LocaleKeys.apiErrors_invalidCharacterSheet,
  'invalid-detection-request' => LocaleKeys.apiErrors_invalidDetectionRequest,
  'invalid-generation-request' => LocaleKeys.apiErrors_invalidGenerationRequest,
  'invalid-item-state' => LocaleKeys.apiErrors_invalidItemState,
  'invalid-keep-request' => LocaleKeys.apiErrors_invalidKeepRequest,
  'invalid-look' => LocaleKeys.apiErrors_invalidLook,
  'invalid-permanent-deletion' => LocaleKeys.apiErrors_invalidPermanentDeletion,
  'invalid-photo-item' => LocaleKeys.apiErrors_invalidPhotoItem,
  'invalid-reject-request' => LocaleKeys.apiErrors_invalidRejectRequest,
  'invalid-restore-request' => LocaleKeys.apiErrors_invalidRestoreRequest,
  'invalid-retry' => LocaleKeys.apiErrors_invalidRetry,
  'invalid-sign-in-request' => LocaleKeys.apiErrors_invalidSignInRequest,
  'invalid-upload-intent' => LocaleKeys.apiErrors_invalidUploadIntent,
  'invalid-wardrobe-edit' => LocaleKeys.apiErrors_invalidWardrobeEdit,
  'invalid-wardrobe-item' => LocaleKeys.apiErrors_invalidWardrobeItem,
  'invalid-wardrobe-transition' =>
    LocaleKeys.apiErrors_invalidWardrobeTransition,
  'origin-not-allowed' => LocaleKeys.apiErrors_originNotAllowed,
  'reset-in-progress' => LocaleKeys.apiErrors_resetInProgress,
  'source-photo-not-found' => LocaleKeys.apiErrors_sourcePhotoNotFound,
  'stale-record-version' => LocaleKeys.apiErrors_staleRecordVersion,
  'upload-intent-not-found' => LocaleKeys.apiErrors_uploadIntentNotFound,
  'upload-missing' => LocaleKeys.apiErrors_uploadMissing,
  'wardrobe-item-not-found' => LocaleKeys.apiErrors_wardrobeItemNotFound,
  _ => null,
};
