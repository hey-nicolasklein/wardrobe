import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/occasion_tile.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/idempotency_key.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

/// Pieces one round may insist on. The planner builds the rest around them.
const maxMustHaves = 4;

/// The order pieces are listed in for picking must-haves, head to toe.
const _categoryOrder = [
  'coat',
  'jacket',
  'top',
  'dress',
  'pants',
  'skirt',
  'shoes',
  'bag',
  'hat',
  'scarf',
  'accessory',
];

/// "Create look", looking forward: what it is for, which pieces have to be
/// in it, then a swipe deck of free proposals. Both steps can be skipped.
class CreateLookPage extends StatefulWidget {
  const CreateLookPage({
    this.occasion,
    this.itemIds = const [],
    super.key,
  });

  /// Preselected occasion, e.g. from an occasion stack.
  final String? occasion;

  /// Preselected must-have pieces, e.g. from a piece's stack.
  final List<String> itemIds;

  @override
  State<CreateLookPage> createState() => _CreateLookPageState();
}

class _CreateLookPageState extends State<CreateLookPage> {
  final _note = TextEditingController();
  var _step = 0;
  late String? _occasion = widget.occasion;
  late bool _occasionPicked = widget.occasion != null;
  late final List<String> _mustHaves = [...widget.itemIds.take(maxMustHaves)];
  var _starting = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _toPieces() {
    FocusScope.of(context).unfocus();
    unawaited(HapticFeedback.selectionClick());
    setState(() => _step = 1);
  }

  void _toggle(String id) {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      if (!_mustHaves.remove(id) && _mustHaves.length < maxMustHaves) {
        _mustHaves.add(id);
      }
    });
  }

  Future<void> _start() async {
    final looks = context.read<LookRepository>();
    final note = _note.text.trim();
    final body = <String, dynamic>{
      'exactItemIds': [..._mustHaves],
      'categories': <String>[],
      'occasion': _occasion,
      'style': 'candid',
      'completion': 'wardrobe',
      'idempotencyKey': newIdempotencyKey(),
      // Only heads the deck. The planner has no free-text input yet.
      if (note.isNotEmpty) 'label': note,
    };
    setState(() {
      _starting = true;
      _failure = null;
    });
    unawaited(HapticFeedback.mediumImpact());
    try {
      await looks.propose(body);
      if (!mounted) return;
      context.pushReplacement('/feed/proposals', extra: body);
    } on FormApiException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(() => _step = 0);
    },
    child: FormSheet(
      title: context.tr(LocaleKeys.createLook),
      scrollable: false,
      leading: _step == 1
          ? IconButton(
              onPressed: () => setState(() => _step = 0),
              tooltip: context.tr(LocaleKeys.composerBack),
              style: IconButton.styleFrom(backgroundColor: FormTokens.field),
              icon: const Icon(Icons.arrow_back),
            )
          : null,
      footer: _step == 0
          ? Row(
              spacing: 12,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _occasion = null;
                      _occasionPicked = false;
                      _note.clear();
                      _toPieces();
                    },
                    child: Text(context.tr(LocaleKeys.createSkip)),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: _toPieces,
                    child: Text(context.tr(LocaleKeys.createNext)),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                if (_failure != null)
                  FormNotice(
                    text: apiFailureText(context, _failure!),
                    error: true,
                  ),
                FilledButton(
                  onPressed: _starting ? null : () => unawaited(_start()),
                  child: _starting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          context.tr(
                            _mustHaves.isEmpty
                                ? LocaleKeys.createShowAll
                                : LocaleKeys.createShowAround,
                          ),
                        ),
                ),
                Text(
                  context.tr(LocaleKeys.createFree),
                  textAlign: TextAlign.center,
                  style: FormTokens.small,
                ),
              ],
            ),
      // Full height from the start, like the deck it hands over to, so the
      // sheet does not jump between the steps.
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: constraints.maxHeight,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: FormTokens.easeOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: _step == 0
                ? _OccasionStep(
                    key: const ValueKey('occasion'),
                    occasion: _occasion,
                    picked: _occasionPicked,
                    note: _note,
                    onOccasion: (value) => setState(() {
                      final again = _occasionPicked && _occasion == value;
                      _occasion = again ? null : value;
                      _occasionPicked = !again;
                    }),
                    onSubmitted: _toPieces,
                  )
                : _MustHaveStep(
                    key: const ValueKey('pieces'),
                    selected: _mustHaves,
                    onToggle: _toggle,
                  ),
          ),
        ),
      ),
    ),
  );
}

class _OccasionStep extends StatelessWidget {
  const _OccasionStep({
    required this.occasion,
    required this.picked,
    required this.note,
    required this.onOccasion,
    required this.onSubmitted,
    super.key,
  });

  final String? occasion;
  final bool picked;
  final TextEditingController note;
  final ValueChanged<String?> onOccasion;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.createOccasionTitle),
          style: FormTokens.heading.copyWith(fontSize: 24),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(LocaleKeys.createOccasionBody),
          style: FormTokens.small,
        ),
        const SizedBox(height: 18),
        Row(
          spacing: 8,
          children: [
            for (final preset in occasionPresets)
              Expanded(
                child: OccasionTile(
                  icon: preset.icon,
                  label: context.tr(preset.label),
                  colors: FormTokens.occasions[preset.value ?? '']!,
                  selected: picked && occasion == preset.value,
                  onTap: () => onOccasion(preset.value),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: note,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            hintText: context.tr(LocaleKeys.createNoteHint),
            filled: true,
            fillColor: FormTokens.field,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(FormTokens.inputRadius),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    ),
  );
}

/// Pieces from the Schrank that have to be in the outfit. Optional.
class _MustHaveStep extends StatelessWidget {
  const _MustHaveStep({
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final wardrobe = context.watch<WardrobeCubit>().state;
    final online = !wardrobe.stale;
    int rank(WardrobeItem item) {
      final index = _categoryOrder.indexOf(item.metadata.category);
      return index < 0 ? _categoryOrder.length : index;
    }

    final items = [
      for (final item in eligibleComposerItems(wardrobe.items ?? []))
        if (item.state == 'owning') item,
    ]..sort((a, b) => rank(a) - rank(b));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.createPiecesTitle),
          style: FormTokens.heading.copyWith(fontSize: 24),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
            LocaleKeys.createPiecesBody,
            namedArgs: {'max': '$maxMustHaves'},
          ),
          style: FormTokens.small,
        ),
        const SizedBox(height: 14),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final position = selected.indexOf(item.id);
              final full = selected.length >= maxMustHaves && position < 0;
              return Semantics(
                button: true,
                selected: position >= 0,
                label: item.metadata.name,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: full ? null : () => onToggle(item.id),
                  child: AnimatedOpacity(
                    duration: FormTokens.quick,
                    opacity: full ? 0.4 : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: FormTokens.easeOut,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: FormTokens.tileTint(
                          item.id,
                          item.metadata.colors,
                        ),
                        borderRadius: BorderRadius.circular(
                          FormTokens.cardRadius,
                        ),
                        border: Border.all(
                          color: position >= 0
                              ? FormTokens.green
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        fit: StackFit.expand,
                        children: [
                          CachedMedia(
                            identity: item.previewIdentity,
                            previewPath: item.previewPath,
                            online: online,
                          ),
                          Positioned(
                            top: -2,
                            right: -2,
                            child: AnimatedScale(
                              scale: position >= 0 ? 1 : 0,
                              duration: const Duration(milliseconds: 300),
                              curve: FormTokens.pop,
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: FormTokens.green,
                                child: Text(
                                  '${position + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
