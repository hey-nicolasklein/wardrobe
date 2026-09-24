import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/repository/media_repository.dart';

class CachedMedia extends StatefulWidget {
  const CachedMedia({
    required this.identity,
    required this.online,
    this.previewPath,
    super.key,
  });
  final String identity;
  final String? previewPath;
  final bool online;
  @override
  State<CachedMedia> createState() => _CachedMediaState();
}

class _CachedMediaState extends State<CachedMedia> {
  late Future<File?> _file;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CachedMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.online != widget.online) {
      _load();
    }
  }

  void _load() {
    _file = context.read<MediaRepository>().load(
      widget.identity,
      previewPath: widget.previewPath,
      online: widget.online,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snapshot) => snapshot.data == null
        ? const Center(child: Icon(Icons.checkroom_outlined, size: 48))
        : Image.file(
            snapshot.data!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.image_not_supported_outlined),
          ),
  );
}
