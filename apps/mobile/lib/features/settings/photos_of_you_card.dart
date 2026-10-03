import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/character/character_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:go_router/go_router.dart';

/// The personal entry at the top of Settings: a fan of the user's own
/// photos, from the collage and the try-on photos, leading to "Photos of
/// you".
class PhotosOfYouCard extends StatefulWidget {
  const PhotosOfYouCard({super.key});

  @override
  State<PhotosOfYouCard> createState() => _PhotosOfYouCardState();
}

class _PhotosOfYouCardState extends State<PhotosOfYouCard> {
  List<String> _tryOn = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final photos = await context.read<LookRepository>().tryOnBases();
    if (mounted) setState(() => _tryOn = photos);
  }

  @override
  Widget build(BuildContext context) {
    final collage =
        context.watch<CharacterCubit>().state.current?.referenceAssetIds ??
        const <String>[];
    final online =
        context.watch<ConnectionCubit>().state == ConnectionStatus.ready;
    final shown = [...collage, ..._tryOn].take(3).toList();
    final subtitle = [
      if (collage.isNotEmpty)
        context.tr(
          LocaleKeys.photosOfYouCollage,
          namedArgs: {'count': '${collage.length}'},
        ),
      if (_tryOn.isNotEmpty)
        context.tr(
          LocaleKeys.photosOfYouTryOn,
          namedArgs: {'count': '${_tryOn.length}'},
        ),
    ].join(' · ');
    return Semantics(
      button: true,
      label: context.tr(LocaleKeys.photosOfYou),
      child: Material(
        color: FormTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FormTokens.cardRadius),
          side: const BorderSide(color: FormTokens.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(
            context.push('/settings/character').then((_) => _load()),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Row(
              children: [
                _Fan(assetIds: shown, online: online),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        context.tr(LocaleKeys.photosOfYou),
                        style: FormTokens.heading.copyWith(fontSize: 21),
                      ),
                      Text(
                        subtitle.isEmpty
                            ? context.tr(LocaleKeys.photosOfYouEmpty)
                            : subtitle,
                        style: FormTokens.small.copyWith(
                          color: FormTokens.noteInk,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: FormTokens.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three portrait photos, slightly turned like prints on a table. With
/// none yet, an empty print with a person outline.
class _Fan extends StatelessWidget {
  const _Fan({required this.assetIds, required this.online});

  static const _photo = Size(56, 72);
  static const _angles = [-0.12, 0.1, -0.02];
  static const _offsets = [0.0, 30.0, 15.0];

  final List<String> assetIds;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final count = math.max(assetIds.length, 1);
    final width = _photo.width + (count > 1 ? 30 : 0) + 8;
    return SizedBox(
      width: width,
      height: _photo.height + 12,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (assetIds.isEmpty)
            _print(
              const ColoredBox(
                color: FormTokens.uploadTint,
                child: Icon(
                  Icons.person_outline_rounded,
                  color: FormTokens.emptyIcon,
                ),
              ),
              0,
              0,
            )
          else
            for (final (index, assetId) in assetIds.indexed)
              _print(
                CachedMedia(
                  identity: assetId,
                  previewPath: 'v1/assets/$assetId/content',
                  online: online,
                  fit: BoxFit.cover,
                  entrance: MediaEntrance.fade,
                ),
                _angles[index],
                _offsets[index],
              ),
        ],
      ),
    );
  }

  Widget _print(Widget child, double angle, double left) => Positioned(
    left: left + 4,
    child: Transform.rotate(
      angle: angle,
      child: Container(
        width: _photo.width,
        height: _photo.height,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: FormTokens.surface,
          borderRadius: BorderRadius.circular(9),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22242923),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: child,
        ),
      ),
    ),
  );
}
