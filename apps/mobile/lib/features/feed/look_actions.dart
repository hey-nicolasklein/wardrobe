import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_page.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/intake/intake_picker.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/features/settings/quality_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/credits_repository.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/services/photo_preparation.dart';
import 'package:form_mobile/utils/idempotency_key.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

/// The ways to start a look, all free: lay out pieces from the Schrank, keep
/// photos the user wore an outfit in, or swipe through FORM's suggestions.
Future<void> showNewLookSheet(BuildContext context) {
  unawaited(HapticFeedback.lightImpact());
  return showFormSheet<void>(
    context: context,
    builder: (sheetContext) {
      void then(void Function() action) {
        Navigator.pop(sheetContext);
        action();
      }

      return FormSheet(
        title: context.tr(LocaleKeys.newLookTitle),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            _NewLookOption(
              index: 0,
              icon: Icons.checkroom_outlined,
              title: context.tr(LocaleKeys.newLookCombine),
              body: context.tr(LocaleKeys.newLookCombineBody),
              onTap: () => then(() => openLookComposer(context)),
            ),
            _NewLookOption(
              index: 1,
              icon: Icons.photo_library_outlined,
              title: context.tr(LocaleKeys.newLookPhotos),
              body: context.tr(LocaleKeys.newLookPhotosBody),
              onTap: () => then(() => unawaited(addPhotoLooks(context))),
            ),
            _NewLookOption(
              index: 2,
              icon: Icons.auto_awesome_outlined,
              title: context.tr(LocaleKeys.newLookSuggest),
              body: context.tr(LocaleKeys.newLookSuggestBody),
              onTap: () => then(() => unawaited(suggestLooks(context))),
            ),
          ],
        ),
      );
    },
  );
}

/// Starts a round of FORM's suggestions from the whole Schrank.
Future<void> suggestLooks(BuildContext context) =>
    runFeedAction(context, () async {
      final body = <String, dynamic>{
        'exactItemIds': <String>[],
        'categories': <String>[],
        'occasion': null,
        'style': 'candid',
        'completion': 'wardrobe',
        'idempotencyKey': newIdempotencyKey(),
      };
      await context.read<LookRepository>().propose(body);
      if (context.mounted) {
        unawaited(context.push('/feed/proposals', extra: body));
      }
    });

/// Keeps photos from the library as looks. They land on the Looks pile right
/// away and their pieces are found in the background.
Future<void> addPhotoLooks(BuildContext context) async {
  final paths = await pickPhotos(context, camera: false);
  if (paths.isEmpty || !context.mounted) return;
  unawaited(HapticFeedback.mediumImpact());
  final feed = context.read<FeedCubit>();
  context.go('/feed');
  showFormToast(
    context,
    context.plural(LocaleKeys.photoLooksAdding, paths.length),
  );
  final failed = await feed.addPhotoLooks(
    paths,
    (path) async => (await PhotoPreparation().prepare(path)).bytes,
  );
  if (failed > 0 && context.mounted) {
    showFormToast(context, context.plural(LocaleKeys.photoLooksFailed, failed));
  }
}

/// Inspirations put the user into an AI photo, so they need photos of the
/// user first. Asked for here, the first time, instead of during onboarding.
/// Returns whether a reference is ready.
Future<bool> ensureCharacterReference(BuildContext context) async {
  if (context.read<FeedCubit>().state.hasActiveCharacterReference != false) {
    return true;
  }
  final start = await showFormSheet<bool>(
    context: context,
    builder: (sheetContext) => FormSheet(
      title: context.tr(LocaleKeys.referenceAskTitle),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _ReferenceIllustration()),
          const SizedBox(height: 20),
          Text(
            context.tr(LocaleKeys.referenceAskBody),
            style: FormTokens.body,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(LocaleKeys.referenceAskPrivacy),
            style: FormTokens.small,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(sheetContext, true),
            child: Text(context.tr(LocaleKeys.referenceAskStart)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(sheetContext, false),
            child: Text(context.tr(LocaleKeys.referenceAskLater)),
          ),
        ],
      ),
    ),
  );
  if (start != true || !context.mounted) return false;
  final done = await context.push<bool>('/feed/character-setup');
  return done ?? false;
}

