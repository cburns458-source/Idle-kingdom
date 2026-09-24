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

/// Left (player) foot in 360×480 design space.
///
/// The 1440×1920 foliage ellipse is 428–683 × 1548–1643 (÷4). The foot sits a
/// few art pixels below the ellipse center, on the lower-middle of the oval.
const Offset templePlayerFootDesign = Offset(138.875, 404.8125);

/// Right (action / enemy) foot in 360×480 design space.
///
/// Foliage ellipse 764–1015 × 1544–1643 (÷4); same lower-middle sit as the player.
const Offset templeActionFootDesign = Offset(222.375, 404.5625);

/// Night sky sampled from the top of the sky layer, for any gap above the plate.
const Color templeSkyFill = Color(0xFF14163B);

/// Portrait box whose bottom-center sits on a shadow ellipse.
const double templePortraitWidth = 152;

/// 256×256 gathering sheets keep ~43px of empty canvas under the plant; player
/// sprites only have ~11px. Drop the right-side box by this many logical pixels
/// so the drawn bottom sits on the same ellipse line as the adventurer.
const double templeActionGroundNudge = 152 * 43 / 256 - 137 * 11 / 256;

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

  /// Widget-bottom for right-side art after the empty-canvas drop.
  Offset get actionStand => Offset(actionFoot.dx, actionFoot.dy + templeActionGroundNudge);
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
