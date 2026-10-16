import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/item_icon.dart';

void main() {
  test('semantic tokens match Vari\'s green/gold rules', () {
    expect(Palette.borderSelected, Palette.softGreen);
    expect(Palette.currency, Palette.gold);
    expect(Palette.rare, Palette.gold);
    expect(Palette.success, Palette.softGreen);
    expect(Palette.progress, Palette.skillXp);
    expect(Palette.border, isNot(Palette.gold));
    expect(Palette.edge, isNot(const Color(0x73A7872D)));
    expect(PixelChrome.goldFace, Palette.gold);
    expect(PixelChrome.goldHighlight, Palette.goldHighlight);
    expect(PixelChrome.goldShade, Palette.goldShade);
    expect(PixelChrome.wood, Palette.wood);
  });

  test('wood and stone share selected green and rare gold rims', () {
    for (final chrome in [UiChrome.wood, UiChrome.stone]) {
      expect(chrome.embossFaceSelected, Palette.borderSelected);
      expect(chrome.embossHighlightSelected, Palette.borderSelectedHighlight);
      expect(chrome.embossShadeSelected, Palette.borderSelectedShade);
      expect(chrome.embossFaceRare, Palette.rare);
      expect(chrome.embossFace, isNot(Palette.gold));
      expect(chrome.embossFaceSelected, isNot(Palette.gold));
    }
    expect(UiChrome.wood.embossFace, Palette.border);
    expect(UiChrome.stone.embossFace, const Color(0xFF4F4F4F));
  });

  testWidgets('PixelPlate defaults to a pack rim, green when selected, gold when rare', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.wood,
          child: const Scaffold(
            body: Column(
              children: [
                PixelPlate(key: Key('plain'), child: SizedBox(width: 20, height: 20)),
                PixelPlate(
                  key: Key('picked'),
                  selected: true,
                  child: SizedBox(width: 20, height: 20),
                ),
                PixelPlate(key: Key('feat'), rare: true, child: SizedBox(width: 20, height: 20)),
                PixelPlate(
                  key: Key('both'),
                  selected: true,
                  rare: true,
                  child: SizedBox(width: 20, height: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final plain = tester.widget<PixelPlate>(find.byKey(const Key('plain')));
    expect(plain.selected, isFalse);
    expect(plain.rare, isFalse);
    expect(plain.emboss, isTrue);

    final picked = tester.widget<PixelPlate>(find.byKey(const Key('picked')));
    expect(picked.selected, isTrue);
    expect(picked.rare, isFalse);

    final feat = tester.widget<PixelPlate>(find.byKey(const Key('feat')));
    expect(feat.rare, isTrue);
    expect(feat.selected, isFalse);

    final both = tester.widget<PixelPlate>(find.byKey(const Key('both')));
    expect(both.selected, isTrue);
    expect(both.rare, isTrue);
  });

  testWidgets('selected GameButton embosses a green rim; confirm uses the green fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.stone,
          child: Scaffold(
            body: Column(
              children: [
                GameButton(label: 'Hall', selected: true, onPressed: () {}),
                GameButton(label: 'Pay', tone: GameButtonTone.confirm, onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    final plates = tester.widgetList<PixelInkPlate>(find.byType(PixelInkPlate)).toList();
    expect(plates, hasLength(2));
    expect(plates[0].selected, isTrue);
    expect(plates[0].gradient, UiChrome.stone.primaryPressed);
    expect(plates[1].selected, isFalse);
    expect(plates[1].gradient, Palette.confirmFill);
  });

  testWidgets('GoldAmount defaults to currency gold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: GoldAmount(amount: 12)),
      ),
    );
    final amount = tester.widget<Text>(find.text('12'));
    expect(amount.style?.color, Palette.currency);
  });

  testWidgets('GamePanel highlight is selected, not rare', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.wood,
          child: const Scaffold(body: GamePanel(highlight: true, child: Text('You'))),
        ),
      ),
    );
    final plate = tester.widget<PixelPlate>(find.byType(PixelPlate).first);
    expect(plate.selected, isTrue);
    expect(plate.rare, isFalse);
  });
}
