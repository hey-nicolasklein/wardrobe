import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/settings/character/character_cubit.dart';
import 'package:form_mobile/features/settings/character/character_setup_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/character_draft_repository.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class CharacterSetupPage extends StatelessWidget {
  const CharacterSetupPage({this.fromFeed = false, super.key});
  final bool fromFeed;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final cubit = CharacterSetupCubit(
        context.read<CharacterDraftRepository>(),
        online: context.read<CharacterCubit>().state.online,
      );
      unawaited(cubit.restore());
      return cubit;
    },
    child: BlocListener<CharacterCubit, CharacterState>(
      listenWhen: (previous, next) => previous.online != next.online,
      listener: (context, state) =>
          context.read<CharacterSetupCubit>().setOnline(online: state.online),
      child: BlocConsumer<CharacterSetupCubit, CharacterSetupState>(
        listenWhen: (previous, next) =>
            previous.step != next.step && next.step == CharacterStep.finished,
        listener: (context, state) async {
          await context.read<FeedCubit>().refresh();
          if (!context.mounted) return;
          showFormToast(context, context.tr(LocaleKeys.character_saved));
          if (fromFeed) {
            context.go('/feed');
          } else {
            context.pop();
          }
        },
        builder: (context, state) {
          final cubit = context.read<CharacterSetupCubit>();
          return FormSheet(
            title: context.tr(switch (state.step) {
              CharacterStep.select => LocaleKeys.character_collage,
              CharacterStep.crop => LocaleKeys.character_crop,
              CharacterStep.review ||
              CharacterStep.finished => LocaleKeys.character_review,
            }),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                if (!state.online)
                  FormNotice(text: context.tr(LocaleKeys.character_offline)),
                if (state.error != null)
                  FormNotice(text: context.tr(state.error!), error: true),
                if (state.busy && state.progress == null)
                  const LinearProgressIndicator(),
                if (state.step == CharacterStep.select) ...[
                  Text(
                    context.tr(LocaleKeys.character_introTitle),
                    style: FormTokens.heading,
                  ),
                  Text(
                    context.tr(LocaleKeys.character_introBody),
                    style: FormTokens.body,
                  ),
                  OutlinedButton.icon(
                    onPressed: state.editable ? cubit.choose : null,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(context.tr(LocaleKeys.intake_library)),
                  ),
                  if (state.draft != null)
                    FilledButton(
                      onPressed: state.editable ? () => cubit.crop(0) : null,
                      child: Text(
                        context.tr(LocaleKeys.character_continueCrop),
                      ),
                    ),
                ],
                if (state.step == CharacterStep.crop) ...[
                  Text(
                    context.tr(
                      LocaleKeys.character_photoIndex,
                      namedArgs: {
                        'index': '${state.index + 1}',
                        'count': '${state.draft!.photos.length}',
                      },
                    ),
                    style: FormTokens.eyebrow,
                  ),
                  Text(
                    context.tr(LocaleKeys.character_cropTitle),
                    style: FormTokens.heading,
                  ),
                  Text(
                    context.tr(LocaleKeys.character_cropBody),
                    style: FormTokens.body,
                  ),
                  _Crop(state: state),
                  if (state.lowResolution)
                    FormNotice(
                      text: context.tr(LocaleKeys.character_resolution),
                    ),
                  Text(context.tr(LocaleKeys.character_zoom)),
                  Slider(
                    value: state.photo.crop.zoom,
                    min: 1,
                    max: 6,
                    onChanged: state.editable ? cubit.zoom : null,
                    semanticFormatterCallback: (value) => context.tr(
                      LocaleKeys.character_zoomValue,
                      namedArgs: {'zoom': value.toStringAsFixed(1)},
                    ),
                  ),
                  Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: state.editable ? cubit.back : null,
                          child: Text(context.tr(LocaleKeys.character_back)),
                        ),
                      ),
                      Expanded(
                        child: FilledButton(
                          onPressed: state.editable ? cubit.next : null,
                          child: Text(
                            context.tr(
                              state.isLastPhoto
                                  ? LocaleKeys.character_review
                                  : LocaleKeys.character_nextPhoto,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (state.step == CharacterStep.review) ...[
                  Text(
                    context.tr(LocaleKeys.character_reviewTitle),
                    style: FormTokens.heading,
                  ),
                  Text(
                    context.tr(LocaleKeys.character_reviewBody),
                    style: FormTokens.body,
                  ),
                  FormReferenceImage(
                    preview: true,
                    child: Image.file(
                      File(state.draft!.previewPath!),
                      key: ValueKey(state.draft!.previewPath),
                      fit: BoxFit.contain,
                      semanticLabel: context.tr(LocaleKeys.character_preview),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < state.draft!.photos.length; i++)
                        OutlinedButton(
                          onPressed: state.editable
                              ? () => cubit.crop(i)
                              : null,
                          child: Text(
                            context.tr(
                              LocaleKeys.character_recrop,
                              namedArgs: {'index': '${i + 1}'},
                            ),
                          ),
                        ),
                    ],
                  ),
                  TextFormField(
                    initialValue: state.draft!.note,
                    enabled: state.editable,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: context.tr(LocaleKeys.character_note),
                      hintText: context.tr(LocaleKeys.character_noteHint),
                    ),
                    onChanged: cubit.note,
                  ),
                  if (state.draft!.locked && !state.busy)
                    FormNotice(
                      text: context.tr(LocaleKeys.character_retryLocked),
                    ),
                  if (state.progress != null) ...[
                    Text(
                      context.tr(
                        state.progress! < 1
                            ? LocaleKeys.character_uploading
                            : LocaleKeys.character_preparing,
                      ),
                    ),
                    LinearProgressIndicator(value: state.progress),
                  ],
                  FilledButton(
                    onPressed: state.canSubmit ? cubit.submit : null,
                    child: Text(
                      context.tr(
                        state.draft!.locked
                            ? LocaleKeys.retryCommand
                            : LocaleKeys.character_useCollage,
                      ),
                    ),
                  ),
                ],
                if (state.draft != null)
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () async {
                            final confirmed = await confirmFormAction(
                              context: context,
                              title: context.tr(LocaleKeys.character_discard),
                              message: context.tr(
                                LocaleKeys.character_discardBody,
                              ),
                              confirmLabel: context.tr(
                                LocaleKeys.character_discard,
                              ),
                            );
                            if (confirmed) await cubit.discard();
                          },
                    child: Text(context.tr(LocaleKeys.character_discard)),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _Crop extends StatelessWidget {
  const _Crop({required this.state});
  final CharacterSetupState state;
  @override
  Widget build(BuildContext context) {
    final photo = state.photo;
    final bounds = state.bounds;
    return FormReferenceImage(
      preview: true,
      aspectRatio: state.tile.width / state.tile.height,
      child: FormCropViewport(
        image: Image.file(File(photo.path), fit: BoxFit.fill),
        sourceSize: Size(photo.width.toDouble(), photo.height.toDouble()),
        bounds: Rect.fromLTWH(bounds.x, bounds.y, bounds.width, bounds.height),
        label: context.tr(LocaleKeys.character_crop),
        onPan: state.editable ? context.read<CharacterSetupCubit>().pan : null,
      ),
    );
  }
}
