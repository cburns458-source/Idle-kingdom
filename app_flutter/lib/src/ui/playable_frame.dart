import 'package:flutter/painting.dart';

/// Widest the playable column may get on a phone-shaped window.
const double playableFrameMaxWidth = 420;

/// Width / height of a phone column.
const double playableFrameAspect = 9 / 16;

/// Leftover width after a 9:16 column that is enough for side chat.
const double playableFrameSideChatMinLeftover = 300;

/// Skip side chat on short windows (including the 800×600 widget-test surface).
const double playableFrameSideChatMinWidth = 1100;

/// Menus and location copy sit ~10% smaller than HUD and combat numbers.
const double playableUiTextScale = 0.9;

double _textScaleFactor(TextScaler scaler) => scaler.scale(100) / 100;

/// Apply [playableUiTextScale] on top of the ambient scaler.
TextScaler playableUiTextScaler(TextScaler parent) =>
    TextScaler.linear(_textScaleFactor(parent) * playableUiTextScale);

/// Undo [playableUiTextScale] so HUD and combat numbers stay full size.
TextScaler playableHudTextScaler(TextScaler parent) =>
    TextScaler.linear(_textScaleFactor(parent) / playableUiTextScale);

/// True when the window can keep a full-height 9:16 column and still fit chat.
bool playableFrameHasSideChat(Size available) {
  if (available.isEmpty || available.width < playableFrameSideChatMinWidth) {
    return false;
  }
  final column = available.height * playableFrameAspect;
  if (column > available.width) return false;
  return available.width - column >= playableFrameSideChatMinLeftover;
}

/// The size of the parchment frame inside [available].
///
/// Phones keep their full height. When leftover width after a 9:16 column is
/// at least [playableFrameSideChatMinLeftover], the column is that 9:16 box at
/// the window height. Narrower windows keep the 420 cap so maps stay portrait.
Size playableFrameSize(Size available) {
  if (available.isEmpty) return available;
  if (playableFrameHasSideChat(available)) {
    return Size(available.height * playableFrameAspect, available.height);
  }
  final byAspect = available.height * playableFrameAspect;
  final width = [playableFrameMaxWidth, available.width, byAspect].reduce((a, b) => a < b ? a : b);
  var height = available.height;
  if (available.width > available.height) {
    final byWidth = width / playableFrameAspect;
    if (byWidth < height) height = byWidth;
  }
  return Size(width, height);
}
