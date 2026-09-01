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
class UiChrome {
  const UiChrome({
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

  static const wood = UiChrome(
    pack: UiChromePack.wood,
    label: 'Wood',
    board: Color(0xFF2A1C12),
    panel: Color(0xFFC4A882),
    slot: Color(0xFF3D2A1A),
    panelInk: Color(0xFF2A1C12),
    panelMuted: Color(0xFF6B5338),
    boardTextureAsset: 'assets/ui/wood-panel.png',
    panelTextureAsset: 'assets/ui/panel-tan.png',
    shellGradient: LinearGradient(
      begin: Alignment(-0.6, -1),
      end: Alignment(0.6, 1),
      colors: [Color(0xFF1A120C), Color(0xFF2A1C12), Color(0xFF14100A)],
      stops: [0, 0.45, 1],
    ),
    frameGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF3D2A1A), Color(0xFF2A1C12)],
    ),
  );

  static const stone = UiChrome(
    pack: UiChromePack.stone,
    label: 'Stone',
    board: Color(0xFF2A2C30),
    panel: Color(0xFFB8B4A8),
    slot: Color(0xFF3A3C42),
    panelInk: Color(0xFF1E2024),
    panelMuted: Color(0xFF5A5E66),
    boardTextureAsset: 'assets/ui/stone-panel.png',
    panelTextureAsset: 'assets/ui/panel-ash.png',
    shellGradient: LinearGradient(
      begin: Alignment(-0.6, -1),
      end: Alignment(0.6, 1),
      colors: [Color(0xFF181A1E), Color(0xFF2A2C30), Color(0xFF121418)],
      stops: [0, 0.45, 1],
    ),
    frameGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF3A3C42), Color(0xFF2A2C30)],
    ),
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
