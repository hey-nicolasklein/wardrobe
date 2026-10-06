import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_settings/app_settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
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
import 'package:form_mobile/repository/credits_repository.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

bool _analyzing(IntakeDraft draft) => switch (draft.phase) {
  DraftPhase.local ||
  DraftPhase.uploading ||
  DraftPhase.uploaded ||
  DraftPhase.detecting => true,
  _ => false,
};

bool _leaving(IntakeDraft draft) =>
    draft.phase == DraftPhase.saving || draft.phase == DraftPhase.finished;

bool _ready(IntakeDraft draft) =>
    draft.phase == DraftPhase.ready && draft.failure == null;

/// Detected pieces in a stable order: clothes first, accessories last, so
/// the preselected pieces lead the strip.
List<IntakeChoice> _pieces(IntakeDraft draft) {
  const order = ['top', 'bottom', 'shoes', 'accessory'];
  final pieces = draft.choices.where((c) => c.proposal != null).toList();
  return [
    for (final theme in order)
      ...pieces.where((c) => _detectionTheme(c.proposal!.category) == theme),
  ];
}

/// Adding pieces works one photo at a time: a tray of all photos on top, the
/// current photo in the middle and its pieces as a strip below. Every region
/// keeps its height while photos are analysed in the background, so nothing
/// jumps. Saving a photo moves on to the next one that needs a decision.
class IntakePage extends StatefulWidget {
  const IntakePage({super.key});
  @override
  State<IntakePage> createState() => _IntakePageState();
}

class _IntakePageState extends State<IntakePage> {
  bool _picking = false;
  String? _pickerError;
  late IntakeBloc _bloc;
  final _pages = PageController();
  final _trayKeys = <String, GlobalKey>{};
  String? _currentId;
  IntakeState _previous = const IntakeState();

  @override
  void initState() {
    super.initState();
    _bloc = context.read<IntakeBloc>();
    _bloc.availability(visible: true);
  }

