import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/look_collections_cubit.dart';
import 'package:form_mobile/features/feed/look_stacks.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/look_collection_repository.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/widgets/form_components.dart';

const _emojis = [
  '🌴', '💼', '🥂', '💍', '🎉', '☕', '🏔️', '🌙', //
  '❤️', '✨', '🎸', '🏖️', '🍂', '❄️', '🌸', '🧳',
];

/// Ideas for a first Sammlung. Tapping one fills name and emoji.
const List<(String, String)> _suggestions = [
  ('🌴', LocaleKeys.collectionIdeaHoliday),
  ('💼', LocaleKeys.collectionIdeaWork),
  ('🥂', LocaleKeys.collectionIdeaDate),
  ('💍', LocaleKeys.collectionIdeaWedding),
  ('☕', LocaleKeys.collectionIdeaWeekend),
];

/// Files [lookId] into Sammlungen: tap a row to put the look in or take it
/// out, hold it to rename, or start a new one. Without [lookId] it opens
/// straight on a new Sammlung, or on [edit] to rename or delete that one.
Future<void> showCollectionSheet(
  BuildContext context, {
  String? lookId,
  LookCollection? edit,
}) => showFormSheet<void>(
  context: context,
  builder: (_) => BlocProvider.value(
    value: context.read<LookCollectionsCubit>(),
    child: _CollectionSheet(lookId: lookId, edit: edit),
  ),
);

/// What the sheet shows: the list, or the form for a new or existing
/// Sammlung.
sealed class _Mode {
  const _Mode();
}

class _Picking extends _Mode {
  const _Picking();
}

class _Editing extends _Mode {
  const _Editing(this.collection);

  /// Null while creating.
  final LookCollection? collection;
}

class _CollectionSheet extends StatefulWidget {
  const _CollectionSheet({required this.lookId, required this.edit});
  final String? lookId;
  final LookCollection? edit;

  @override
  State<_CollectionSheet> createState() => _CollectionSheetState();
}

