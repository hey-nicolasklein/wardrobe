import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/features/intake/intake_bloc.dart';
import 'package:form_mobile/features/intake/intake_failure.dart';
import 'package:form_mobile/features/wardrobe/item_edit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/intake.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(context.tr(LocaleKeys.intake_discard)),
        content: Text(context.tr(LocaleKeys.intake_discardBody)),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: Text(context.tr(LocaleKeys.cancel)),
          ),
          TextButton(
            onPressed: () => context.pop(true),
            child: Text(context.tr(LocaleKeys.intake_discard)),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      _bloc.discard(draft.id);
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<IntakeBloc, IntakeState>(
    builder: (context, state) {
      final online =
          context.watch<ConnectionCubit>().state == ConnectionStatus.ready;
      final enabled = online && !state.busy && !_picking;
      return Scaffold(
        appBar: AppBar(title: Text(context.tr(LocaleKeys.intake_title))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(context.tr(LocaleKeys.intake_intro)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.busy || _picking
                  ? null
                  : () => _pick(camera: true),
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(context.tr(LocaleKeys.intake_camera)),
            ),
            OutlinedButton.icon(
              onPressed: state.busy || _picking
                  ? null
                  : () => _pick(camera: false),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(context.tr(LocaleKeys.intake_library)),
            ),
            Text(context.tr(LocaleKeys.intake_cost)),
            if (!online) Text(context.tr(LocaleKeys.intake_offline)),
            if (state.busy || _picking)
              LinearProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
              ),
            if (_pickerError != null) ...[
              Text(context.tr(_pickerError!)),
              if (_pickerError == LocaleKeys.intake_permission)
                TextButton(
                  onPressed: AppSettings.openAppSettings,
                  child: Text(context.tr(LocaleKeys.intake_openSettings)),
                ),
            ],
            if (state.error != null) Text(context.tr(state.error!)),
            for (final draft in state.drafts)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('intake.phases.${draft.phase.name}'),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _discard(draft),
                            icon: const Icon(Icons.close),
                            tooltip: context.tr(LocaleKeys.intake_discard),
                          ),
                        ],
                      ),
                      if (state.activeDraftId == draft.id)
                        LinearProgressIndicator(value: state.progress),
                      DraftPhoto(
                        draft: draft,
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
                      ),
                      if (draft.failure != null) ...[
                        Text(context.tr(draft.failure!)),
                        TextButton(
                          onPressed: enabled
                              ? () => _bloc.add(
                                  IntakeEvent(IntakeAction.retry, id: draft.id),
                                )
                              : null,
                          child: Text(context.tr(LocaleKeys.retry)),
                        ),
                      ],
                      if (draft.phase == DraftPhase.ready ||
                          draft.phase == DraftPhase.saving) ...[
                        SwitchListTile(
                          title: Text(
                            context.tr(LocaleKeys.intake_batchOwning),
                          ),
                          value: draft.ownership == 'owning',
                          onChanged: enabled && draft.phase == DraftPhase.ready
                              ? (value) => _bloc.add(
                                  IntakeEvent(
                                    IntakeAction.ownership,
                                    id: draft.id,
                                    value: value,
                                  ),
                                )
                              : null,
                        ),
                        for (final choice in draft.choices.where(
                          (c) => c.proposal != null,
                        ))
                          Row(
                            children: [
                              SizedBox(
                                width: 64,
                                height: 80,
                                child: DraftPhoto(
                                  draft: draft,
                                  crop: choice.proposal!.boundingBox,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    CheckboxListTile(
                                      title: Text(choice.proposal!.name),
                                      subtitle: Text(
                                        context.tr(
                                          'categories.'
                                          '${choice.proposal!.category}',
                                        ),
                                      ),
                                      value: choice.selected,
                                      onChanged: enabled && !choice.locked
                                          ? (value) => _bloc.add(
                                              IntakeEvent(
                                                IntakeAction.select,
                                                id: draft.id,
                                                choiceKey: choice.itemKey,
                                                value: value,
                                              ),
                                            )
                                          : null,
                                    ),
                                    SwitchListTile(
                                      title: Text(
                                        context.tr(
                                          'collection.${choice.ownership}',
                                        ),
                                      ),
                                      value: choice.ownership == 'owning',
                                      onChanged: enabled && !choice.locked
                                          ? (value) => _bloc.add(
                                              IntakeEvent(
                                                IntakeAction.ownership,
                                                id: draft.id,
                                                choiceKey: choice.itemKey,
                                                value: value,
                                              ),
                                            )
                                          : null,
                                    ),
                                    if (choice.itemId != null)
                                      Text(
                                        context.tr(
                                          choice.enqueued
                                              ? LocaleKeys.intake_enqueued
                                              : LocaleKeys.intake_created,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        if (draft.phase == DraftPhase.ready)
                          FilledButton(
                            onPressed:
                                enabled &&
                                    draft.choices.any(
                                      (c) => c.selected && !c.enqueued,
                                    )
                                ? () => _bloc.add(
                                    IntakeEvent(
                                      IntakeAction.save,
                                      id: draft.id,
                                    ),
                                  )
                                : null,
                            child: Text(context.tr(LocaleKeys.intake_save)),
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
              ),
          ],
        ),
      );
    },
  );
}

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
                      Positioned.fromRect(
                        rect: choice.proposal!.boundingBox.pixels(
                          Size(source.width * scale, source.height * scale),
                        ),
                        child: GestureDetector(
                          onTap: onSelect == null || choice.locked
                              ? null
                              : () => onSelect!(choice),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: choice.selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
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
      children: [
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
        SwitchListTile(
          title: Text(context.tr('collection.$_ownership')),
          value: _ownership == 'owning',
          onChanged: widget.enabled
              ? (v) => setState(() => _ownership = v ? 'owning' : 'wanting')
              : null,
        ),
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
