import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum FormIconName { feed, closet, settings }

class FormIcon extends StatelessWidget {
  const FormIcon(this.name, {this.size = 23, this.color, super.key});
  final FormIconName name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/${name.name}.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: ColorFilter.mode(
      color ?? IconTheme.of(context).color ?? Colors.black,
      BlendMode.srcIn,
    ),
  );
}
