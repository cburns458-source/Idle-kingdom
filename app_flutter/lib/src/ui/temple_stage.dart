import 'package:flutter/material.dart';

import '../content/asset_paths.dart';
import 'game_image.dart';

/// The Temple (LOC-0036) is the first node on the layered 360-wide plate.
const String templeLocationId = 'LOC-0036';

bool usesTempleLayeredBackground(String locationId) => locationId == templeLocationId;

/// Authored width of the stacked PNGs, in art pixels.
const double templeDesignWidth = 360;

/// Authored height of the stacked PNGs, in art pixels.
const double templeDesignHeight = 480;

/// How many of those 360 art pixels stay in view (centered).
const double templeViewWidth = 320;

/// Crop from each side of the 360-wide plate so 320 art pixels fill the stage.
const double templeViewCrop = (templeDesignWidth - templeViewWidth) / 2;

/// Left (player) ellipse center in 360×480 design space.
///
/// Measured from the 1440×1920 foliage PNG (4×).
const Offset templePlayerFootDesign = Offset(138.875, 398.875);

/// Right (action / enemy) ellipse center in 360×480 design space.
const Offset templeActionFootDesign = Offset(222.375, 398.375);

/// Night sky sampled from the top of the sky layer, for any gap above the plate.
const Color templeSkyFill = Color(0xFF14163B);

/// Portrait box whose bottom-center sits on a shadow ellipse.
const double templePortraitWidth = 152;

class TempleStageLayout {
  const TempleStageLayout(this.stageSize);

  final Size stageSize;

  /// One art pixel → this many logical pixels. 320 art pixels span [stageSize.width].
  double get scale => stageSize.width / templeViewWidth;

  Offset toStage(Offset design) {
    return Offset(
      (design.dx - templeViewCrop) * scale,
      stageSize.height - (templeDesignHeight - design.dy) * scale,
    );
  }

  Offset get playerFoot => toStage(templePlayerFootDesign);

  Offset get actionFoot => toStage(templeActionFootDesign);
}

/// Sky, terrain, and foliage stacked at the same size, clipped to the 320 view.
class TempleLayeredBackdrop extends StatelessWidget {
  const TempleLayeredBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = TempleStageLayout(Size(constraints.maxWidth, constraints.maxHeight));
        final artSize = Size(templeDesignWidth * layout.scale, templeDesignHeight * layout.scale);
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: templeSkyFill),
              Align(
                alignment: Alignment.bottomCenter,
                child: OverflowBox(
                  maxWidth: artSize.width,
                  maxHeight: artSize.height,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: artSize.width,
                    height: artSize.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GameImage(
                          templeSkyAssetPath(),
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.none,
                        ),
                        GameImage(
                          templeTerrainAssetPath(),
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.none,
                        ),
                        GameImage(
                          templeForegroundAssetPath(),
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.none,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
