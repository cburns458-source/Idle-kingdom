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

  test('a landscape desktop window is a 9:16 phone', () {
    expect(playableFrameSize(const Size(1920, 1080)), const Size(420, 420 * 16 / 9));
  });

  test('an empty box is returned unchanged', () {
    expect(playableFrameSize(Size.zero), Size.zero);
  });
}