class _CollectionSheetState extends State<_CollectionSheet> {
  late _Mode _mode =
      widget.edit != null ||
          widget.lookId == null ||
          context.read<LookCollectionsCubit>().state.isEmpty
      ? _Editing(widget.edit)
      : const _Picking();
  final _name = TextEditingController();
  String _emoji = _emojis[math.Random().nextInt(_emojis.length)];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.edit case final edit?) {
      _name.text = edit.name;
      _emoji = edit.emoji;
    }
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _openForm(LookCollection? collection) {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _mode = _Editing(collection);
      _name.text = collection?.name ?? '';
      _emoji =
          collection?.emoji ?? _emojis[math.Random().nextInt(_emojis.length)];
    });
  }

  /// Back to the list when there is one to go back to, otherwise closed.
  void _leaveForm() {
    if (widget.lookId == null ||
        context.read<LookCollectionsCubit>().state.isEmpty) {
      Navigator.of(context).pop();
    } else {
      setState(() => _mode = const _Picking());
    }
  }

  Future<void> _toggle(LookCollection collection) async {
    unawaited(HapticFeedback.selectionClick());
    try {
      await context.read<LookCollectionsCubit>().toggle(
        collection.id,
        widget.lookId!,
      );
    } on FormApiException {
      if (mounted) {
        showFormToast(context, context.tr(LocaleKeys.collectionFailed));
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final mode = _mode;
    if (name.isEmpty || _busy || mode is! _Editing) return;
    setState(() => _busy = true);
    unawaited(HapticFeedback.mediumImpact());
    final cubit = context.read<LookCollectionsCubit>();
    try {
      if (mode.collection case final existing?) {
        await cubit.rename(existing.id, name: name, emoji: _emoji);
        if (!mounted) return;
        setState(() => _busy = false);
        _leaveForm();
        return;
      }
      await cubit.create(name: name, emoji: _emoji, lookId: widget.lookId);
      if (!mounted) return;
      showFormToast(
        context,
        context.tr(
          widget.lookId == null
              ? LocaleKeys.collectionCreated
              : LocaleKeys.collectionFiled,
          namedArgs: {'name': '$_emoji $name'},
        ),
      );
      Navigator.of(context).pop();
    } on FormApiException {
      if (!mounted) return;
      setState(() => _busy = false);
      showFormToast(context, context.tr(LocaleKeys.collectionFailed));
    }
  }

  Future<void> _delete(LookCollection collection) async {
    final removed = await confirmRemoveCollection(context, collection);
    if (removed && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final collections = context.watch<LookCollectionsCubit>().state;
    final mode = _mode;
    return switch (mode) {
      _Picking() => FormSheet(
        title: context.tr(LocaleKeys.collectionAddTitle),
        child: _picker(context, collections),
      ),
      _Editing(:final collection) => FormSheet(
        title: context.tr(
          collection == null
              ? LocaleKeys.collectionNew
              : LocaleKeys.collectionEdit,
        ),
        // The footer stays pinned above the keyboard.
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _name.text.trim().isEmpty || _busy ? null : _save,
              child: Text(
                context.tr(
                  collection != null
                      ? LocaleKeys.collectionSave
                      : widget.lookId == null
                      ? LocaleKeys.collectionCreate
                      : LocaleKeys.collectionCreateAndFile,
                ),
              ),
            ),
            if (collection != null)
              TextButton(
                onPressed: _busy ? null : () => _delete(collection),
                style: TextButton.styleFrom(
                  foregroundColor: FormTokens.danger,
                ),
                child: Text(context.tr(LocaleKeys.collectionRemove)),
              ),
          ],
        ),
        child: _form(context, creating: collection == null),
      ),
    };
  }

  Widget _picker(BuildContext context, List<LookCollection> collections) {
    final feed = context.watch<FeedCubit>().state;
    final looksById = {
      for (final record in feed.looks ?? const <CachedLook>[])
        record.look.id: record,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final collection in collections)
          _CollectionRow(
            collection: collection,
            looks: [
              for (final id in collection.lookIds) ?looksById[id],
            ],
            online: feed.online,
            selected: collection.lookIds.contains(widget.lookId),
            onTap: () => _toggle(collection),
            onEdit: () => _openForm(collection),
          ),
        _NewRow(onTap: () => _openForm(null)),
        const SizedBox(height: 10),
        Text(
          context.tr(LocaleKeys.collectionHoldHint),
          textAlign: TextAlign.center,
          style: FormTokens.small,
        ),
      ],
    );
  }

  Widget _form(BuildContext context, {required bool creating}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: CurvedAnimation(parent: animation, curve: FormTokens.pop),
              child: child,
            ),
            child: Container(
              key: ValueKey(_emoji),
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: FormTokens.selectedTint,
                borderRadius: BorderRadius.circular(FormTokens.cardRadius),
              ),
              child: Text(_emoji, style: const TextStyle(fontSize: 30)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _name,
              autofocus: creating,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: context.tr(LocaleKeys.collectionNameHint),
                counterText: '',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      // Two even rows of eight, so the picker reads as a tray.
      LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth / 8;
          return Wrap(
            children: [
              for (final emoji in _emojis)
                _EmojiChoice(
                  emoji: emoji,
                  size: size,
                  selected: emoji == _emoji,
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    setState(() => _emoji = emoji);
                  },
                ),
            ],
          );
        },
      ),
      if (creating && _name.text.isEmpty) ...[
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (emoji, label) in _suggestions)
              _IdeaPill(
                label: '$emoji  ${context.tr(label)}',
                onTap: () {
                  unawaited(HapticFeedback.selectionClick());
                  setState(() => _emoji = emoji);
                  _name.text = context.tr(label);
                },
              ),
          ],
        ),
      ],
      if (widget.lookId != null &&
          context.read<LookCollectionsCubit>().state.isNotEmpty) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _leaveForm,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
            label: Text(context.tr(LocaleKeys.collectionBack)),
          ),
        ),
      ],
    ],
  );
}

