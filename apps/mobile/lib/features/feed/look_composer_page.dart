import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/composer_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/settings/quality_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';

/// The PWA's look composer (`openLookComposer`), shown as a sheet route.
class LookComposerPage extends StatelessWidget {
  const LookComposerPage({this.preselectedIds = const [], super.key});

  final List<String> preselectedIds;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => ComposerCubit(
      context.read<LookRepository>(),
      preselectedIds: preselectedIds,
      defaultQuality: context.read<QualityCubit>().state.feed,
    ),
    child: const _ComposerView(),
  );
}

class _ComposerView extends StatefulWidget {
  const _ComposerView();

  @override
  State<_ComposerView> createState() => _ComposerViewState();
}

class _ComposerViewState extends State<_ComposerView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onState(BuildContext context, ComposerState state) {
    if (_search.text != state.query) _search.text = state.query;
    if (state.createdLookId != null) {
      // The new look is the newest card, so it sits at the top of the feed.
      context.go('/feed');
      showFormToast(context, context.tr(LocaleKeys.lookCreating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wardrobe = context.watch<WardrobeCubit>().state;
    final connected =
        context.watch<ConnectionCubit>().state == ConnectionStatus.ready;
    final eligible = eligibleComposerItems(wardrobe.items ?? []);
    return BlocConsumer<ComposerCubit, ComposerState>(
      listenWhen: (previous, next) =>
          previous.query != next.query ||
          previous.createdLookId != next.createdLookId,
      listener: _onState,
      builder: (context, state) {
        final cubit = context.read<ComposerCubit>();
        final selected = state.selectedItems(eligible);
        return PopScope(
          // Back from the flat-lay preview returns to the picker first.
          canPop: !state.previewExpanded,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.closePreview();
          },
          child: FormSheet(
            title: context.tr(LocaleKeys.createLook),
            footer: _ComposerFooter(
              state: state,
              selected: selected,
              online: !wardrobe.stale,
              connected: connected,
            ),
            child: state.previewExpanded
                ? _ComposerPreview(state: state, selected: selected)
                : _ComposerPicker(
                    state: state,
                    eligible: eligible,
                    search: _search,
                    online: !wardrobe.stale,
                  ),
          ),
        );
      },
    );
  }
}

class _ComposerPicker extends StatelessWidget {
  const _ComposerPicker({
    required this.state,
    required this.eligible,
    required this.search,
    required this.online,
  });

  final ComposerState state;
  final List<WardrobeItem> eligible;
  final TextEditingController search;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    final visible = state.visible(eligible);
    final available = [
      for (final category in categories)
        if (eligible.any((item) => item.metadata.category == category))
          category,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.composerQualityLabel),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        FormNotice(text: context.tr(LocaleKeys.composerQualityNote)),
        const SizedBox(height: 8),
        FormChoiceChips(
          options: {
            for (final quality in qualities)
              quality: context.tr('quality.$quality'),
          },
          selected: state.quality,
          onSelected: cubit.setQuality,
        ),
        const SizedBox(height: 24),
        _OccasionPresets(selected: state.occasion),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr(LocaleKeys.composerPickerTitle),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: FormTokens.ink,
                ),
              ),
            ),
            Tooltip(
              message: context.tr(LocaleKeys.composerSelectedOnly),
              child: FormPill(
                label: context.tr(
                  LocaleKeys.composerSelectedCount,
                  namedArgs: {'count': '${state.selectedIds.length}'},
                ),
                leading: const FormIcon(FormIconName.check, size: 18),
                selected: state.selectedOnly,
                onTap: cubit.toggleSelectedOnly,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FormSearchField(
          controller: search,
          hint: context.tr(LocaleKeys.composerSearchHint),
          onChanged: cubit.setQuery,
          onClear: state.query.isEmpty ? null : () => cubit.setQuery(''),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final category in [null, ...available])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FormPill(
                    label: category == null
                        ? context.tr(LocaleKeys.composerFilterAll)
                        : context.tr('categories.$category'),
                    selected:
                        !state.selectedOnly && state.itemCategory == category,
                    onTap: () => cubit.setItemCategory(category),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (visible.isEmpty)
          Text(
            context.tr(
              eligible.isEmpty
                  ? LocaleKeys.composerNoEligible
                  : LocaleKeys.composerEmpty,
            ),
            style: FormTokens.small,
          )
        else
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 18,
            crossAxisSpacing: 12,
            childAspectRatio: 0.6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final item in visible)
                _SelectItem(
                  item: item,
                  selected: state.selectedIds.contains(item.id),
                  online: online,
                  onTap: () => cubit.toggleItem(item.id),
                ),
            ],
          ),
        const SizedBox(height: 24),
        _CompletionOptions(state: state),
      ],
    );
  }
}

class _OccasionPresets extends StatelessWidget {
  const _OccasionPresets({required this.selected});

  final String? selected;

