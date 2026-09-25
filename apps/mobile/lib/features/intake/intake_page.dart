import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:app_settings/app_settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/intake/intake_bloc.dart';
import 'package:form_mobile/features/intake/intake_failure.dart';
import 'package:form_mobile/features/wardrobe/item_edit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/intake.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:image_picker/image_picker.dart';

typedef IntakeChoiceBoolCallback =
    void Function(
      IntakeChoice choice, {
      required bool value,
    });

class IntakePage extends StatefulWidget {
  const IntakePage({super.key});
  @override
  State<IntakePage> createState() => _IntakePageState();
}

class _IntakePageState extends State<IntakePage> {
  bool _picking = false;
  String? _pickerError;
  late IntakeBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<IntakeBloc>();
    _bloc.availability(visible: true);
  }

  @override
  void dispose() {
    _bloc.availability(visible: false);
    super.dispose();
  }

  Future<void> _pick({required bool camera}) async {
    setState(() {
      _picking = true;
      _pickerError = null;
    });
    try {
      final picker = ImagePicker();
      final List<XFile> files;
      if (camera) {
        final photo = await picker.pickImage(
          source: ImageSource.camera,
          requestFullMetadata: false,
        );
        files = photo == null ? [] : [photo];
      } else {
        files = await picker.pickMultiImage(requestFullMetadata: false);
      }
      if (files.isNotEmpty) {
        _bloc.add(
          IntakeEvent(
            IntakeAction.add,
            paths: files.map((f) => f.path).toList(),
          ),
        );
      }
    } on Object catch (error) {
      _pickerError = intakeFailureKey(
        error,
        fallback: LocaleKeys.intake_invalidPhoto,
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _discard(IntakeDraft draft) async {
    final confirmed = await confirmFormAction(
      context: context,
      title: context.tr(LocaleKeys.intake_discard),
      message: context.tr(LocaleKeys.intake_discardBody),
      confirmLabel: context.tr(LocaleKeys.intake_discard),
    );
    if (confirmed) {
      _bloc.discard(draft.id);
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<IntakeBloc, IntakeState>(
    builder: (context, state) {
      final online =
          context.watch<ConnectionCubit>().state == ConnectionStatus.ready;
      final enabled = online && !state.busy && !_picking;
      final hasDrafts = state.drafts.isNotEmpty;
      return Scaffold(
        backgroundColor: FormTokens.paper,
        extendBodyBehindAppBar: true,
        appBar: FormPageHeader(title: context.tr(LocaleKeys.intake_title)),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(
              FormTokens.gutter,
              MediaQuery.paddingOf(context).top,
              FormTokens.gutter,
              MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              const SizedBox(height: 8),
              Text(
                context.tr(LocaleKeys.intake_intro),
                style: FormTokens.body.copyWith(color: FormTokens.muted),
              ),
              const SizedBox(height: 16),
              _UploadArea(
                compact: hasDrafts,
                enabled: enabled,
                picking: _picking,
                busy: state.busy,
                onCamera: () => _pick(camera: true),
                onLibrary: () => _pick(camera: false),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: FormTokens.field,
                  borderRadius: BorderRadius.circular(FormTokens.inputRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Text(
                    context.tr(LocaleKeys.intake_cost),
                    style: FormTokens.small.copyWith(color: FormTokens.noteInk),
                  ),
                ),
              ),
              if (!online)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FormNotice(
                    text: context.tr(LocaleKeys.intake_offline),
                    error: true,
                  ),
                ),
              if (state.busy || _picking)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: state.progress > 0 ? state.progress : null,
                      backgroundColor: FormTokens.line,
                      color: FormTokens.green,
                    ),
                  ),
                ),
              if (_pickerError != null) ...[
                const SizedBox(height: 12),
                FormNotice(text: context.tr(_pickerError!), error: true),
                if (_pickerError == LocaleKeys.intake_permission)
                  TextButton(
                    onPressed: AppSettings.openAppSettings,
                    child: Text(context.tr(LocaleKeys.intake_openSettings)),
                  ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 12),
                FormNotice(text: context.tr(state.error!), error: true),
              ],
              for (final draft in state.drafts)
                _DraftCard(
                  draft: draft,
                  state: state,
                  enabled: enabled,
                  onDiscard: () => _discard(draft),
                  onSelect: enabled && draft.phase == DraftPhase.ready
                      ? (choice) => _bloc.add(
                          IntakeEvent(
                            IntakeAction.select,
                            id: draft.id,
                            choiceKey: choice.itemKey,
                            value: !choice.selected,
                          ),
                        )
                      : null,
                  onBatchOwning: enabled && draft.phase == DraftPhase.ready
                      ? (value) => _bloc.add(
                          IntakeEvent(
                            IntakeAction.ownership,
                            id: draft.id,
                            value: value,
                          ),
                        )
                      : null,
                  onChoiceOwning: enabled
                      ? (choice, {required value}) {
                          if (choice.locked) return;
                          _bloc.add(
                            IntakeEvent(
                              IntakeAction.ownership,
                              id: draft.id,
                              choiceKey: choice.itemKey,
                              value: value,
                            ),
                          );
                        }
                      : null,
                  onChoiceSelect: enabled
                      ? (choice, {required value}) {
                          if (choice.locked) return;
                          _bloc.add(
                            IntakeEvent(
                              IntakeAction.select,
                              id: draft.id,
                              choiceKey: choice.itemKey,
                              value: value,
                            ),
                          );
                        }
                      : null,
                  onRetry: enabled
                      ? () => _bloc.add(
                          IntakeEvent(IntakeAction.retry, id: draft.id),
                        )
                      : null,
                  onSave:
                      enabled &&
                          draft.phase == DraftPhase.ready &&
                          draft.choices.any((c) => c.selected && !c.enqueued)
                      ? () => _bloc.add(
                          IntakeEvent(IntakeAction.save, id: draft.id),
                        )
                      : null,
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    },
  );
}

class _UploadArea extends StatelessWidget {
  const _UploadArea({
    required this.compact,
    required this.enabled,
    required this.picking,
    required this.busy,
    required this.onCamera,
    required this.onLibrary,
  });

  final bool compact;
  final bool enabled;
  final bool picking;
  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final buttonsDisabled = busy || picking || !enabled;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FormTokens.uploadTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FormTokens.uploadLine),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: compact ? 16 : 35,
        ),
        child: Column(
          children: [
            if (!compact) ...[
              const Icon(
                Icons.camera_alt_outlined,
                size: 36,
                color: FormTokens.green,
              ),
              const SizedBox(height: 16),
            ],
            if (compact)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: buttonsDisabled ? null : onCamera,
                      icon: const Icon(Icons.camera_alt_outlined, size: 23),
                      label: Text(context.tr(LocaleKeys.intake_camera)),
                    ),
                  ),
                  const SizedBox(width: FormTokens.gap),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: buttonsDisabled ? null : onLibrary,
                      icon: const Icon(
                        Icons.photo_library_outlined,
                        size: 23,
                      ),
                      label: Text(context.tr(LocaleKeys.intake_library)),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  FilledButton.icon(
                    onPressed: buttonsDisabled ? null : onCamera,
                    icon: const Icon(Icons.camera_alt_outlined, size: 23),
                    label: Text(context.tr(LocaleKeys.intake_camera)),
                  ),
                  const SizedBox(height: FormTokens.gap),
                  OutlinedButton.icon(
                    onPressed: buttonsDisabled ? null : onLibrary,
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      size: 23,
                    ),
                    label: Text(context.tr(LocaleKeys.intake_library)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.state,
    required this.enabled,
    required this.onDiscard,
    required this.onSelect,
    required this.onBatchOwning,
    required this.onChoiceOwning,
    required this.onChoiceSelect,
    required this.onRetry,
    required this.onSave,
  });

  final IntakeDraft draft;
  final IntakeState state;
  final bool enabled;
  final VoidCallback onDiscard;
  final void Function(IntakeChoice)? onSelect;
  final ValueChanged<bool>? onBatchOwning;
  final IntakeChoiceBoolCallback? onChoiceOwning;
  final IntakeChoiceBoolCallback? onChoiceSelect;
  final VoidCallback? onRetry;
  final VoidCallback? onSave;

  bool get _busy =>
      draft.phase == DraftPhase.uploading ||
      draft.phase == DraftPhase.uploaded ||
      draft.phase == DraftPhase.detecting;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 17),
      child: FormPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DraftHead(
              title: _draftTitle(context),
              onDiscard: onDiscard,
            ),
            if (state.activeDraftId == draft.id && state.progress > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: state.progress,
                    backgroundColor: FormTokens.line,
                    color: FormTokens.green,
                  ),
                ),
              ),
            if (draft.phase == DraftPhase.manual) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: FormTokens.field,
                  child: DraftPhoto(draft: draft),
                ),
              ),
              const SizedBox(height: 12),
            ] else
              _DetectionStage(
                draft: draft,
                busy: _busy,
                analyzing: draft.phase != DraftPhase.uploading,
                onSelect: onSelect,
              ),
            if (draft.failure != null) ...[
              const SizedBox(height: 12),
              FormNotice(text: context.tr(draft.failure!), error: true),
              TextButton(
                onPressed: onRetry,
                child: Text(context.tr(LocaleKeys.retry)),
              ),
            ],
            if (draft.phase == DraftPhase.ready ||
                draft.phase == DraftPhase.saving) ...[
              if (!_busy) ...[
                _BatchOwnership(
                  value: draft.ownership == 'owning',
                  onChanged: onBatchOwning,
                ),
                const SizedBox(height: 13),
                _DetectionChoices(
                  draft: draft,
                  enabled: enabled,
                  onChoiceSelect: onChoiceSelect,
                  onChoiceOwning: onChoiceOwning,
                ),
              ],
              if (draft.phase == DraftPhase.ready)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton(
                    onPressed: onSave,
                    child: Text(context.tr(LocaleKeys.intake_save)),
                  ),
                ),
            ],
            if (draft.phase == DraftPhase.manual)
              ManualIntakeForm(
                key: ValueKey(draft.id),
                draft: draft,
                enabled: enabled,
              ),
          ],
        ),
      ),
    );
  }

  String _draftTitle(BuildContext context) =>
      context.tr('intake.phases.${draft.phase.name}');
}

