import 'package:flutter/material.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// Selectable outer/inner UI chrome packs (presentation only).
enum UiChromePack {
  /// Current warm boards + tan panels.
  wood,

  /// Cool grey boards + ash panels.
  stone,
}

/// Colors and textures for one [UiChromePack].
///
/// Pack instances are long-lived singletons so [DecorationImage]s can be cached
/// and reused across rebuilds without reallocating [AssetImage]s every frame.
class UiChrome {
  UiChrome({
    required this.pack,
    required this.label,
    required this.board,
    required this.panel,
    required this.slot,
    required this.panelInk,
    required this.panelMuted,
    required this.boardTextureAsset,
    required this.panelTextureAsset,
    required this.shellGradient,
    required this.frameGradient,
    required this.primaryFill,
    required this.primaryPressed,
    required this.secondaryFill,
    required this.secondaryPressed,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.iconButtonFill,
    required this.embossFace,
    required this.embossHighlight,
    required this.embossShade,
    required this.embossFaceSelected,
    required this.embossHighlightSelected,
    required this.embossShadeSelected,
    required this.rivetFill,
    required this.rivetShade,
  });

  final UiChromePack pack;
  final String label;
  final Color board;
  final Color panel;
  final Color slot;
  final Color panelInk;
  final Color panelMuted;
  final String boardTextureAsset;
  final String panelTextureAsset;
  final LinearGradient shellGradient;
  final LinearGradient frameGradient;
  final LinearGradient primaryFill;
  final LinearGradient primaryPressed;
  final LinearGradient secondaryFill;
  final LinearGradient secondaryPressed;
  final Color primaryLabel;
  final Color secondaryLabel;
  final Color iconButtonFill;
  final Color embossFace;
  final Color embossHighlight;
  final Color embossShade;
  final Color embossFaceSelected;
  final Color embossHighlightSelected;
  final Color embossShadeSelected;
  final Color rivetFill;
  final Color rivetShade;

  DecorationImage? _boardFill55;
  DecorationImage? _boardFill40;
  DecorationImage? _boardPlate45;
  DecorationImage? _panelPlate32;
  BoxDecoration? _shellDecoration;
  BoxDecoration? _frameDecoration;

