import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Game art that still paints when the Flutter web bundle lookup misses a file.
///
/// [Image.asset] is tried first so tests and native builds keep using the
/// bundle. On web, a miss falls back to the same path under `/assets/`, which
/// is how the static host already serves these files.
class GameImage extends StatelessWidget {
  const GameImage(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.none,
    this.gaplessPlayback = false,
  });

  final String path;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: (context, error, stack) {
        if (kIsWeb) {
          return Image.network(
            'assets/$path',
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            filterQuality: filterQuality,
            gaplessPlayback: gaplessPlayback,
            errorBuilder: (context, error, stack) => _placeholder(),
          );
        }
        return _placeholder();
      },
    );
  }

  Widget _placeholder() {
    return SizedBox(width: width, height: height);
  }
}