/// Puts an AI image on top of the combination [look]: an `inspiration`
/// scene or a `try-on` on a photo of the user. Both are paid, so the cost is
/// confirmed first. The combination itself never changes.
Future<void> addLookImage(
  BuildContext context,
  Look look, {
  required String mode,
}) async {
  if (mode == 'inspiration' && !await ensureCharacterReference(context)) {
    return;
  }
  if (!context.mounted) return;
  unawaited(context.read<CreditsCubit>().refresh());
  await showFormSheet<void>(
    context: context,
    builder: (_) => _LookImageSheet(look: look, mode: mode, page: context),
  );
}

class _NewLookOption extends StatelessWidget {
  const _NewLookOption({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FormReveal(
    delay: Duration(milliseconds: 60 * index),
    child: Material(
      color: FormTokens.surface,
      borderRadius: BorderRadius.circular(FormTokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: FormTokens.selectedTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: FormTokens.green, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      title,
                      style: FormTokens.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(body, style: FormTokens.small),
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

/// Three overlapping photo frames, the shape of the collage that is asked for.
class _ReferenceIllustration extends StatelessWidget {
  const _ReferenceIllustration();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    height: 120,
    child: Stack(
      alignment: Alignment.center,
      children: [
        for (final (index, angle) in const [(0, -0.16), (1, 0.14), (2, 0.0)])
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 520 + 120 * index),
            curve: FormTokens.pop,
            builder: (context, value, child) => Transform.translate(
              offset: Offset((index - 1) * 46.0 * value, 0),
              child: Transform.rotate(angle: angle * value, child: child),
            ),
            child: Container(
              width: 72,
              height: 96,
              decoration: BoxDecoration(
                color: index == 2
                    ? FormTokens.selectedTint
                    : FormTokens.flatLayPaper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FormTokens.surface, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x261D281C),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                index == 2 ? Icons.person_outline : Icons.face_outlined,
                color: FormTokens.green,
                size: 30,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Confirms an AI image on a combination. A try-on first picks one of the
/// user's photos, or adds a new one.
class _LookImageSheet extends StatefulWidget {
  const _LookImageSheet({
    required this.look,
    required this.mode,
    required this.page,
  });

  final Look look;
  final String mode;

  /// The page the sheet was opened from. It outlives the sheet, so the
  /// result is reported there.
  final BuildContext page;

  @override
  State<_LookImageSheet> createState() => _LookImageSheetState();
}

class _LookImageSheetState extends State<_LookImageSheet> {
  final String _key = newIdempotencyKey();
  List<String>? _bases;
  String? _base;
  bool _uploading = false;
  ApiFailure? _failure;

  bool get _tryOn => widget.mode == 'try-on';

  @override
  void initState() {
    super.initState();
    if (_tryOn) unawaited(_loadBases());
  }

  Future<void> _loadBases() async {
    final bases = await context.read<LookRepository>().tryOnBases();
    if (!mounted) return;
    setState(() {
      _bases = bases;
      _base ??= bases.firstOrNull;
    });
  }

  Future<void> _addBase() async {
    final source = await pickPhotoSource(
      context,
      title: context.tr(LocaleKeys.composerTryOnAddPhoto),
    );
    if (source == null || !mounted) return;
    final paths = await pickPhotos(context, camera: source);
    if (paths.isEmpty || !mounted) return;
    final looks = context.read<LookRepository>();
    setState(() {
      _uploading = true;
      _failure = null;
    });
    try {
      final prepared = await PhotoPreparation().prepare(paths.first);
      final assetId = await looks.uploadTryOnPhoto(
        await compute(cropToLookFormat, prepared.bytes),
      );
      if (!mounted) return;
      setState(() {
        _bases = [assetId, ...?_bases];
        _base = assetId;
      });
    } on FormApiException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    } on FormatException {
      if (mounted) setState(() => _failure = ApiFailure.rejected);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _confirm() {
    final page = widget.page;
    final feed = page.read<FeedCubit>();
    final quality = page.read<QualityCubit>().state.feed;
    Navigator.pop(context);
    unawaited(HapticFeedback.mediumImpact());
    unawaited(
      runFeedAction(
        page,
        () => feed.createImage(
          widget.look.id,
          mode: widget.mode,
          idempotencyKey: _key,
          baseAssetId: _tryOn ? _base : null,
          quality: quality,
        ),
        success: page.tr(LocaleKeys.lookCreating),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<FeedCubit>().state.online;
    return FormSheet(
      title: context.tr(
        _tryOn ? LocaleKeys.lookTryOn : LocaleKeys.lookInspiration,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(
              _tryOn
                  ? LocaleKeys.lookTryOnBody
                  : LocaleKeys.lookInspirationBody,
            ),
            style: FormTokens.body,
          ),
          if (_tryOn) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                children: [
                  _BaseTile(
                    selected: false,
                    onTap: _uploading || !online
                        ? null
                        : () => unawaited(_addBase()),
                    child: ColoredBox(
                      color: FormTokens.uploadTint,
                      child: Center(
                        child: _uploading
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.add_a_photo_outlined,
                                color: FormTokens.green,
                              ),
                      ),
                    ),
                  ),
                  for (final assetId in _bases ?? const <String>[])
                    _BaseTile(
                      key: ValueKey(assetId),
                      selected: assetId == _base,
                      onTap: () {
                        unawaited(HapticFeedback.selectionClick());
                        setState(() => _base = assetId);
                      },
                      child: CachedMedia(
                        identity: assetId,
                        previewPath: 'v1/assets/$assetId/content',
                        online: online,
                        fit: BoxFit.cover,
                        entrance: MediaEntrance.fade,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_failure != null) ...[
            const SizedBox(height: 12),
            FormNotice(text: apiFailureText(context, _failure!), error: true),
          ],
          const SizedBox(height: 18),
          BlocBuilder<CreditsCubit, Credits?>(
            builder: (context, balance) {
              final metered = balance?.metered ?? false;
              final short = metered && balance!.balance < lookCreditCost;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  if (short)
                    Text(
                      context.tr(LocaleKeys.credits_empty),
                      style: FormTokens.body.copyWith(
                        color: FormTokens.danger,
                      ),
                    )
                  else if (metered)
                    Text(
                      context.tr(
                        LocaleKeys.lookCostBalance,
                        namedArgs: {
                          'left': '${balance!.balance - lookCreditCost}',
                        },
                      ),
                      style: FormTokens.small.copyWith(
                        color: FormTokens.noteInk,
                      ),
                    ),
                  FilledButton(
                    onPressed: short || !online || (_tryOn && _base == null)
                        ? null
                        : _confirm,
                    child: Text(
                      lookCostLabel(
                        context,
                        context.tr(
                          _tryOn
                              ? LocaleKeys.composerTryOnAction
                              : LocaleKeys.lookInspirationAction,
                        ),
                        balance,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BaseTile extends StatelessWidget {
  const _BaseTile({
    required this.selected,
    required this.onTap,
    required this.child,
    super.key,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: FormTokens.quick,
          width: 120,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? FormTokens.green : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                Positioned(
                  top: 6,
                  right: 6,
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 260),
                    curve: FormTokens.pop,
                    child: const CircleAvatar(
                      radius: 11,
                      backgroundColor: FormTokens.green,
                      child: Icon(Icons.check, size: 14, color: Colors.white),
                    ),
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