  static const List<({FormIconName icon, String label, String? value})>
  _presets = [
    (
      value: null,
      icon: FormIconName.shuffle,
      label: LocaleKeys.composerOccasionSurprise,
    ),
    (
      value: 'night-out',
      icon: FormIconName.moon,
      label: LocaleKeys.composerOccasionNightOut,
    ),
    (
      value: 'party',
      icon: FormIconName.party,
      label: LocaleKeys.composerOccasionParty,
    ),
    (
      value: 'casual',
      icon: FormIconName.top,
      label: LocaleKeys.composerOccasionCasual,
    ),
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (index, preset) in _presets.indexed) ...[
        if (index > 0) const SizedBox(width: 10),
        Expanded(child: _preset(context, preset)),
      ],
    ],
  );

  Widget _preset(
    BuildContext context,
    ({String? value, FormIconName icon, String label}) preset,
  ) {
    final colors = FormTokens.occasions[preset.value ?? '']!;
    final pressed = preset.value == selected;
    return Semantics(
      button: true,
      selected: pressed,
      child: GestureDetector(
        onTap: () => context.read<ComposerCubit>().setOccasion(preset.value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
          decoration: BoxDecoration(
            color: colors.tint,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: pressed ? colors.ink : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              FormIcon(preset.icon, color: colors.ink),
              const SizedBox(height: 12),
              Text(
                context.tr(preset.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectItem extends StatelessWidget {
  const _SelectItem({
    required this.item,
    required this.selected,
    required this.online,
    required this.onTap,
  });

  static const TextStyle titleStyle = TextStyle(
    fontSize: 11,
    height: 1.3,
    color: FormTokens.ink,
  );
  static const double titleHeight = 11 * 1.3 * 2;

  final WardrobeItem item;
  final bool selected;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: item.metadata.name,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = math.min(
                  constraints.maxHeight,
                  width * 4 / 3,
                );
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selected
                                ? FormTokens.selectedTint
                                : FormTokens.field,
                            borderRadius: BorderRadius.circular(
                              FormTokens.inputRadius,
                            ),
                          ),
                          child: CachedMedia(
                            identity: item.previewIdentity,
                            previewPath: item.previewPath,
                            online: online,
                          ),
                        ),
                        if (selected)
                          const Positioned(
                            top: 7,
                            right: 7,
                            child: _CheckBadge(),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: SizedBox(
              height: _SelectItem.titleHeight,
              width: double.infinity,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  item.metadata.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _SelectItem.titleStyle,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: FormTokens.checkBadge,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: FormTokens.flatLayInk.withValues(alpha: 0.07),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: const FormIcon(
      FormIconName.check,
      size: 14,
      color: FormTokens.checkInk,
    ),
  );
}

class _CompletionOptions extends StatefulWidget {
  const _CompletionOptions({required this.state});

  final ComposerState state;

  @override
  State<_CompletionOptions> createState() => _CompletionOptionsState();
}

class _CompletionOptionsState extends State<_CompletionOptions> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<ComposerCubit>();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FormTokens.surface,
        border: Border.all(color: FormTokens.line),
        borderRadius: BorderRadius.circular(FormTokens.inputRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FormTokens.inputRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormToggleRow(
              title: context.tr(LocaleKeys.composerCompleteTitle),
              subtitle: context.tr(
                state.completeWithWardrobe
                    ? LocaleKeys.composerCompleteHelpOn
                    : LocaleKeys.composerCompleteHelpOff,
              ),
              value: state.completeWithWardrobe,
              onChanged: state.canToggleCompletion
                  ? (_) => cubit.toggleCompleteWithWardrobe()
                  : null,
            ),
            if (state.completeWithWardrobe) ...[
              const Divider(height: 1, color: FormTokens.line),
              InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        const FormIcon(FormIconName.filter, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr(LocaleKeys.composerCategoriesTitle),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(_open ? '−' : '+'),
                      ],
                    ),
                  ),
                ),
              ),
              if (_open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category in categories)
                        FormPill(
                          label: context.tr('categories.$category'),
                          selected: state.categories.contains(category),
                          onTap: () => cubit.toggleCategory(category),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComposerPreview extends StatelessWidget {
  const _ComposerPreview({required this.state, required this.selected});

  final ComposerState state;
  final List<WardrobeItem> selected;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    final piece = selected
        .where((item) => item.id == state.selectedPieceId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: cubit.closePreview,
            icon: const FormIcon(FormIconName.arrow, size: 18),
            label: Text(context.tr(LocaleKeys.composerBack)),
          ),
        ),
        Text(
          context.tr(LocaleKeys.composerPreviewHint),
          style: FormTokens.small,
        ),
        const SizedBox(height: 12),
        if (selected.isEmpty) ...[
          Text(
            context.tr(LocaleKeys.composerPreviewEmpty),
            style: FormTokens.body,
          ),
          Text(
            context.tr(LocaleKeys.composerPreviewEmptyHint),
            style: FormTokens.small,
          ),
        ] else
          FlatLayBoard(
            garments: [
              for (final item in selected) LookGarment(id: item.id, item: item),
            ],
            online: true,
            selectedId: state.selectedPieceId,
            onGarmentTap: cubit.selectPiece,
          ),
        const SizedBox(height: 12),
        if (piece == null)
          Text(
            context.tr(LocaleKeys.composerPieceHint),
            style: FormTokens.small,
          )
        else
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      piece.metadata.name,
                      style: FormTokens.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      context.tr('categories.${piece.metadata.category}'),
                      style: FormTokens.small,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => cubit.toggleItem(piece.id),
                child: Text(context.tr(LocaleKeys.composerRemovePiece)),
              ),
            ],
          ),
      ],
    );
  }
}

