import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/services/photo_preparation.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:image_picker/image_picker.dart';

/// The user's try-on photos: add several at once so the try-on already has a
/// choice, or delete one together with its file.
class TryOnPhotosSection extends StatefulWidget {
  const TryOnPhotosSection({super.key});

  @override
  State<TryOnPhotosSection> createState() => _TryOnPhotosSectionState();
}

class _TryOnPhotosSectionState extends State<TryOnPhotosSection> {
  List<String>? _photos;
  bool _uploading = false;
  ApiFailure? _failure;

  LookRepository get _looks => context.read<LookRepository>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final photos = await _looks.tryOnBases();
    if (mounted) setState(() => _photos = photos);
  }

  Future<void> _add() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _uploading = true;
      _failure = null;
    });
    try {
      for (final file in picked) {
        final prepared = await PhotoPreparation().prepare(file.path);
        final jpeg = await compute(cropToLookFormat, prepared.bytes);
        final assetId = await _looks.uploadTryOnPhoto(jpeg);
        if (mounted) setState(() => _photos = [assetId, ...?_photos]);
      }
    } on FormApiException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(String assetId) async {
    final confirmed = await confirmFormAction(
      context: context,
      title: context.tr(LocaleKeys.tryOnPhotos_deleteTitle),
      message: context.tr(LocaleKeys.tryOnPhotos_deleteBody),
      confirmLabel: context.tr(LocaleKeys.tryOnPhotos_delete),
    );
    if (!confirmed || !mounted) return;
    setState(() => _failure = null);
    try {
      await _looks.deleteTryOnPhoto(assetId);
      if (mounted) {
        setState(() => _photos = [...?_photos]..remove(assetId));
      }
    } on FormApiException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online =
        context.watch<ConnectionCubit>().state == ConnectionStatus.ready;
    final photos = _photos;
    return FormPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            context.tr(LocaleKeys.tryOnPhotos_title),
            style: FormTokens.body.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            context.tr(LocaleKeys.tryOnPhotos_body),
            style: FormTokens.small,
          ),
          if (_failure case final failure?)
            FormNotice(text: apiFailureText(context, failure), error: true),
          if (photos == null)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else
            GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 4 / 5,
              shrinkWrap: true,
              // Without it the grid inherits the safe-area inset as padding.
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _AddTile(
                  uploading: _uploading,
                  onTap: _uploading || !online ? null : () => unawaited(_add()),
                ),
                for (final assetId in photos)
                  _PhotoTile(
                    key: ValueKey(assetId),
                    assetId: assetId,
                    online: online,
                    onDelete: online ? () => unawaited(_delete(assetId)) : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.uploading, required this.onTap});

  final bool uploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.tr(LocaleKeys.tryOnPhotos_add),
    excludeSemantics: true,
    child: Material(
      color: FormTokens.uploadTint,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: uploading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Opacity(
                  opacity: onTap == null ? 0.45 : 1,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      const Icon(
                        Icons.add_a_photo_outlined,
                        color: FormTokens.green,
                      ),
                      Text(
                        context.tr(LocaleKeys.tryOnPhotos_add),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: FormTokens.green,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    ),
  );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.assetId,
    required this.online,
    required this.onDelete,
    super.key,
  });

  final String assetId;
  final bool online;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedMedia(
          identity: assetId,
          previewPath: 'v1/assets/$assetId/content',
          online: online,
          fit: BoxFit.cover,
          entrance: MediaEntrance.fade,
        ),
      ),
      Positioned(
        top: 2,
        right: 2,
        child: IconButton(
          onPressed: onDelete,
          tooltip: context.tr(LocaleKeys.tryOnPhotos_delete),
          style: IconButton.styleFrom(
            backgroundColor: FormTokens.surface.withValues(alpha: 0.9),
            minimumSize: const Size(32, 32),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(
            Icons.close_rounded,
            size: 18,
            color: FormTokens.ink,
          ),
        ),
      ),
    ],
  );
}
