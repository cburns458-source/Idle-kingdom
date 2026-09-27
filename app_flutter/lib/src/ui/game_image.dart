import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Largest decoded edge GameImage will ask the codec for, in physical pixels.
///
/// iOS Safari's WebGL budget cannot hold a paper doll of 2000×2000 slot
/// glyphs; each one is ~16MB uncompressed. Inventory icons never need more
/// than this on a phone.
const int gameImageMaxDecodePx = 2048;

/// Physical pixel size to decode [logical] at, or null when the layout size
/// is unknown. Caps at [gameImageMaxDecodePx] so a missing width on a huge
/// asset cannot allocate a 2000×2000 bitmap.
int? gameImageDecodePx(double? logical, double devicePixelRatio) {
  if (logical == null || !logical.isFinite || logical <= 0) return null;
  final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1.0;
  return (logical * dpr).round().clamp(1, gameImageMaxDecodePx);
}

/// Game art that still paints when the Flutter web bundle lookup misses a file.
///
/// [Image.asset] is tried first so tests and native builds keep using the
/// bundle. On web, a miss falls back to the same path under `/assets/`, which
/// is how the static host already serves these files.
///
/// Decode size follows the painted size. Several HUD and paper-doll icons
/// shipped as ~2000×2000 WebPs; decoding those at full resolution when the
/// inventory opened was enough to black-screen iOS Safari.
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
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final knownW = gameImageDecodePx(width, dpr);
    final knownH = gameImageDecodePx(height, dpr);
    if (knownW != null || knownH != null || width != null || height != null) {
      return _image(cacheWidth: knownW, cacheHeight: knownH);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalW = constraints.hasBoundedWidth ? constraints.maxWidth : null;
        final logicalH = constraints.hasBoundedHeight ? constraints.maxHeight : null;
        return _image(
          cacheWidth: gameImageDecodePx(logicalW, dpr),
          cacheHeight: gameImageDecodePx(logicalH, dpr),
        );
      },
    );
  }

  Widget _image({required int? cacheWidth, required int? cacheHeight}) {
    return Image.asset(
      path,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
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
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
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
