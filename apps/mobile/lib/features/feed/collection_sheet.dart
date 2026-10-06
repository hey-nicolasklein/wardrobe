import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/look_collections_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/look_collection_repository.dart';
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

/// Files [lookId] into Sammlungen: tap one to put the look in or take it out,
/// or start a new one. Without [lookId] it only creates a Sammlung.
Future<void> showCollectionSheet(BuildContext context, {String? lookId}) =>
    showFormSheet<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<LookCollectionsCubit>(),
        child: _CollectionSheet(lookId: lookId),
      ),
    );

class _CollectionSheet extends StatefulWidget {
  const _CollectionSheet({required this.lookId});
  final String? lookId;

  @override
  State<_CollectionSheet> createState() => _CollectionSheetState();
}

class _CollectionSheetState extends State<_CollectionSheet> {
  late bool _creating =
      widget.lookId == null ||
      context.read<LookCollectionsCubit>().state.isEmpty;

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

  @override
  Widget build(BuildContext context) {
    final collections = context.watch<LookCollectionsCubit>().state;
    return FormSheet(
      title: context.tr(
        _creating ? LocaleKeys.collectionNew : LocaleKeys.collectionAddTitle,
      ),
      child: AnimatedSize(
        duration: FormTokens.sheetDuration,
        curve: FormTokens.sheetCurve,
        alignment: Alignment.topCenter,
        child: _creating
            ? _CreateCollection(
                lookId: widget.lookId,
                onBack: collections.isEmpty || widget.lookId == null
                    ? null
                    : () => setState(() => _creating = false),
              )
            : GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
                children: [
                  for (final collection in collections)
                    _CollectionTile(
                      emoji: collection.emoji,
                      label: collection.name,
                      count: collection.lookIds.length,
                      selected: collection.lookIds.contains(widget.lookId),
                      onTap: () => _toggle(collection),
                    ),
                  _NewTile(
                    onTap: () => setState(() => _creating = true),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A Sammlung to tap. Picking it bounces the emoji and pops a check in.
class _CollectionTile extends StatefulWidget {
  const _CollectionTile({
    required this.emoji,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CollectionTile> createState() => _CollectionTileState();
}

class _CollectionTileState extends State<_CollectionTile>
    with SingleTickerProviderStateMixin {
  late final _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didUpdateWidget(_CollectionTile old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) unawaited(_bounce.forward(from: 0));
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: widget.selected,
    label: widget.label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: FormTokens.quick,
        decoration: BoxDecoration(
          color: widget.selected ? FormTokens.selectedTint : FormTokens.field,
          borderRadius: BorderRadius.circular(FormTokens.panelRadius),
          border: Border.all(
            color: widget.selected ? FormTokens.green : Colors.transparent,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _bounce,
                    builder: (_, child) {
                      final t = _bounce.value;
                      // A quick hop with a wiggle that settles.
                      return Transform.translate(
                        offset: Offset(0, -10 * math.sin(t * math.pi)),
                        child: Transform.rotate(
                          angle: 0.25 * math.sin(t * math.pi * 3) * (1 - t),
                          child: Transform.scale(
                            scale: 1 + 0.25 * math.sin(t * math.pi),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      widget.emoji,
                      style: const TextStyle(fontSize: 34),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FormTokens.ink,
                    ),
                  ),
                  Text(
                    context.tr(
                      widget.count == 1
                          ? LocaleKeys.stackCountOne
                          : LocaleKeys.stackCountMany,
                      namedArgs: {'count': '${widget.count}'},
                    ),
                    style: FormTokens.small,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedScale(
                scale: widget.selected ? 1 : 0,
                duration: const Duration(milliseconds: 320),
                curve: FormTokens.pop,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: FormTokens.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NewTile extends StatelessWidget {
  const _NewTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.tr(LocaleKeys.collectionNew),
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FormTokens.panelRadius),
          border: Border.all(color: FormTokens.uploadLine, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 30, color: FormTokens.green),
            const SizedBox(height: 6),
            Text(
              context.tr(LocaleKeys.collectionNew),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: FormTokens.green,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Name and emoji for a new Sammlung. The emoji starts random, so every new
/// Sammlung already looks like something.
class _CreateCollection extends StatefulWidget {
  const _CreateCollection({required this.lookId, required this.onBack});
  final String? lookId;
  final VoidCallback? onBack;

  @override
  State<_CreateCollection> createState() => _CreateCollectionState();
}

class _CreateCollectionState extends State<_CreateCollection> {
  final _name = TextEditingController();
  late String _emoji = _emojis[math.Random().nextInt(_emojis.length)];
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _pick(String emoji) {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _emoji = emoji);
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    unawaited(HapticFeedback.mediumImpact());
    final navigator = Navigator.of(context);
    try {
      await context.read<LookCollectionsCubit>().create(
        name: name,
        emoji: _emoji,
        lookId: widget.lookId,
      );
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
      navigator.pop();
    } on FormApiException {
      if (!mounted) return;
      setState(() => _busy = false);
      showFormToast(context, context.tr(LocaleKeys.collectionFailed));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
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
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: FormTokens.selectedTint,
                borderRadius: BorderRadius.circular(FormTokens.panelRadius),
              ),
              child: Text(_emoji, style: const TextStyle(fontSize: 36)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _name,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _create(),
              decoration: InputDecoration(
                hintText: context.tr(LocaleKeys.collectionNameHint),
                counterText: '',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final emoji in _emojis)
            GestureDetector(
              onTap: () => _pick(emoji),
              child: AnimatedContainer(
                duration: FormTokens.quick,
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: emoji == _emoji
                      ? FormTokens.selectedTint
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
        ],
      ),
      if (_name.text.isEmpty) ...[
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (emoji, label) in _suggestions)
              ActionChip(
                label: Text('$emoji ${context.tr(label)}'),
                onPressed: () {
                  _pick(emoji);
                  _name.text = context.tr(label);
                },
              ),
          ],
        ),
      ],
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _name.text.trim().isEmpty || _busy ? null : _create,
        child: Text(
          context.tr(
            widget.lookId == null
                ? LocaleKeys.collectionCreate
                : LocaleKeys.collectionCreateAndFile,
          ),
        ),
      ),
      if (widget.onBack case final onBack?)
        TextButton(
          onPressed: onBack,
          child: Text(context.tr(LocaleKeys.collectionBack)),
        ),
    ],
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
