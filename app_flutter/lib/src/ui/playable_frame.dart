import 'dart:ui';

/// Widest the playable column may get. Wider windows keep this so maps stay
/// portrait and do not need huge empty margins.
const double playableFrameMaxWidth = 420;

/// Width / height of a phone column. Used only to stop a short wide window
/// from stretching the frame into a landscape strip.
const double playableFrameAspect = 9 / 16;

/// The size of the parchment frame inside [available].
///
/// Phones keep their full height. Wide desktops are capped at
/// [playableFrameMaxWidth]. A short wide window is narrowed further so the
/// column stays at least as tall as a 9:16 phone. Landscape windows also cap
/// height to that same 9:16 so the desktop game is a phone, not a tall strip.
/// Portrait windows never shrink height — widget tests use a tall surface.
Size playableFrameSize(Size available) {
  if (available.isEmpty) return available;
  final byAspect = available.height * playableFrameAspect;
  final width = [playableFrameMaxWidth, available.width, byAspect].reduce((a, b) => a < b ? a : b);
  var height = available.height;
  if (available.width > available.height) {
    final byWidth = width / playableFrameAspect;
    if (byWidth < height) height = byWidth;
  }
  return Size(width, height);
}
