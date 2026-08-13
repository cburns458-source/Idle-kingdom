import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';

/// The local player figure: a custom PNG when this device has one, else the
/// bundled gender-presentation sprite.
class PlayerSprite extends StatelessWidget {
  const PlayerSprite({
    super.key,
    required this.appearance,
    this.bytes,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.none,
  });

  final PlayerAppearance? appearance;
  final Uint8List? bytes;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return Image.memory(
        bytes!,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
      );
    }
    return Image.asset(
      playerAssetPath(appearance),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
    );
  }
}