  static final wood = UiChrome(
    pack: UiChromePack.wood,
    label: 'Wood',
    board: const Color(0xFF2A1C12),
    panel: const Color(0xFFC4A882),
    slot: const Color(0xFF3D2A1A),
    panelInk: const Color(0xFF2A1C12),
    panelMuted: const Color(0xFF6B5338),
    boardTextureAsset: 'assets/ui/wood-panel.png',
    panelTextureAsset: 'assets/ui/panel-tan.png',
    shellGradient: const LinearGradient(
      begin: Alignment(-0.6, -1),
      end: Alignment(0.6, 1),
      colors: [Color(0xFF1A120C), Color(0xFF2A1C12), Color(0xFF14100A)],
      stops: [0, 0.45, 1],
    ),
    frameGradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF3D2A1A), Color(0xFF2A1C12)],
    ),
    primaryFill: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF8B5E34), Color(0xFF5E3D22)],
    ),
    primaryPressed: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF6E4A28), Color(0xFF3F2A16)],
    ),
    secondaryFill: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF6A4A30), Color(0xFF45301F)],
    ),
    secondaryPressed: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF4A3422), Color(0xFF2F2115)],
    ),
    primaryLabel: const Color(0xFFFFF6E4),
    secondaryLabel: const Color(0xFFFFF4D4),
    iconButtonFill: const Color(0xFF45301F),
    embossFace: const Color(0xFF7A5F24),
    embossHighlight: const Color(0xFF7A6434),
    embossShade: const Color(0xFF3A2A0C),
    embossFaceSelected: const Color(0xFF967A32),
    embossHighlightSelected: const Color(0xFF968040),
    embossShadeSelected: const Color(0xFF3A2A0A),
    rivetFill: const Color(0xFF8A6B28),
    rivetShade: const Color(0xFF3F2E0C),
  );

  static final stone = UiChrome(
    pack: UiChromePack.stone,
    label: 'Stone',
    board: const Color(0xFF2A2C30),
    panel: const Color(0xFFB8B4A8),
    slot: const Color(0xFF3A3C42),
    panelInk: const Color(0xFF1E2024),
    panelMuted: const Color(0xFF5A5E66),
    boardTextureAsset: 'assets/ui/stone-panel.png',
    panelTextureAsset: 'assets/ui/panel-ash.png',
    shellGradient: const LinearGradient(
      begin: Alignment(-0.6, -1),
      end: Alignment(0.6, 1),
      colors: [Color(0xFF181A1E), Color(0xFF2A2C30), Color(0xFF121418)],
      stops: [0, 0.45, 1],
    ),
    frameGradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF3A3C42), Color(0xFF2A2C30)],
    ),
    primaryFill: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF6A6E78), Color(0xFF4A4E56)],
    ),
    primaryPressed: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF52565E), Color(0xFF363A42)],
    ),
    secondaryFill: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF4A4E56), Color(0xFF32363C)],
    ),
    secondaryPressed: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF363A40), Color(0xFF22262C)],
    ),
    primaryLabel: const Color(0xFFF2F0EA),
    secondaryLabel: const Color(0xFFE8E6E0),
    iconButtonFill: const Color(0xFF32363C),
    embossFace: const Color(0xFF4A4E56),
    embossHighlight: const Color(0xFF5A5E66),
    embossShade: const Color(0xFF141618),
    embossFaceSelected: const Color(0xFF6A6E78),
    embossHighlightSelected: const Color(0xFF7A7E86),
    embossShadeSelected: const Color(0xFF0A0C0E),
    rivetFill: const Color(0xFF5A5E66),
    rivetShade: const Color(0xFF1A1C20),
  );

  static UiChrome forPack(UiChromePack pack) => switch (pack) {
    UiChromePack.wood => wood,
    UiChromePack.stone => stone,
  };

  /// Looks up the active pack from [UiChromeScope], defaulting to wood.
  static UiChrome of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiChromeScope>();
    return scope?.chrome ?? wood;
  }

  DecorationImage _boardImage(double opacity) => DecorationImage(
    image: AssetImage(boardTextureAsset),
    repeat: ImageRepeat.repeat,
    fit: BoxFit.none,
    alignment: Alignment.topLeft,
    filterQuality: FilterQuality.none,
    opacity: opacity,
  );

  /// Tiled board texture for HUD / nav / popup fills.
  DecorationImage boardFillImage({double opacity = 0.55}) {
    if (opacity == 0.55) return _boardFill55 ??= _boardImage(0.55);
    if (opacity == 0.4) return _boardFill40 ??= _boardImage(0.4);
    if (opacity == 0.45) return _boardPlate45 ??= _boardImage(0.45);
    return _boardImage(opacity);
  }

  /// Tiled inner-panel texture for [PixelPlate] tan plates.
  DecorationImage panelPlateImage({double opacity = 0.32}) {
    if (opacity == 0.32) {
      return _panelPlate32 ??= DecorationImage(
        image: AssetImage(panelTextureAsset),
        repeat: ImageRepeat.repeat,
        fit: BoxFit.none,
        alignment: Alignment.topLeft,
        filterQuality: FilterQuality.none,
        opacity: 0.32,
      );
    }
    return DecorationImage(
      image: AssetImage(panelTextureAsset),
      repeat: ImageRepeat.repeat,
      fit: BoxFit.none,
      alignment: Alignment.topLeft,
      filterQuality: FilterQuality.none,
      opacity: opacity,
    );
  }

  /// Full shell wash (default gradient). Custom [gradient] still reuses the image.
  BoxDecoration shellDecoration({Gradient? gradient}) {
    if (gradient == null) {
      return _shellDecoration ??= BoxDecoration(
        color: board,
        gradient: shellGradient,
        image: boardFillImage(),
      );
    }
    if (identical(gradient, frameGradient)) {
      return _frameDecoration ??= BoxDecoration(
        color: board,
        gradient: frameGradient,
        image: boardFillImage(),
      );
    }
    return BoxDecoration(color: board, gradient: gradient, image: boardFillImage());
  }

  /// Board fill with optional border / radius (image is pack-cached).
  BoxDecoration boardFill({
    BorderRadius? borderRadius,
    BoxBorder? border,
    double textureOpacity = 0.55,
  }) {
    return BoxDecoration(
      color: board,
      borderRadius: borderRadius,
      border: border,
      image: boardFillImage(opacity: textureOpacity),
    );
  }
}

/// Provides the active [UiChrome] to the widget subtree.
class UiChromeScope extends InheritedWidget {
  const UiChromeScope({super.key, required this.chrome, required super.child});

  final UiChrome chrome;

  @override
  bool updateShouldNotify(UiChromeScope oldWidget) => oldWidget.chrome.pack != chrome.pack;
}

/// Client-only preference for which UI chrome pack is drawn.
///
/// Kept off the exportable save — presentation only, like map-travel animation.
class UiChromePref {
  UiChromePref({this.storage, UiChromePack? pack}) : _pack = pack ?? UiChromePack.wood;

  static const String storageKey = 'idle-kingdoms.client.ui-chrome-pack';

  final SaveStorage? storage;
  UiChromePack _pack;

  UiChromePack get pack => _pack;

  UiChrome get chrome => UiChrome.forPack(_pack);

  factory UiChromePref.load(SaveStorage? storage) {
    final stored = storage?.getItem(storageKey);
    if (stored == 'stone') {
      return UiChromePref(storage: storage, pack: UiChromePack.stone);
    }
    return UiChromePref(storage: storage, pack: UiChromePack.wood);
  }

  void setPack(UiChromePack value) {
    _pack = value;
    storage?.setItem(storageKey, value == UiChromePack.stone ? 'stone' : 'wood');
  }
}
