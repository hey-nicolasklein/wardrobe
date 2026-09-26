import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_settings/app_settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/intake/intake_bloc.dart';
import 'package:form_mobile/features/intake/intake_failure.dart';
import 'package:form_mobile/features/onboarding/scan_stage.dart';
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
      // On top while the page is empty, below the drafts once analysis is
      // running so the photo being scanned stays front and centre.
      final addPhotos = <Widget>[
        if (!hasDrafts) ...[
          const SizedBox(height: 8),
          Text(
            context.tr(LocaleKeys.intake_intro),
            style: FormTokens.body.copyWith(color: FormTokens.muted),
          ),
          const SizedBox(height: 16),
        ],
        _UploadArea(
          compact: hasDrafts,
          // Not tied to the bloc's busy flag: detection polling toggles it
          // every few seconds, and a new photo simply queues behind it.
          enabled: online,
          picking: _picking,
          onCamera: () => _pick(camera: true),
          onLibrary: () => _pick(camera: false),
        ),
        if (hasDrafts)
          Text(
            context.tr(LocaleKeys.intake_cost),
            textAlign: TextAlign.center,
            style: FormTokens.small.copyWith(fontSize: 11),
          )
        else
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
                style: FormTokens.small.copyWith(
                  color: FormTokens.noteInk,
                ),
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
      ];
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
              if (!hasDrafts) ...addPhotos,
              if (!online)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FormNotice(
                    text: context.tr(LocaleKeys.intake_offline),
                    error: true,
                  ),
                ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                FormNotice(text: context.tr(state.error!), error: true),
              ],
              for (final draft in state.drafts)
                FormReveal(
                  key: ValueKey(draft.id),
                  child: _DraftCard(
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
                ),
              if (hasDrafts) ...[
                const SizedBox(height: 24),
                ...addPhotos,
              ],
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
    required this.onCamera,
    required this.onLibrary,
  });

  final bool compact;
  final bool enabled;
  final bool picking;
  final VoidCallback onCamera;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final buttonsDisabled = picking || !enabled;
    final camera = FilledButton.icon(
      onPressed: buttonsDisabled ? null : onCamera,
      icon: Icon(Icons.camera_alt_outlined, size: compact ? 20 : 23),
      label: Text(
        context.tr(
          compact ? LocaleKeys.intake_cameraShort : LocaleKeys.intake_camera,
        ),
      ),
    );
    final library = OutlinedButton.icon(
      onPressed: buttonsDisabled ? null : onLibrary,
      icon: Icon(Icons.photo_library_outlined, size: compact ? 20 : 23),
      label: Text(
        context.tr(
          compact ? LocaleKeys.intake_libraryShort : LocaleKeys.intake_library,
        ),
      ),
    );
    // Below the drafts it is a secondary action: a quiet heading and one row
    // of buttons instead of the dashed upload card.
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              context.tr(LocaleKeys.intake_more).toUpperCase(),
              style: FormTokens.eyebrow,
            ),
            Row(
              spacing: FormTokens.gap,
              children: [
                Expanded(child: camera),
                Expanded(child: library),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CustomPaint(
        foregroundPainter: const FormDashedBorder(
          color: FormTokens.uploadLine,
          radius: 20,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: FormTokens.uploadTint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 170, child: LoopingScanStage()),
                const SizedBox(height: 18),
                Text(
                  context.tr(LocaleKeys.intake_uploadTitle),
                  textAlign: TextAlign.center,
                  style: FormTokens.heading.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 6),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 270),
                    child: Text(
                      context.tr(LocaleKeys.intake_uploadBody),
                      textAlign: TextAlign.center,
                      style: FormTokens.body.copyWith(
                        color: FormTokens.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                camera,
                const SizedBox(height: FormTokens.gap),
                library,
              ],
            ),
          ),
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
                AnimatedSwitcher(
                  duration: FormTokens.sheetDuration,
                  switchInCurve: FormTokens.easeOut,
                  // Only the new title takes part, so the old one doesn't
                  // overlap it while fading.
                  layoutBuilder: (current, _) => current ?? const SizedBox(),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    title,
                    key: ValueKey(title),
                    style: FormTokens.heading.copyWith(fontSize: 22),
                  ),
                ),
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
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: FormTokens.sheetDuration,
                child: busy
                    ? _ScanOverlay(
                        message: context.tr(
                          analyzing
                              ? LocaleKeys.intake_phases_detecting
                              : LocaleKeys.intake_phases_uploading,
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A band sweeping over the photo while it uploads and is analysed, with
/// the current step in a pill below.
class _ScanOverlay extends StatefulWidget {
  const _ScanOverlay({required this.message});

  final String message;

  @override
  State<_ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<_ScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      unawaited(_sweep.repeat());
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0x40263329),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final band = height * 0.35;
        return Stack(
          children: [
            AnimatedBuilder(
              animation: _sweep,
              builder: (context, _) {
                final t = FormTokens.easeOut.transform(_sweep.value);
                return Positioned(
                  left: 0,
                  right: 0,
                  top: -band + (height + band) * t,
                  height: band,
                  child: Opacity(
                    // Fades in at the top and out at the bottom so the loop
                    // restarts without a visible jump.
                    opacity: math.sin(math.pi * _sweep.value),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00FFFFFF), Color(0x70FFFFFF)],
                        ),
                        border: Border(
                          bottom: BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xD9263329),
                    borderRadius: BorderRadius.circular(FormTokens.chipRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        AnimatedBuilder(
                          animation: _sweep,
                          builder: (context, _) => Opacity(
                            opacity:
                                0.45 +
                                0.55 * math.sin(math.pi * _sweep.value).abs(),
                            child: const SizedBox.square(
                              dimension: 7,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: FormTokens.quick,
                          layoutBuilder: (current, _) =>
                              current ?? const SizedBox(),
                          child: Text(
                            widget.message,
                            key: ValueKey(widget.message),
                            style: FormTokens.body.copyWith(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
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
          key: ValueKey(entry.choice.itemKey),
          padding: const EdgeInsets.only(bottom: 7),
          child: FormReveal(
            delay: Duration(milliseconds: 250 + 70 * entry.index),
            child: _DetectionChoiceRow(
              draft: draft,
              choice: entry.choice,
              index: entry.index,
              enabled: enabled,
              onSelect: onChoiceSelect,
              onOwning: onChoiceOwning,
            ),
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

  static const double _rowRadius = FormTokens.panelRadius;
  static const _rowPadding = 10.0;

  @override
  Widget build(BuildContext context) {
    final selected = choice.selected;
    final rowEnabled = enabled && !choice.locked && onSelect != null;
    final categoryLabel = context.tr('categories.${choice.proposal!.category}');
    final semanticsLabel = '$categoryLabel · ${choice.proposal!.name}';
    return AnimatedContainer(
      duration: FormTokens.quick,
      curve: FormTokens.easeOut,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE7EDDF) : FormTokens.surface,
        borderRadius: BorderRadius.circular(_rowRadius),
        border: Border.all(
          color: selected ? const Color(0xFF9EAF92) : FormTokens.line,
        ),
      ),
      child: Semantics(
        label: semanticsLabel,
        button: true,
        selected: selected,
        enabled: rowEnabled,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(_rowRadius),
            onTap: rowEnabled
                ? () => onSelect!(choice, value: !choice.selected)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(_rowPadding),
              // The text column sets the row height. The photo is stretched to
              // it (DraftPhoto uses a LayoutBuilder, so no IntrinsicHeight),
              // the chip sits at the bottom and the checkbox stays centred.
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 58,
                    child: ClipRRect(
                      // Concentric with the row's corners.
                      borderRadius: BorderRadius.circular(
                        _rowRadius - _rowPadding,
                      ),
                      child: ColoredBox(
                        color: const Color(0xFFE2E6DE),
                        child: DraftPhoto(
                          draft: draft,
                          crop: choice.proposal!.boundingBox,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 70),
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
                            const SizedBox(height: 2),
                            Text(
                              '$categoryLabel · '
                              '${choice.proposal!.colors.join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FormTokens.small.copyWith(fontSize: 11),
                            ),
                            if (choice.itemId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  context.tr(
                                    choice.enqueued
                                        ? LocaleKeys.intake_enqueued
                                        : LocaleKeys.intake_created,
                                  ),
                                  style: FormTokens.small,
                                ),
                              ),
                            const SizedBox(height: 12),
                            _OwnershipChip(
                              owning: choice.ownership == 'owning',
                              enabled: enabled && !choice.locked,
                              onChanged: onOwning == null
                                  ? null
                                  : (value) => onOwning!(choice, value: value),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ChoiceNumber(selected: selected, index: index),
                    ],
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

class _ChoiceNumber extends StatelessWidget {
  const _ChoiceNumber({required this.selected, required this.index});

  final bool selected;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: FormTokens.quick,
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: FormTokens.pop,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: selected
            ? const Icon(
                Icons.check,
                key: ValueKey(true),
                size: 15,
                color: Colors.white,
              )
            : Text(
                '${index + 1}',
                key: const ValueKey(false),
                style: FormTokens.small
                    .copyWith(
                      fontSize: 11,
                      color: FormTokens.muted,
                    )
                    .merge(FormTokens.numerals),
              ),
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
/// The whole draft photo with tappable detection boxes, or with [crop] a
/// single detection that covers its box so the parent's rounded clip shapes
/// every corner.
class DraftPhoto extends StatelessWidget {
  const DraftPhoto({required this.draft, this.crop, this.onSelect, super.key});
  final IntakeDraft draft;
  final DetectionBox? crop;
  final void Function(IntakeChoice)? onSelect;
  @override
  Widget build(BuildContext context) {
    final source = Size(draft.width.toDouble(), draft.height.toDouble());
    final image = Image.file(
      File(draft.filePath),
      fit: BoxFit.fill,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    );
    if (crop != null) {
      final region = crop!.pixels(source);
      return LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          final scale = math.max(
            box.width / region.width,
            box.height / region.height,
          );
          return ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left:
                      (box.width - region.width * scale) / 2 -
                      region.left * scale,
                  top:
                      (box.height - region.height * scale) / 2 -
                      region.top * scale,
                  width: source.width * scale,
                  height: source.height * scale,
                  child: image,
                ),
              ],
            ),
          );
        },
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: source.width / source.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / source.width;
            return ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(child: image),
                  for (final (index, choice)
                      in draft.choices.where((c) => c.proposal != null).indexed)
                    _DetectionBoxOverlay(
                      key: ValueKey(choice.proposal!.id),
                      index: index,
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

/// A detected piece framed on the photo. Boxes pop in one after another
/// with a haptic tick. Once saved, a box flashes green with a check and
/// shrinks away, as if the piece were lifted into the wardrobe.
class _DetectionBoxOverlay extends StatefulWidget {
  const _DetectionBoxOverlay({
    required this.index,
    required this.choice,
    required this.scale,
    required this.source,
    required this.onSelect,
    super.key,
  });

  final int index;
  final IntakeChoice choice;
  final double scale;
  final Size source;
  final void Function(IntakeChoice)? onSelect;

  @override
  State<_DetectionBoxOverlay> createState() => _DetectionBoxOverlayState();
}

class _DetectionBoxOverlayState extends State<_DetectionBoxOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _lift;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _lift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      // A piece saved before this box was built is already gone.
      value: widget.choice.enqueued ? 1 : 0,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _enter.value = 1;
        return;
      }
      _timer = Timer(
        Duration(milliseconds: 220 + 120 * widget.index),
        () {
          unawaited(HapticFeedback.lightImpact());
          unawaited(_enter.forward());
        },
      );
    });
  }

  @override
  void didUpdateWidget(_DetectionBoxOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.choice.enqueued && !oldWidget.choice.enqueued) {
      unawaited(HapticFeedback.mediumImpact());
      if (MediaQuery.disableAnimationsOf(context)) {
        _lift.value = 1;
      } else {
        unawaited(_lift.forward());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choice = widget.choice;
    final onSelect = widget.onSelect;
    final theme = _detectionTheme(choice.proposal!.category);
    final colors = FormTokens.category(theme);
    final selected = choice.selected;
    final rect = choice.proposal!.boundingBox.pixels(
      Size(
        widget.source.width * widget.scale,
        widget.source.height * widget.scale,
      ),
    );
    final enabled = onSelect != null && !choice.locked && !choice.enqueued;
    final label =
        '${context.tr('categories.${choice.proposal!.category}')} · '
        '${choice.proposal!.name}';
    final saved = choice.enqueued;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        ignoring: saved,
        child: AnimatedBuilder(
          animation: Listenable.merge([_enter, _lift]),
          builder: (context, child) {
            final enter = FormTokens.pop.transform(_enter.value);
            // The flash holds for the first half, then the box lifts away.
            final lift = Curves.easeIn.transform(
              ((_lift.value - 0.45) / 0.55).clamp(0, 1),
            );
            return Opacity(
              opacity: (_enter.value * (1 - lift)).clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, -18 * lift),
                child: Transform.scale(
                  scale: (1.3 - 0.3 * enter) * (1 - 0.25 * lift),
                  child: child,
                ),
              ),
            );
          },
          child: Semantics(
            label: label,
            button: true,
            selected: selected,
            enabled: enabled,
            onTap: enabled ? () => onSelect(choice) : null,
            child: Actions(
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    if (enabled) onSelect(choice);
                    return null;
                  },
                ),
              },
              child: Focus(
                child: GestureDetector(
                  onTap: enabled
                      ? () {
                          unawaited(HapticFeedback.selectionClick());
                          onSelect(choice);
                        }
                      : null,
                  child: AnimatedContainer(
                    duration: FormTokens.quick,
                    curve: FormTokens.easeOut,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: saved
                            ? FormTokens.green
                            : selected
                            ? colors.ink
                            : const Color(0xCCFFFFFF),
                        width: selected || saved ? 3 : 2,
                      ),
                      color: saved
                          ? FormTokens.green.withValues(alpha: 0.4)
                          : selected
                          ? colors.ink.withValues(alpha: 0.26)
                          : const Color(0x00000000),
                      boxShadow: const [
                        BoxShadow(color: Color(0x66263329)),
                      ],
                    ),
                    child: Center(
                      child: AnimatedScale(
                        scale: selected || saved ? 1.12 : 1,
                        duration: const Duration(milliseconds: 260),
                        curve: FormTokens.pop,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: saved
                                ? FormTokens.green
                                : FormTokens.surface,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x30000000),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              saved ? Icons.check : _categoryIcon(theme),
                              size: 14,
                              color: saved ? Colors.white : colors.ink,
                            ),
                          ),
                        ),
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
