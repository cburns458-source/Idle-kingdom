import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/playable_frame.dart';

void main() {
  test('a tall desktop window stays 420 wide and keeps its full height', () {
    expect(playableFrameSize(const Size(900, 2400)), const Size(420, 2400));
  });

  test('a short wide window narrows so the column stays 9:16', () {
    expect(playableFrameSize(const Size(720, 450)), const Size(253.125, 450));
  });

  test('a phone-narrow window uses the full width', () {
    expect(playableFrameSize(const Size(390, 844)), const Size(390, 844));
  });

  test('a landscape desktop window is a full-height 9:16 column', () {
    expect(playableFrameHasSideChat(const Size(1920, 1080)), isTrue);
    expect(playableFrameSize(const Size(1920, 1080)), const Size(1080 * 9 / 16, 1080));
  });

  test('a phone-narrow window does not open side chat', () {
    expect(playableFrameHasSideChat(const Size(390, 844)), isFalse);
    expect(playableFrameHasSideChat(const Size(800, 600)), isFalse);
  });

  test('an empty box is returned unchanged', () {
    expect(playableFrameSize(Size.zero), Size.zero);
  });
}