class _ComposerFooter extends StatelessWidget {
  const _ComposerFooter({
    required this.state,
    required this.selected,
    required this.online,
    required this.connected,
  });

  final ComposerState state;
  final List<WardrobeItem> selected;
  final bool online;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toasts would land behind the sheet, so problems show inline here.
        if (state.failure != null || state.limitReached) ...[
          FormNotice(
            text: state.limitReached
                ? context.tr(LocaleKeys.composerLimit)
                : apiFailureText(context, state.failure!),
            error: state.failure != null,
          ),
          const SizedBox(height: 12),
        ],
        if (selected.isNotEmpty && !state.previewExpanded) ...[
          _Tray(selected: selected, online: online),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                composerSummaryText(context, state),
                style: FormTokens.small.copyWith(color: FormTokens.ink),
              ),
            ),
            TextButton(
              onPressed: cubit.reset,
              child: Text(context.tr(LocaleKeys.composerReset)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: state.submitting || !connected
              ? null
              : () => unawaited(cubit.submit()),
          child: state.submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(context.tr(LocaleKeys.createLook)),
        ),
      ],
    );
  }
}

/// "Damit starten wir": up to five selected pieces that open the preview.
class _Tray extends StatelessWidget {
  const _Tray({required this.selected, required this.online});

  static const _slot = 56.0;
  static const _moreWidth = 28.0;

  final List<WardrobeItem> selected;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final shown = selected.take(5).toList();
    final more = selected.length - shown.length;
    // Matches the PWA, which shrinks the tray on short screens.
    final height = MediaQuery.sizeOf(context).height <= 740 ? 48.0 : 62.0;
    return Semantics(
      button: true,
      label: context.tr(
        LocaleKeys.composerTrayLabel,
        namedArgs: {'count': '${selected.length}'},
      ),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.read<ComposerCubit>().openPreview(),
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 105,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(LocaleKeys.composerTrayTitle),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: FormTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            context.tr(LocaleKeys.composerTrayAction),
                            style: const TextStyle(
                              fontSize: 11,
                              color: FormTokens.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.chevron_left,
                          size: 13,
                          color: FormTokens.muted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: height,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Pieces are laid out right-aligned by hand so that a
                      // slot shifting over glides instead of jumping.
                      final end =
                          constraints.maxWidth - (more > 0 ? _moreWidth : 0);
                      final size = math.min(
                        math.min(_slot, height),
                        end / shown.length,
                      );
                      return Stack(
                        children: [
                          for (final (index, item) in shown.indexed)
                            AnimatedPositioned(
                              key: ValueKey(item.id),
                              duration: _TrayGarment.duration,
                              curve: _TrayGarment.curve,
                              left: end - (shown.length - index) * size,
                              top: (height - size) / 2,
                              width: size,
                              height: size,
                              child: _TrayGarment(
                                item: item,
                                online: online,
                                delay: index * 35,
                              ),
                            ),
                          if (more > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              width: _moreWidth,
                              child: Center(
                                child: Text(
                                  '+$more',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: FormTokens.muted,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tray piece that rises into place when it first appears, like the PWA's
/// entrance: up 14px, from 88% scale and transparent.
class _TrayGarment extends StatefulWidget {
  const _TrayGarment({
    required this.item,
    required this.online,
    required this.delay,
  });

  static const duration = Duration(milliseconds: 420);
  static const curve = Cubic(0.22, 1, 0.36, 1);

  final WardrobeItem item;
  final bool online;
  final int delay;

  @override
  State<_TrayGarment> createState() => _TrayGarmentState();
}

class _TrayGarmentState extends State<_TrayGarment>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: _TrayGarment.duration,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: _TrayGarment.curve,
  );
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted || _delay != null) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _delay = Timer(
        Duration(milliseconds: widget.delay),
        () => unawaited(_controller.forward()),
      );
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    builder: (context, child) {
      final t = _progress.value;
      return Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
        ),
      );
    },
    child: CachedMedia(
      identity: widget.item.previewIdentity,
      previewPath: widget.item.previewPath,
      online: widget.online,
    ),
  );
}
