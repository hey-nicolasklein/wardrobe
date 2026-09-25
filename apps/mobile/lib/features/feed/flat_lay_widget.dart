import 'package:flutter/material.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/flat_lay_layout.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';

class FlatLayBoard extends StatelessWidget {
  const FlatLayBoard({
    required this.garments,
    required this.online,
    this.onGarmentTap,
    this.selectedId,
    super.key,
  });

  final List<LookGarment> garments;
  final bool online;
  final ValueChanged<String>? onGarmentTap;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final items = garments
        .where((garment) => garment.item != null)
        .map((garment) => garment.item!)
        .toList();
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final layout = flatLayLayout(items);
    return AspectRatio(
      aspectRatio: 100 / 125,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final placement in layout)
                () {
                  final garment = garments.firstWhere(
                    (entry) => entry.id == placement.item.id,
                  );
                  final size = placement.size / 100 * width;
                  final left = placement.x / 100 * width - size / 2;
                  final top = placement.y / 125 * height - size / 2;
                  final child = garment.available
                      ? CachedMedia(
                          identity: garment.item!.previewIdentity,
                          previewPath: garment.item!.previewPath,
                          online: online,
                        )
                      : Center(
                          child: Text(
                            garment.item?.metadata.name ?? garment.id,
                            textAlign: TextAlign.center,
                            style: FormTokens.small,
                          ),
                        );
                  return Positioned(
                    left: left,
                    top: top,
                    width: size,
                    height: size,
                    child: Transform.rotate(
                      angle: placement.angle * 3.1415926535 / 180,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onGarmentTap == null || !garment.available
                              ? null
                              : () => onGarmentTap!(garment.id),
                          customBorder: const CircleBorder(),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: selectedId == garment.id
                                  ? Border.all(
                                      color: FormTokens.green,
                                      width: 2,
                                    )
                                  : null,
                              shape: BoxShape.circle,
                            ),
                            child: ClipOval(child: child),
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          );
        },
      ),
    );
  }
}