  @override
  void dispose() {
    _bloc.availability(visible: false);
    _pages.dispose();
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

  Future<void> _pickSource() async {
    final camera = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(context.tr(LocaleKeys.intake_more)),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr(LocaleKeys.intake_camera)),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr(LocaleKeys.intake_library)),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr(LocaleKeys.cancel)),
        ),
      ),
    );
    if (camera != null) await _pick(camera: camera);
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

  void _goTo(String id, {bool animate = true}) {
    final index = _bloc.state.drafts.indexWhere((d) => d.id == id);
    if (index < 0 || !_pages.hasClients) return;
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      unawaited(
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 460),
          curve: FormTokens.sheetCurve,
        ),
      );
    } else {
      _pages.jumpToPage(index);
    }
  }

  void _showing(String id) {
    setState(() => _currentId = id);
    final tray = _trayKeys[id]?.currentContext;
    if (tray != null) {
      unawaited(
        Scrollable.ensureVisible(
          tray,
          alignment: 0.5,
          duration: FormTokens.sheetDuration,
          curve: FormTokens.easeOut,
        ),
      );
    }
  }

  /// The next photo that still needs a decision, ready ones first.
  IntakeDraft? _nextOpen(String afterId) {
    final drafts = _bloc.state.drafts;
    final start = drafts.indexWhere((d) => d.id == afterId);
    final order = [...drafts.skip(start + 1), ...drafts.take(start)];
    return order.where(_ready).firstOrNull ??
        order.where((d) => !_leaving(d)).firstOrNull;
  }

  void _save(IntakeDraft draft) {
    unawaited(HapticFeedback.mediumImpact());
    _bloc.add(IntakeEvent(IntakeAction.save, id: draft.id));
    final next = _nextOpen(draft.id);
    if (next == null) return;
    // Long enough to see the pieces being stamped, then on to the next photo
    // while saving continues in the background.
    Timer(const Duration(milliseconds: 750), () {
      if (mounted && _currentId == draft.id) _goTo(next.id);
    });
  }

  // The last draft leaving while it was saving means everything picked has
  // landed in the wardrobe, so return to the list. A discard does not count.
  static bool _savedLastDraft(IntakeState previous, IntakeState current) =>
      current.drafts.isEmpty &&
      previous.drafts.isNotEmpty &&
      previous.drafts.every(_leaving);

  /// Keeps the shown photo when drafts arrive or leave. A removed photo hands
  /// over to the one that followed it.
  void _sync(IntakeState previous, IntakeState current) {
    if (_savedLastDraft(previous, current)) {
      context.go('/wardrobe');
      return;
    }
    final ids = current.drafts.map((d) => d.id).toList();
    _trayKeys.removeWhere((id, _) => !ids.contains(id));
    if (ids.isEmpty) {
      _currentId = null;
      return;
    }
    var id = _currentId;
    if (id == null) {
      id = ids.first;
    } else if (!ids.contains(id)) {
      final oldIds = previous.drafts.map((d) => d.id).toList();
      id =
          oldIds.skip(oldIds.indexOf(id) + 1).where(ids.contains).firstOrNull ??
          ids.last;
    }
    _currentId = id;
    final index = ids.indexOf(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients) return;
      if ((_pages.page ?? 0).round() != index) _pages.jumpToPage(index);
    });
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<IntakeBloc, IntakeState>(
    listenWhen: (previous, current) {
      _previous = previous;
      return previous.drafts != current.drafts;
    },
    listener: (context, state) => _sync(_previous, state),
    builder: (context, state) {
      final online =
          context.watch<ConnectionCubit>().state == ConnectionStatus.ready;
      final drafts = state.drafts;
      final current =
          drafts.where((d) => d.id == _currentId).firstOrNull ??
          drafts.firstOrNull;
      final notices = <Widget>[
        if (!online)
          FormNotice(text: context.tr(LocaleKeys.intake_offline), error: true),
        if (state.error != null)
          FormNotice(text: context.tr(state.error!), error: true),
        if (_pickerError != null) ...[
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
        appBar: FormPageHeader(
          title: context.tr(LocaleKeys.intake_title),
          subtitle: drafts.length > 1 && current != null
              ? context.tr(
                  LocaleKeys.intake_photoOf,
                  namedArgs: {
                    'index': '${drafts.indexOf(current) + 1}',
                    'total': '${drafts.length}',
                  },
                )
              : null,
        ),
        body: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            if (current == null) {
              return _EmptyIntake(
                padding: padding,
                online: online,
                picking: _picking,
                notices: notices,
                onCamera: () => _pick(camera: true),
                onLibrary: () => _pick(camera: false),
              );
            }
            final enabled = online && !_picking;
            return Padding(
              padding: EdgeInsets.only(top: padding.top),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        FormTokens.gutter,
                        4,
                        FormTokens.gutter,
                        8,
                      ),
                      child: Column(spacing: 8, children: notices),
                    ),
                  _PhotoTray(
                    drafts: drafts,
                    currentId: current.id,
                    keys: _trayKeys,
                    canAdd: online && !_picking,
                    onSelect: _goTo,
                    onAdd: _pickSource,
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: drafts.length,
                      onPageChanged: (index) => _showing(drafts[index].id),
                      findChildIndexCallback: (key) {
                        final index = drafts.indexWhere(
                          (d) => ValueKey(d.id) == key,
                        );
                        return index < 0 ? null : index;
                      },
                      itemBuilder: (context, index) {
                        final draft = drafts[index];
                        return _DraftPage(
                          key: ValueKey(draft.id),
                          draft: draft,
                          enabled: enabled,
                          onDiscard: () => _discard(draft),
                          onToggle: (choice) => _bloc.add(
                            IntakeEvent(
                              IntakeAction.select,
                              id: draft.id,
                              choiceKey: choice.itemKey,
                              value: !choice.selected,
                            ),
                          ),
                          onOwnership: (owning) => _bloc.add(
                            IntakeEvent(
                              IntakeAction.ownership,
                              id: draft.id,
                              value: owning,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (current.phase != DraftPhase.manual)
                    _ActionBar(
                      draft: current,
                      enabled: enabled,
                      bottom: padding.bottom,
                      nextReady: _ready(current)
                          ? null
                          : drafts
                                .where((d) => d.id != current.id)
                                .where(_ready)
                                .firstOrNull,
                      onSave: () => _save(current),
                      onRetry: () => _bloc.add(
                        IntakeEvent(IntakeAction.retry, id: current.id),
                      ),
                      onNext: _goTo,
                    ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

/// The first view before any photo is picked. It fits the screen without
/// scrolling and previews the flow: pick photos, FORM finds the pieces, tap
/// to choose and add.
class _EmptyIntake extends StatelessWidget {
  const _EmptyIntake({
    required this.padding,
    required this.online,
    required this.picking,
    required this.notices,
    required this.onCamera,
    required this.onLibrary,
  });

  final EdgeInsets padding;
  final bool online;
  final bool picking;
  final List<Widget> notices;
  final VoidCallback onCamera;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final disabled = picking || !online;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FormTokens.gutter,
        padding.top + 4,
        FormTokens.gutter,
        padding.bottom + 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(
            child: FormReveal(child: LoopingScanStage()),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr(LocaleKeys.intake_uploadTitle),
            style: FormTokens.heading.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 20),
          const _IntakeSteps(),
          const SizedBox(height: 28),
          for (final notice in notices) ...[notice, const SizedBox(height: 10)],
          FilledButton.icon(
            onPressed: disabled ? null : onLibrary,
            icon: const Icon(Icons.photo_library_outlined, size: 22),
            label: Text(context.tr(LocaleKeys.intake_library)),
          ),
          const SizedBox(height: FormTokens.gap),
          OutlinedButton.icon(
            onPressed: disabled ? null : onCamera,
            icon: const Icon(Icons.camera_alt_outlined, size: 22),
            label: Text(context.tr(LocaleKeys.intake_camera)),
          ),
          SizedBox(
            height: 30,
            child: Center(
              child: Text(
                context.tr(
                  LocaleKeys.intake_costShort,
                  namedArgs: {'credits': '$shelfImageCreditCost'},
                ),
                style: FormTokens.small.copyWith(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three steps of adding, in the order the next screen walks through.
class _IntakeSteps extends StatelessWidget {
  const _IntakeSteps();

  @override
  Widget build(BuildContext context) {
    final steps = [
      (Icons.photo_library_outlined, LocaleKeys.intake_steps_pick),
      (Icons.auto_awesome_outlined, LocaleKeys.intake_steps_detect),
      (Icons.check_circle_outline, LocaleKeys.intake_steps_add),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, (icon, label)) in steps.indexed) ...[
          Expanded(
            child: FormReveal(
              delay: Duration(milliseconds: 120 + 110 * index),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: FormTokens.selectedTint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 18, color: FormTokens.green),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(label),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FormTokens.small.copyWith(
                      fontSize: 11.5,
                      height: 1.3,
                      color: FormTokens.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// All photos of this session as thumbnails, each showing where it stands.
class _PhotoTray extends StatelessWidget {
  const _PhotoTray({
    required this.drafts,
    required this.currentId,
    required this.keys,
    required this.canAdd,
    required this.onSelect,
    required this.onAdd,
  });

  final List<IntakeDraft> drafts;
  final String currentId;
  final Map<String, GlobalKey> keys;
  final bool canAdd;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  static const size = 54.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: size + 18,
    child: _EdgeFade(
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(FormTokens.gutter, 6, 14, 12),
        children: [
          for (final draft in drafts)
            Padding(
              key: keys.putIfAbsent(draft.id, GlobalKey.new),
              padding: const EdgeInsets.only(right: 8),
              child: FormReveal(
                child: _TrayThumb(
                  draft: draft,
                  active: draft.id == currentId,
                  onTap: () => onSelect(draft.id),
                ),
              ),
            ),
          _AddThumb(onTap: canAdd ? onAdd : null),
        ],
      ),
    ),
  );
}

class _TrayThumb extends StatelessWidget {
  const _TrayThumb({
    required this.draft,
    required this.active,
    required this.onTap,
  });

  final IntakeDraft draft;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final analyzing = _analyzing(draft) && draft.failure == null;
    final leaving = _leaving(draft);
    final selected = draft.choices.where((c) => c.selected).length;
    final badge = draft.failure != null
        ? const _TrayBadge(
            key: ValueKey('failed'),
            color: FormTokens.danger,
            child: Text('!'),
          )
        : leaving
        ? const _TrayBadge(
            key: ValueKey('saved'),
            color: FormTokens.green,
            child: Icon(Icons.check, size: 12, color: Colors.white),
          )
        : draft.phase == DraftPhase.manual
        ? const _TrayBadge(
            key: ValueKey('manual'),
            color: FormTokens.coinRim,
            child: Icon(Icons.edit, size: 11, color: Colors.white),
          )
        : draft.phase == DraftPhase.ready
        ? _TrayBadge(
            key: ValueKey('ready-$selected'),
            color: FormTokens.green,
            child: Text('$selected'),
          )
        : null;
    return Semantics(
      button: true,
      selected: active,
      label: context.tr('intake.phases.${draft.phase.name}'),
      child: GestureDetector(
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        child: AnimatedScale(
          scale: active ? 1 : 0.9,
          duration: FormTokens.quick,
          curve: FormTokens.easeOut,
          child: SizedBox.square(
            dimension: _PhotoTray.size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: FormTokens.quick,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? FormTokens.green : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(draft.filePath),
                            fit: BoxFit.cover,
                            cacheWidth: 160,
                            errorBuilder: (_, _, _) =>
                                const ColoredBox(color: FormTokens.field),
                          ),
                          AnimatedOpacity(
                            opacity: analyzing || leaving ? 1 : 0,
                            duration: FormTokens.sheetDuration,
                            child: ColoredBox(
                              color: leaving
                                  ? FormTokens.green.withValues(alpha: 0.45)
                                  : const Color(0x66263329),
                              child: analyzing ? const _ThumbScan() : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -4,
                  top: -4,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: FormTokens.pop,
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: badge ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft band of light drifting slowly over a thumbnail while its photo
/// is analysed, the small sibling of the photo's scan.
class _ThumbScan extends StatefulWidget {
  const _ThumbScan();

  @override
  State<_ThumbScan> createState() => _ThumbScanState();
}

class _ThumbScanState extends State<_ThumbScan>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _sweep,
    builder: (context, _) {
      final t = Curves.easeInOut.transform(_sweep.value);
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1 + 3 * t - 1, -1),
            end: Alignment(1 + 3 * t - 1, 1),
            colors: const [
              Color(0x00FFFFFF),
              Color(0x59FFFFFF),
              Color(0x00FFFFFF),
            ],
          ),
        ),
      );
    },
  );
}

class _TrayBadge extends StatelessWidget {
  const _TrayBadge({required this.color, required this.child, super.key});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: FormTokens.paper, width: 2),
    ),
    child: DefaultTextStyle(
      style: FormTokens.small
          .copyWith(
            fontSize: 11,
            height: 1,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          )
          .merge(FormTokens.numerals),
      child: child,
    ),
  );
}

class _AddThumb extends StatelessWidget {
  const _AddThumb({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: context.tr(LocaleKeys.intake_more),
    child: GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: SizedBox.square(
          dimension: _PhotoTray.size,
          child: CustomPaint(
            foregroundPainter: const FormDashedBorder(
              color: FormTokens.uploadLine,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: FormTokens.uploadTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add, color: FormTokens.green),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One photo: the picture fills the free space, the strip of pieces below
/// keeps a fixed height whether the photo is still analysed or ready.
class _DraftPage extends StatefulWidget {
  const _DraftPage({
    required this.draft,
    required this.enabled,
    required this.onDiscard,
    required this.onToggle,
    required this.onOwnership,
    super.key,
  });

  final IntakeDraft draft;
  final bool enabled;
  final VoidCallback onDiscard;
  final ValueChanged<IntakeChoice> onToggle;
  final ValueChanged<bool> onOwnership;

  @override
  State<_DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<_DraftPage> {
  String? _focus;
  Timer? _unfocus;

  @override
  void dispose() {
    _unfocus?.cancel();
    super.dispose();
  }

  // Highlights the tapped piece on the photo for a moment, so the photo
  // stays calm otherwise.
  void _toggle(IntakeChoice choice) {
    widget.onToggle(choice);
    _unfocus?.cancel();
    setState(() => _focus = choice.itemKey);
    _unfocus = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _focus = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.draft.phase == DraftPhase.manual) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FormTokens.gutter,
          4,
          FormTokens.gutter,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 220,
              child: _PhotoStage(
                draft: widget.draft,
                focus: _focus,
                onDiscard: widget.onDiscard,
              ),
            ),
            ManualIntakeForm(
              key: ValueKey(widget.draft.id),
              draft: widget.draft,
              enabled: widget.enabled,
            ),
          ],
        ),
      );
    }
    final pieces = _pieces(widget.draft);
    final selected = pieces.where((c) => c.selected).length;
    final ready = widget.draft.phase == DraftPhase.ready;
    final interactive = widget.enabled && ready && widget.draft.failure == null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FormTokens.gutter,
              ),
              child: _PhotoStage(
                draft: widget.draft,
                focus: _focus,
                onDiscard: widget.onDiscard,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FormTokens.gutter),
            child: SizedBox(
              height: 32,
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: FormTokens.quick,
                      layoutBuilder: (current, _) => Align(
                        alignment: Alignment.centerLeft,
                        child: current,
                      ),
                      child: Text(
                        pieces.isEmpty
                            ? context.tr(
                                'intake.phases.${widget.draft.phase.name}',
                              )
                            : context.tr(
                                LocaleKeys.intake_selectedCount,
                                namedArgs: {
                                  'selected': '$selected',
                                  'total': '${pieces.length}',
                                },
                              ),
                        key: ValueKey(
                          pieces.isEmpty ? widget.draft.phase : selected,
                        ),
                        style: FormTokens.small.copyWith(
                          fontWeight: FontWeight.w600,
                          color: FormTokens.ink,
                        ),
                      ),
                    ),
                  ),
                  if (pieces.isNotEmpty)
                    _OwnershipSwitch(
                      owning: widget.draft.ownership == 'owning',
                      onChanged: interactive ? widget.onOwnership : null,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _PieceTile.height,
            child: widget.draft.failure != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FormTokens.gutter,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: FormNotice(
                        text: context.tr(widget.draft.failure!),
                        error: true,
                      ),
                    ),
                  )
                : pieces.isEmpty
                ? const _SkeletonStrip()
                : _EdgeFade(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: FormTokens.gutter,
                      ),
                      itemCount: pieces.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) => FormReveal(
                        key: ValueKey(pieces[index].itemKey),
                        delay: Duration(milliseconds: 160 + 70 * index),
                        child: _PieceTile(
                          draft: widget.draft,
                          choice: pieces[index],
                          onTap: interactive && !pieces[index].locked
                              ? () => _toggle(pieces[index])
                              : null,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The photo fitted into the free space. It stays clean; tapping a piece in
/// the strip spotlights it here for a moment.
class _PhotoStage extends StatelessWidget {
  const _PhotoStage({
    required this.draft,
    required this.onDiscard,
    this.focus,
  });

  final IntakeDraft draft;
  final String? focus;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final analyzing = _analyzing(draft) && draft.failure == null;
    final leaving = _leaving(draft);
    return Center(
      child: AspectRatio(
        aspectRatio: draft.width / draft.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FormTokens.panelRadius),
          child: ColoredBox(
            color: FormTokens.field,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DraftPhoto(draft: draft, focus: focus),
                AnimatedSwitcher(
                  duration: FormTokens.sheetDuration,
                  child: analyzing
                      ? _ScanOverlay(
                          key: const ValueKey('scan'),
                          message: context.tr(
                            draft.phase == DraftPhase.detecting
                                ? LocaleKeys.intake_phases_detecting
                                : LocaleKeys.intake_phases_uploading,
                          ),
                        )
                      : leaving
                      ? _ScanOverlay(
                          key: const ValueKey('saving'),
                          sweep: false,
                          message: context.tr(
                            'intake.phases.${draft.phase.name}',
                          ),
                        )
                      : const SizedBox.expand(),
                ),
                if (!leaving)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _DiscardButton(onPressed: onDiscard),
                  ),
              ],
            ),
          ),
        ),
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
        color: const Color(0xCCFFFFFF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(
              Icons.close,
              size: 18,
              color: FormTokens.ink,
              semanticLabel: label,
            ),
          ),
        ),
      ),
    );
  }
}

/// A band sweeping over the photo while it uploads and is analysed, with
/// the current step in a pill below. Without [sweep] only the pill shows.
class _ScanOverlay extends StatefulWidget {
  const _ScanOverlay({required this.message, this.sweep = true, super.key});

  final String message;
  final bool sweep;

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
    color: widget.sweep ? const Color(0x40263329) : Colors.transparent,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final band = height * 0.35;
        return Stack(
          children: [
            if (widget.sweep)
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

/// Owning or Wanting for every piece of one photo, small enough to share a
/// row with the selection count.
class _OwnershipSwitch extends StatelessWidget {
  const _OwnershipSwitch({required this.owning, required this.onChanged});

  final bool owning;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FormTokens.quick;
    Widget segment(String label, {required bool value}) {
      final active = owning == value;
      return Semantics(
        button: true,
        selected: active,
        enabled: onChanged != null,
        child: GestureDetector(
          onTap: onChanged == null || active
              ? null
              : () {
                  unawaited(HapticFeedback.selectionClick());
                  onChanged!(value);
                },
          child: AnimatedContainer(
            duration: duration,
            curve: FormTokens.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? FormTokens.green : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: FormTokens.small.copyWith(
                fontSize: 12,
                height: 1,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : FormTokens.ink,
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedOpacity(
      opacity: onChanged == null ? 0.55 : 1,
      duration: duration,
      child: Container(
        height: 32,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: FormTokens.field,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(context.tr('collection.owning'), value: true),
            segment(context.tr('collection.wanting'), value: false),
          ],
        ),
      ),
    );
  }
}

/// A detected piece as a large crop. Tapping keeps or leaves it out.
class _PieceTile extends StatelessWidget {
  const _PieceTile({
    required this.draft,
    required this.choice,
    required this.onTap,
  });

  final IntakeDraft draft;
  final IntakeChoice choice;
  final VoidCallback? onTap;

  static const size = 92.0;
  static const double height = size + 26;

  @override
  Widget build(BuildContext context) {
    final selected = choice.selected;
    final leaving = _leaving(draft);
    final proposal = choice.proposal!;
    final colors = FormTokens.category(_detectionTheme(proposal.category));
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FormTokens.quick;
    return Semantics(
      label:
          '${context.tr('categories.${proposal.category}')} · '
          '${proposal.name}',
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                unawaited(HapticFeedback.selectionClick());
                onTap!();
              },
        child: AnimatedOpacity(
          // Pieces left out fade away once the photo is being saved.
          opacity: leaving && !selected ? 0.25 : 1,
          duration: FormTokens.sheetDuration,
          child: SizedBox(
            width: size,
            child: Column(
              children: [
                AnimatedScale(
                  scale: selected ? 1 : 0.92,
                  duration: const Duration(milliseconds: 260),
                  curve: FormTokens.pop,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: FormTokens.easeOut,
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: selected ? colors.tint : FormTokens.field,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? FormTokens.green : FormTokens.line,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      // Concentric with the tile, inside its border.
                      borderRadius: BorderRadius.circular(
                        selected ? 16 - 2.5 : 16 - 1,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedOpacity(
                            opacity: selected ? 1 : 0.45,
                            duration: duration,
                            child: DraftPhoto(
                              draft: draft,
                              crop: proposal.boundingBox,
                              contain: true,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: _CheckBadge(
                              selected: selected,
                              saved: choice.enqueued,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  proposal.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: FormTokens.small.copyWith(
                    fontSize: 11.5,
                    height: 1.4,
                    color: selected ? FormTokens.ink : FormTokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge({required this.selected, required this.saved});

  final bool selected;
  final bool saved;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: FormTokens.quick,
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? FormTokens.green : const Color(0xE6FFFFFF),
      border: Border.all(
        color: selected ? FormTokens.green : FormTokens.toggleOff,
      ),
    ),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: FormTokens.pop,
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: Icon(
        saved
            ? Icons.done_all
            : selected
            ? Icons.check
            : Icons.add,
        key: ValueKey((selected, saved)),
        size: 13,
        color: selected ? Colors.white : FormTokens.muted,
      ),
    ),
  );
}

/// Placeholder tiles while the photo is analysed, at the strip's final
/// height so the page does not move when the pieces arrive.
class _SkeletonStrip extends StatefulWidget {
  const _SkeletonStrip();

  @override
  State<_SkeletonStrip> createState() => _SkeletonStripState();
}

class _SkeletonStripState extends State<_SkeletonStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 0.5;
    } else if (!_pulse.isAnimating) {
      unawaited(_pulse.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: FormTokens.gutter),
    itemCount: 4,
    separatorBuilder: (_, _) => const SizedBox(width: 10),
    itemBuilder: (context, index) => AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        // Each tile runs a little behind the previous one, like a wave.
        final t = (math.sin((_pulse.value - index * 0.18) * math.pi) + 1) / 2;
        return Opacity(
          opacity: 0.45 + 0.55 * t,
          child: Column(
            children: [
              Container(
                width: _PieceTile.size,
                height: _PieceTile.size,
                decoration: BoxDecoration(
                  color: FormTokens.field,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: _PieceTile.size * 0.6,
                height: 8,
                decoration: BoxDecoration(
                  color: FormTokens.field,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// The one decision per photo, pinned to the bottom.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.draft,
    required this.enabled,
    required this.bottom,
    required this.nextReady,
    required this.onSave,
    required this.onRetry,
    required this.onNext,
  });

  final IntakeDraft draft;
  final bool enabled;
  final double bottom;
  final IntakeDraft? nextReady;
  final VoidCallback onSave;
  final VoidCallback onRetry;
  final ValueChanged<String> onNext;

  @override
  Widget build(BuildContext context) {
    final count = draft.choices.where((c) => c.selected && !c.enqueued).length;
    final Widget button;
    final String note;
    if (draft.failure != null) {
      button = FilledButton(
        onPressed: enabled ? onRetry : null,
        child: Text(context.tr(LocaleKeys.retry)),
      );
      note = '';
    } else if (draft.phase == DraftPhase.ready) {
      final credits = count * shelfImageCreditCost;
      button = FilledButton(
        onPressed: enabled && count > 0 ? onSave : null,
        child: Text(
          count == 0
              ? context.tr(LocaleKeys.intake_addNone)
              : context.tr(
                  count == 1
                      ? LocaleKeys.intake_addOne
                      : LocaleKeys.intake_addMany,
                  namedArgs: {'count': '$count'},
                ),
        ),
      );
      note = count == 0
          ? ''
          : context.tr(
              count == 1
                  ? LocaleKeys.intake_costOne
                  : LocaleKeys.intake_costMany,
              namedArgs: {'count': '$count', 'credits': '$credits'},
            );
    } else if (_leaving(draft)) {
      button = FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check, size: 20),
        label: Text(context.tr('intake.phases.${draft.phase.name}')),
      );
      note = context.tr(LocaleKeys.intake_background);
    } else if (nextReady != null) {
      button = OutlinedButton.icon(
        onPressed: () => onNext(nextReady!.id),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_forward, size: 20),
        label: Text(context.tr(LocaleKeys.intake_nextReady)),
      );
      note = context.tr(LocaleKeys.intake_detectionFree);
    } else {
      button = FilledButton(
        onPressed: null,
        child: Text(context.tr('intake.phases.${draft.phase.name}')),
      );
      note = context.tr(LocaleKeys.intake_detectionFree);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FormTokens.gutter,
        14,
        FormTokens.gutter,
        bottom + 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: FormTokens.quick,
            // Passes the bar's full width on to the button.
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.passthrough,
              children: [...previous, ?current],
            ),
            child: KeyedSubtree(
              key: ValueKey(
                '${draft.id}-${draft.phase}-${draft.failure}-'
                '${nextReady != null}',
              ),
              child: button,
            ),
          ),
          SizedBox(
            height: 24,
            child: Center(
              child: Text(
                note,
                style: FormTokens.small.copyWith(fontSize: 11),
              ),
            ),
          ),
        ],
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

String _detectionTheme(String category) {
  if (['top', 'jacket', 'coat', 'dress'].contains(category)) return 'top';
  if (['pants', 'skirt'].contains(category)) return 'bottom';
  if (category == 'shoes') return 'shoes';
  return 'accessory';
}

/// Both preview crops and the spotlight use the prepared photo's pixel
/// geometry. The whole draft photo with an optional spotlight, or with [crop]
/// a single detection. A crop covers its box so the parent's rounded clip
/// shapes every corner, or with [contain] shows the whole piece.
class DraftPhoto extends StatelessWidget {
  const DraftPhoto({
    required this.draft,
    this.crop,
    this.contain = false,
    this.focus,
    super.key,
  });
  final IntakeDraft draft;
  final DetectionBox? crop;
  final bool contain;

  /// Item key of the piece to highlight on the whole photo.
  final String? focus;
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
          final fit = contain ? math.min : math.max;
          final scale = fit(
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
    final focused = draft.choices
        .where((c) => c.itemKey == focus && c.proposal != null)
        .firstOrNull;
    return Center(
      child: AspectRatio(
        aspectRatio: source.width / source.height,
        child: LayoutBuilder(
          builder: (context, constraints) => ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                _Spotlight(
                  rect: focused?.proposal!.boundingBox.pixels(
                    constraints.biggest,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dims the photo around one piece. Moves between pieces and fades out
/// once [rect] is null.
class _Spotlight extends StatefulWidget {
  const _Spotlight({required this.rect});

  final Rect? rect;

  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> {
  late Rect? _last = widget.rect;

  @override
  void didUpdateWidget(_Spotlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    _last = widget.rect ?? _last;
  }

  @override
  Widget build(BuildContext context) {
    final last = _last;
    final still = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.rect == null ? 0 : 1,
        duration: still ? Duration.zero : FormTokens.sheetDuration,
        curve: FormTokens.easeOut,
        child: last == null
            ? const SizedBox.expand()
            : TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: last),
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                curve: FormTokens.easeOut,
                builder: (context, rect, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _SpotlightPainter(rect!),
                ),
              ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      rect.inflate(6),
      const Radius.circular(14),
    );
    canvas
      ..drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addRRect(hole),
        ),
        Paint()..color = const Color(0x8C263329),
      )
      ..drawRRect(
        hole,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) => oldDelegate.rect != rect;
}

/// Fades the ends of a horizontal list where more content is scrolled away.
class _EdgeFade extends StatefulWidget {
  const _EdgeFade({required this.child});

  final Widget child;

  @override
  State<_EdgeFade> createState() => _EdgeFadeState();
}

class _EdgeFadeState extends State<_EdgeFade> {
  static const _width = 28.0;
  bool _start = false;
  bool _end = false;

  bool _update(ScrollMetrics metrics) {
    final start = metrics.pixels > metrics.minScrollExtent + 1;
    final end = metrics.pixels < metrics.maxScrollExtent - 1;
    if (start != _start || end != _end) {
      setState(() {
        _start = start;
        _end = end;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _update(n.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _update(n.metrics),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final stop = _width / bounds.width;
              return LinearGradient(
                colors: [
                  if (_start) Colors.transparent else Colors.white,
                  Colors.white,
                  Colors.white,
                  if (_end) Colors.transparent else Colors.white,
                ],
                stops: [0, stop, 1 - stop, 1],
              ).createShader(bounds);
            },
            child: widget.child,
          ),
        ),
      );
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
