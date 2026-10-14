import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('the close x is a 32px chip inside a 48px tap square', (tester) async {
    var taps = 0;
    await pump(tester, GameCloseButton(onPressed: () => taps++));

    final button = find.byType(GameCloseButton);
    expect(tester.getSize(button), const Size(gameCloseTapTarget, gameCloseTapTarget));
    expect(tester.getSize(find.byType(PixelPlate)), const Size(32, 32));
    expect(find.byIcon(Icons.close), findsOne);
    expect(find.byTooltip('Close'), findsOne);
    expect(find.text('Close'), findsNothing);

    // The ring around the chip still counts as the button.
    final box = tester.getRect(button);
    await tester.tapAt(box.topLeft + const Offset(3, 3));
    await tester.tapAt(box.bottomRight - const Offset(3, 3));
    await tester.tap(find.byIcon(Icons.close));
    expect(taps, 3);
  });

  testWidgets('a plain icon chip keeps its own size as the tap area', (tester) async {
    await pump(tester, GameIconButton(icon: Icons.check, tooltip: 'Accept', onPressed: () {}));
    expect(tester.getSize(find.byType(GameIconButton)), const Size(32, 32));
    expect(tester.getSize(find.byType(PixelPlate)), const Size(32, 32));
  });

  testWidgets('a disabled close x ignores taps', (tester) async {
    await pump(tester, const GameCloseButton(onPressed: null));
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(tester.getSize(find.byType(GameCloseButton)), const Size(48, 48));
  });
}
