import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
      if (mounted) _controller.forward();
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