class _DraftHead extends StatelessWidget {
  const _DraftHead({
    required this.title,
    required this.onDiscard,
  });

  final String title;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: FormTokens.heading.copyWith(fontSize: 22)),
              ],
            ),
          ),
          _DiscardButton(onPressed: onDiscard),
        ],
      ),
    );
  }
}

class _DiscardButton extends StatelessWidget {
  const _DiscardButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = context.tr(LocaleKeys.intake_discard);
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: FormTokens.field,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.close,
              size: 20,
              color: FormTokens.ink,
              semanticLabel: label,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectionStage extends StatelessWidget {
  const _DetectionStage({
    required this.draft,
    required this.busy,
    required this.analyzing,
    required this.onSelect,
  });

  final IntakeDraft draft;
  final bool busy;
  final bool analyzing;
  final void Function(IntakeChoice)? onSelect;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: FormTokens.field,
        child: Stack(
          alignment: Alignment.center,
          children: [
            DraftPhoto(draft: draft, onSelect: busy ? null : onSelect),
            if (busy)
              _ScanProgress(
                message: context.tr(
                  analyzing
                      ? LocaleKeys.intake_phases_detecting
                      : LocaleKeys.intake_phases_uploading,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScanProgress extends StatelessWidget {
  const _ScanProgress({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: ColoredBox(
            color: const Color(0x99263329),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x24FFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(9),
                      child: Icon(
                        Icons.search,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    style: FormTokens.body.copyWith(
                      fontSize: 13,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchOwnership extends StatelessWidget {
  const _BatchOwnership({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FormTokens.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(LocaleKeys.intake_batchOwning),
              style: FormTokens.small.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.04 * 12,
                color: FormTokens.muted,
              ),
            ),
            const SizedBox(height: 6),
            _FormStateToggle(
              label: context.tr(LocaleKeys.intake_batchOwning),
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _FormStateToggle extends StatelessWidget {
  const _FormStateToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      label: label,
      button: true,
      toggled: value,
      enabled: enabled,
      child: Material(
        color: FormTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FormTokens.inputRadius),
          side: const BorderSide(color: FormTokens.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: FormTokens.body.copyWith(fontSize: 13),
                  ),
                ),
                _ToggleControl(checked: value),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleControl extends StatelessWidget {
  const _ToggleControl({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : FormTokens.quick,
      curve: FormTokens.easeOut,
      width: 40,
      height: 24,
      decoration: BoxDecoration(
        color: checked ? FormTokens.green : const Color(0xFFB9BEB5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : FormTokens.quick,
        curve: FormTokens.easeOut,
        alignment: checked ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _DetectionChoices extends StatelessWidget {
  const _DetectionChoices({
    required this.draft,
    required this.enabled,
    required this.onChoiceSelect,
    required this.onChoiceOwning,
  });

  final IntakeDraft draft;
  final bool enabled;
  final IntakeChoiceBoolCallback? onChoiceSelect;
  final IntakeChoiceBoolCallback? onChoiceOwning;

  static const List<({String theme, List<String> categories})> _groups = [
    (theme: 'top', categories: ['top', 'jacket', 'dress']),
    (theme: 'bottom', categories: ['pants', 'skirt']),
    (theme: 'shoes', categories: ['shoes']),
    (theme: 'accessory', categories: <String>[]),
  ];

  static const _mainCategories = {
    'top',
    'jacket',
    'dress',
    'pants',
    'skirt',
    'shoes',
  };

  @override
  Widget build(BuildContext context) {
    final choices = draft.choices.where((c) => c.proposal != null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in _groups) ...[
          ..._groupSections(context, group.theme, group.categories, choices),
        ],
      ],
    );
  }

  List<Widget> _groupSections(
    BuildContext context,
    String theme,
    List<String> categories,
    List<IntakeChoice> choices,
  ) {
    final indexed = <({IntakeChoice choice, int index})>[];
    var index = 0;
    for (final choice in choices) {
      final category = choice.proposal!.category;
      final inGroup = categories.isEmpty
          ? !_mainCategories.contains(category)
          : categories.contains(category);
      if (inGroup) {
        indexed.add((choice: choice, index: index));
      }
      index++;
    }
    if (indexed.isEmpty) return [];
    final colors = FormTokens.category(theme);
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            Icon(_groupIcon(theme), size: 15, color: colors.ink),
            const SizedBox(width: 6),
            Text(
              _groupLabel(context, theme),
              style: FormTokens.small.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
          ],
        ),
      ),
      for (final entry in indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: _DetectionChoiceRow(
            draft: draft,
            choice: entry.choice,
            index: entry.index,
            enabled: enabled,
            onSelect: onChoiceSelect,
            onOwning: onChoiceOwning,
          ),
        ),
      const SizedBox(height: 9),
    ];
  }

  String _groupLabel(BuildContext context, String theme) => switch (theme) {
    'top' => context.tr('categories.top'),
    'bottom' => context.tr('categories.pants'),
    'shoes' => context.tr('categories.shoes'),
    _ => context.tr('categories.accessory'),
  };

  IconData _groupIcon(String theme) => switch (theme) {
    'top' => Icons.checkroom_outlined,
    'bottom' => Icons.straighten,
    'shoes' => Icons.directions_walk_outlined,
    _ => Icons.watch_outlined,
  };
}

class _DetectionChoiceRow extends StatelessWidget {
  const _DetectionChoiceRow({
    required this.draft,
    required this.choice,
    required this.index,
    required this.enabled,
    required this.onSelect,
    required this.onOwning,
  });

  final IntakeDraft draft;
  final IntakeChoice choice;
  final int index;
  final bool enabled;
  final IntakeChoiceBoolCallback? onSelect;
  final IntakeChoiceBoolCallback? onOwning;

  @override
  Widget build(BuildContext context) {
    final selected = choice.selected;
    final rowEnabled = enabled && !choice.locked && onSelect != null;
    final categoryLabel = context.tr('categories.${choice.proposal!.category}');
    final semanticsLabel = '$categoryLabel · ${choice.proposal!.name}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE7EDDF) : FormTokens.surface,
        borderRadius: BorderRadius.circular(FormTokens.inputRadius),
        border: Border.all(
          color: selected ? const Color(0xFF9EAF92) : FormTokens.line,
        ),
      ),
      child: Stack(
        children: [
          Semantics(
            label: semanticsLabel,
            button: true,
            selected: selected,
            enabled: rowEnabled,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(FormTokens.inputRadius),
                onTap: rowEnabled
                    ? () => onSelect!(choice, value: !choice.selected)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 38),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 58,
                        height: 74,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: ColoredBox(
                            color: const Color(0xFFE2E6DE),
                            child: DraftPhoto(
                              draft: draft,
                              crop: choice.proposal!.boundingBox,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              choice.proposal!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FormTokens.body.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$categoryLabel · '
                              '${choice.proposal!.colors.join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FormTokens.small.copyWith(fontSize: 11),
                            ),
                            if (choice.itemId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  context.tr(
                                    choice.enqueued
                                        ? LocaleKeys.intake_enqueued
                                        : LocaleKeys.intake_created,
                                  ),
                                  style: FormTokens.small,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _ChoiceNumber(selected: selected, index: index),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 80,
            bottom: 10,
            child: _OwnershipChip(
              owning: choice.ownership == 'owning',
              enabled: enabled && !choice.locked,
              onChanged: onOwning == null
                  ? null
                  : (value) => onOwning!(choice, value: value),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceNumber extends StatelessWidget {
  const _ChoiceNumber({required this.selected, required this.index});

  final bool selected;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 27,
      height: 27,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? FormTokens.green : Colors.transparent,
        border: Border.all(
          color: selected ? FormTokens.green : const Color(0xFFB9BEB5),
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : Text(
              '${index + 1}',
              style: FormTokens.small
                  .copyWith(
                    fontSize: 11,
                    color: FormTokens.muted,
                  )
                  .merge(FormTokens.numerals),
            ),
    );
  }
}

class _OwnershipChip extends StatelessWidget {
  const _OwnershipChip({
    required this.owning,
    required this.enabled,
    required this.onChanged,
  });

  final bool owning;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final chipEnabled = enabled && onChanged != null;
    final label = context.tr('collection.${owning ? 'owning' : 'wanting'}');
    return Semantics(
      label: label,
      button: true,
      toggled: owning,
      enabled: chipEnabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(FormTokens.chipRadius),
          onTap: chipEnabled ? () => onChanged!(!owning) : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: owning ? const Color(0xFFF9FBF5) : const Color(0xFFF4F5F1),
              borderRadius: BorderRadius.circular(FormTokens.chipRadius),
              border: Border.all(
                color: owning
                    ? const Color(0xFFB7C3AB)
                    : const Color(0xFFD7DCD1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    owning ? Icons.check : null,
                    size: 12,
                    color: owning ? const Color(0xFF536547) : FormTokens.muted,
                  ),
                  if (!owning)
                    Text(
                      '＋',
                      style: FormTokens.small.copyWith(fontSize: 11),
                    ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: FormTokens.small.copyWith(
                      fontSize: 11,
                      color: owning
                          ? const Color(0xFF536547)
                          : FormTokens.muted,
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
}

String _detectionTheme(String category) {
  if (['top', 'jacket', 'dress'].contains(category)) return 'top';
  if (['pants', 'skirt'].contains(category)) return 'bottom';
  if (category == 'shoes') return 'shoes';
  return 'accessory';
}

IconData _categoryIcon(String theme) => switch (theme) {
  'top' => Icons.checkroom_outlined,
  'bottom' => Icons.straighten,
  'shoes' => Icons.directions_walk_outlined,
  _ => Icons.watch_outlined,
};

/// Both preview crops and overlays use the prepared photo's pixel geometry.
class DraftPhoto extends StatelessWidget {
  const DraftPhoto({required this.draft, this.crop, this.onSelect, super.key});
  final IntakeDraft draft;
  final DetectionBox? crop;
  final void Function(IntakeChoice)? onSelect;
  @override
  Widget build(BuildContext context) {
    final source = Size(draft.width.toDouble(), draft.height.toDouble());
    final region = crop?.pixels(source) ?? Offset.zero & source;
    return Center(
      child: AspectRatio(
        aspectRatio: region.width / region.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / region.width;
            return ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    left: -region.left * scale,
                    top: -region.top * scale,
                    width: source.width * scale,
                    height: source.height * scale,
                    child: Image.file(
                      File(draft.filePath),
                      fit: BoxFit.fill,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                  if (crop == null)
                    for (final choice in draft.choices.where(
                      (c) => c.proposal != null && !c.enqueued,
                    ))
                      _DetectionBoxOverlay(
                        choice: choice,
                        scale: scale,
                        source: source,
                        onSelect: onSelect,
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DetectionBoxOverlay extends StatelessWidget {
  const _DetectionBoxOverlay({
    required this.choice,
    required this.scale,
    required this.source,
    required this.onSelect,
  });

  final IntakeChoice choice;
  final double scale;
  final Size source;
  final void Function(IntakeChoice)? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = _detectionTheme(choice.proposal!.category);
    final colors = FormTokens.category(theme);
    final selected = choice.selected;
    final rect = choice.proposal!.boundingBox.pixels(
      Size(source.width * scale, source.height * scale),
    );
    final enabled = onSelect != null && !choice.locked;
    final label =
        '${context.tr('categories.${choice.proposal!.category}')} · '
        '${choice.proposal!.name}';
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        label: label,
        button: true,
        selected: selected,
        enabled: enabled,
        onTap: enabled ? () => onSelect!(choice) : null,
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (enabled) onSelect!(choice);
                return null;
              },
            ),
          },
          child: Focus(
            child: GestureDetector(
              onTap: enabled ? () => onSelect!(choice) : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? colors.ink : const Color(0xCCFFFFFF),
                    width: selected ? 3 : 2,
                  ),
                  color: selected ? colors.ink.withValues(alpha: 0.26) : null,
                  boxShadow: const [
                    BoxShadow(color: Color(0x66263329)),
                  ],
                ),
                child: Center(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: FormTokens.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x30000000), blurRadius: 10),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        _categoryIcon(theme),
                        size: 14,
                        color: colors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ManualIntakeForm extends StatefulWidget {
  const ManualIntakeForm({
    required this.draft,
    required this.enabled,
    super.key,
  });
  final IntakeDraft draft;
  final bool enabled;
  @override
  State<ManualIntakeForm> createState() => _ManualIntakeFormState();
}

class _ManualIntakeFormState extends State<ManualIntakeForm> {
  final _form = GlobalKey<FormState>();
  String _name = '';
  String _colors = '';
  String _notes = '';
  String _category = 'top';
  String _ownership = 'owning';
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(context.tr(LocaleKeys.intake_manual)),
        TextFormField(
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: context.tr(LocaleKeys.itemName),
          ),
          onChanged: (v) => _name = v,
          validator: (v) => ItemMetadata.validName(v!.trim())
              ? null
              : context.tr(LocaleKeys.intake_validation),
        ),
        DropdownButtonFormField<String>(
          initialValue: _category,
          items: [
            for (final c in supportedCategories)
              DropdownMenuItem(
                value: c,
                child: Text(context.tr('categories.$c')),
              ),
          ],
          onChanged: widget.enabled
              ? (v) => setState(() => _category = v!)
              : null,
        ),
        TextFormField(
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: context.tr(LocaleKeys.itemColors),
          ),
          onChanged: (v) => _colors = v,
          validator: (v) => ItemEdit.validColors(v!)
              ? null
              : context.tr(LocaleKeys.intake_validation),
        ),
        TextFormField(
          enabled: widget.enabled,
          decoration: InputDecoration(labelText: context.tr(LocaleKeys.notes)),
          onChanged: (v) => _notes = v,
          validator: (v) => v!.trim().length <= 2000
              ? null
              : context.tr(LocaleKeys.intake_validation),
        ),
        _FormStateToggle(
          label: context.tr('collection.$_ownership'),
          value: _ownership == 'owning',
          onChanged: widget.enabled
              ? (v) => setState(() => _ownership = v ? 'owning' : 'wanting')
              : null,
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: widget.enabled
              ? () {
                  if (!_form.currentState!.validate()) return;
                  context.read<IntakeBloc>().add(
                    IntakeEvent(
                      IntakeAction.manual,
                      id: widget.draft.id,
                      edit: ItemEdit(
                        name: _name,
                        category: _category,
                        colors: _colors,
                        notes: _notes,
                        state: _ownership,
                      ),
                    ),
                  );
                }
              : null,
          child: Text(context.tr(LocaleKeys.intake_save)),
        ),
      ],
    ),
  );
}
