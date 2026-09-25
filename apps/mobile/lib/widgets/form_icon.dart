import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icons copied from the PWA's `icons` map in `app.js`. `heartFilled` and
/// `bookmarkFilled` are the pressed look-action states.
enum FormIconName {
  feed('feed'),
  closet('closet'),
  settings('settings'),
  shuffle('shuffle'),
  moon('moon'),
  party('party'),
  top('top'),
  check('check'),
  filter('filter'),
  arrow('arrow'),
  heart('heart'),
  heartFilled('heart-filled'),
  share('share'),
  bookmark('bookmark'),
  bookmarkFilled('bookmark-filled'),
  more('more'),
  person('person'),
  photo('photo'),
  close('close');

  const FormIconName(this.file);
  final String file;
}

class FormIcon extends StatelessWidget {
  const FormIcon(this.name, {this.size = 23, this.color, super.key});
  final FormIconName name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/${name.file}.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: ColorFilter.mode(
      color ?? IconTheme.of(context).color ?? Colors.black,
      BlendMode.srcIn,
    ),
  );
}
