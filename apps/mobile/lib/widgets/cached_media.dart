import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/repository/media_repository.dart';

/// How a loaded image appears on screen.
enum MediaEntrance {
  none,
  fade,
  shelf,
}

class CachedMedia extends StatefulWidget {
  const CachedMedia({
    required this.identity,
    required this.online,
    this.previewPath,
    this.fit = BoxFit.contain,
    this.entrance = MediaEntrance.none,
    super.key,
  });
  final String identity;
  final String? previewPath;
  final bool online;
  final BoxFit fit;
  final MediaEntrance entrance;
  @override
  State<CachedMedia> createState() => _CachedMediaState();
}

class _CachedMediaState extends State<CachedMedia>
    with SingleTickerProviderStateMixin {
  late Future<File?> _file;
  late final AnimationController _controller;
  bool _played = false;

  Duration get _duration => Duration(
    milliseconds: widget.entrance == MediaEntrance.shelf ? 520 : 320,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _load();
  }

  @override
  void didUpdateWidget(CachedMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _duration;
    if (oldWidget.identity != widget.identity) {
      _controller.value = 0;
      _played = false;
      _load();
    } else if (oldWidget.online != widget.online) {
      // Same image: the new future resolves to the same cached file, which
      // stays on screen meanwhile, so the entrance must not replay.
      _load();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _load() {
    _file = context.read<MediaRepository>().load(
      widget.identity,
      previewPath: widget.previewPath,
      online: widget.online,
    );
  }

  /// Plays the entrance once the first frame is decoded, so the animation
  /// never runs over an empty image.
  void _startEntrance() {
    if (_played) return;
    _played = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.forward());
    });
  }

  Widget _placeholder() => const ColoredBox(color: FormTokens.field);

  Widget _wrapEntrance(Widget child) {
    final entrance = widget.entrance;
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (context, child) {
        final t = FormTokens.easeOut.transform(_controller.value);
        if (entrance == MediaEntrance.fade) {
          return Opacity(opacity: t, child: child);
        }
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snapshot) {
      if (snapshot.data == null) return _placeholder();
      return Image.file(
        snapshot.data!,
        fit: widget.fit,
        gaplessPlayback: true,
        frameBuilder: widget.entrance == MediaEntrance.none
            ? null
            : (context, child, frame, _) {
                if (frame == null && !_played) return _placeholder();
                _startEntrance();
                return _wrapEntrance(child);
              },
        errorBuilder: (_, _, _) =>
            const Icon(Icons.image_not_supported_outlined),
      );
    },
  );
}

/// Status bar style for the cached image [identity]: light icons while a dark
/// image sits under the status bar, dark ones otherwise. Flutter reads the
/// region under the status bar every frame, so the icons follow the scroll.
/// The page needs no fixed style of its own on top, see
/// `FormScrollEdge.adaptive`.
class MediaStatusBarRegion extends StatefulWidget {
  const MediaStatusBarRegion({
    required this.identity,
    required this.online,
    required this.child,
    this.previewPath,
    this.enabled = true,
    super.key,
  });
  final String identity;
  final String? previewPath;
  final bool online;
  final Widget child;

  /// Off while the image is hidden, e.g. faded out behind another view.
  final bool enabled;

  @override
  State<MediaStatusBarRegion> createState() => _MediaStatusBarRegionState();
}

class _MediaStatusBarRegionState extends State<MediaStatusBarRegion> {
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  @override
  void didUpdateWidget(MediaStatusBarRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) unawaited(_measure());
  }

  Future<void> _measure() async {
    final file = await context.read<MediaRepository>().load(
      widget.identity,
      previewPath: widget.previewPath,
      online: widget.online,
    );
    final dark = file != null && await _isDark(file);
    if (mounted && dark != _dark) setState(() => _dark = dark);
  }

  // Always wraps the child, so a result arriving never rebuilds the image.
  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: _dark && widget.enabled
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: widget.child,
  );
}

/// Brightness per image file, measured once per app run.
final _darkImages = <String, Future<bool>>{};

/// Whether the image's average luminance is dark enough for light status bar
/// icons. Decodes a 24 px wide copy, so it stays cheap.
Future<bool> _isDark(File file) => _darkImages.putIfAbsent(file.path, () async {
  try {
    final codec = await ui.instantiateImageCodec(
      await file.readAsBytes(),
      targetWidth: 24,
    );
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData();
    image.dispose();
    codec.dispose();
    if (data == null) return false;
    var sum = 0.0;
    final pixels = data.lengthInBytes ~/ 4;
    for (var i = 0; i < pixels; i++) {
      sum +=
          0.2126 * data.getUint8(i * 4) +
          0.7152 * data.getUint8(i * 4 + 1) +
          0.0722 * data.getUint8(i * 4 + 2);
    }
    return sum / pixels / 255 < 0.5;
  } on Exception {
    return false;
  }
});