/// A Sammlung as a shelf row: its newest looks fanned on the left, name and
/// count, and a round toggle on the right. Filing the look fans the prints
/// open and pops the check in.
class _CollectionRow extends StatelessWidget {
  const _CollectionRow({
    required this.collection,
    required this.looks,
    required this.online,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  final LookCollection collection;
  final List<CachedLook> looks;
  final bool online;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final count = collection.lookIds.length;
    return Semantics(
      button: true,
      selected: selected,
      label: collection.name,
      onLongPressHint: context.tr(LocaleKeys.collectionEdit),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: () {
          unawaited(HapticFeedback.mediumImpact());
          onEdit();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: FormTokens.easeOut,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          decoration: BoxDecoration(
            color: selected ? FormTokens.selectedTint : Colors.transparent,
            borderRadius: BorderRadius.circular(FormTokens.panelRadius),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: looks.isEmpty
                    ? _EmojiCover(emoji: collection.emoji)
                    : FittedBox(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: selected ? 1.15 : 0.55),
                          duration: const Duration(milliseconds: 480),
                          curve: FormTokens.pop,
                          builder: (_, spread, _) => PhotoFan(
                            looks: looks,
                            feed: context.watch<FeedCubit>().state,
                            online: online,
                            photoSize: const Size(46, 58),
                            spread: spread,
                            angle: 0.16,
                            offset: 0.28,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${collection.emoji}  ${collection.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FormTokens.title,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(
                        count == 1
                            ? LocaleKeys.stackCountOne
                            : LocaleKeys.stackCountMany,
                        namedArgs: {'count': '$count'},
                      ),
                      style: FormTokens.small.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              _Toggle(on: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round check at the end of a row. Empty it is a ring, filed it fills
/// forest and the check pops in.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: on ? FormTokens.green : Colors.transparent,
      shape: BoxShape.circle,
      border: Border.all(
        color: on ? FormTokens.green : FormTokens.toggleOff,
        width: 1.5,
      ),
    ),
    child: AnimatedScale(
      scale: on ? 1 : 0,
      duration: const Duration(milliseconds: 360),
      curve: FormTokens.pop,
      child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
    ),
  );
}

/// The cover of a Sammlung without looks: its emoji on a soft print.
class _EmojiCover extends StatelessWidget {
  const _EmojiCover({required this.emoji});
  final String emoji;

  @override
  Widget build(BuildContext context) => Center(
    child: Transform.rotate(
      angle: -0.06,
      child: Container(
        width: 50,
        height: 62,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FormTokens.flatLayPaper,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FormTokens.surface, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x171D281C),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    ),
  );
}

class _NewRow extends StatelessWidget {
  const _NewRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.tr(LocaleKeys.collectionNew),
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              height: 76,
              child: Center(
                child: Container(
                  width: 50,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: FormTokens.uploadLine,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 24,
                    color: FormTokens.green,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              context.tr(LocaleKeys.collectionNew),
              style: FormTokens.title.copyWith(color: FormTokens.green),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmojiChoice extends StatelessWidget {
  const _EmojiChoice({
    required this.emoji,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: emoji,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: AnimatedContainer(
            duration: FormTokens.quick,
            width: size - 6,
            height: size - 6,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? FormTokens.selectedTint : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: AnimatedScale(
              scale: selected ? 1.15 : 1,
              duration: const Duration(milliseconds: 300),
              curve: FormTokens.pop,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A suggestion on the pill tone, per the design system's pill.
class _IdeaPill extends StatelessWidget {
  const _IdeaPill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: FormTokens.pill,
        borderRadius: BorderRadius.circular(FormTokens.chipRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 14, color: FormTokens.ink),
      ),
    ),
  );
}

/// Asks before deleting [collection]. Its looks stay in the feed. Returns
/// whether it was deleted.
Future<bool> confirmRemoveCollection(
  BuildContext context,
  LookCollection collection,
) async {
  unawaited(HapticFeedback.mediumImpact());
  final confirmed = await confirmFormAction(
    context: context,
    title: context.tr(
      LocaleKeys.collectionRemoveTitle,
      namedArgs: {'name': '${collection.emoji} ${collection.name}'},
    ),
    message: context.tr(LocaleKeys.collectionRemoveBody),
    confirmLabel: context.tr(LocaleKeys.collectionRemove),
  );
  if (!confirmed || !context.mounted) return false;
  try {
    await context.read<LookCollectionsCubit>().remove(collection.id);
    if (context.mounted) {
      showFormToast(context, context.tr(LocaleKeys.collectionRemoved));
    }
    return true;
  } on FormApiException {
    if (context.mounted) {
      showFormToast(context, context.tr(LocaleKeys.collectionFailed));
    }
    return false;
  }
}
