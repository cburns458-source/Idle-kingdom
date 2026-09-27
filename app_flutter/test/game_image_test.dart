import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/content/asset_paths.dart';
import 'package:idle_kingdoms/src/ui/game_image.dart';

void main() {
  test('decode size follows the painted size and caps runaway rasters', () {
    expect(gameImageDecodePx(24, 3), 72);
    expect(gameImageDecodePx(24, 1), 24);
    expect(gameImageDecodePx(null, 3), isNull);
    expect(gameImageDecodePx(0, 3), isNull);
    expect(gameImageDecodePx(-4, 2), isNull);
    expect(gameImageDecodePx(double.infinity, 2), isNull);
    expect(gameImageDecodePx(4000, 3), gameImageMaxDecodePx);
  });

  testWidgets('sized art asks the codec for the painted pixel size', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: GameImage(goldIconPath(), width: 24, height: 24)));

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 24);
    expect(image.height, 24);
    final resized = image.image as ResizeImage;
    expect(resized.width, 72);
    expect(resized.height, 72);
  });
}
