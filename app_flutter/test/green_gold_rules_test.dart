import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/item_icon.dart';
import 'package:idle_kingdoms/src/ui/world_map_view.dart';

void main() {
  test('semantic tokens match Vari\'s green/gold rules', () {
    expect(Palette.borderSelected, Palette.softGreen);
    expect(Palette.currency, Palette.gold);
    expect(Palette.rare, Palette.gold);
    expect(Palette.success, Palette.softGreen);
    expect(Palette.progress, Palette.skillXp);
    expect(Palette.border, isNot(Palette.gold));
    expect(Palette.edge, isNot(const Color(0x73A7872D)));
    expect(Palette.goldInk, isNot(Palette.gold));
    expect(PixelChrome.goldFace, Palette.gold);
    expect(PixelChrome.goldHighlight, Palette.goldHighlight);
    expect(PixelChrome.goldShade, Palette.goldShade);
    expect(PixelChrome.wood, Palette.wood);
  });

  test('gold ink and confirm cream clear 4.5:1 on tan, ash, and green fills', () {
    expect(contrastRatio(Palette.goldInk, Palette.panelTan), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.goldInk, UiChrome.stone.panel), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.gold, Palette.wood), greaterThanOrEqualTo(4.5));
    for (final fill in [...Palette.confirmFill.colors, ...Palette.confirmPressed.colors]) {
      expect(contrastRatio(Palette.confirmLabel, fill), greaterThanOrEqualTo(4.5));
    }
  });

  test('unselected option parchment clears 4.5:1 on wood and stone boards', () {
    expect(contrastRatio(Palette.parchmentText, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.parchmentText, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.panelInk, Palette.panelTan), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(UiChrome.stone.panelInk, UiChrome.stone.panel), greaterThanOrEqualTo(4.5));
  });

  test('you-are-here is a filled marker; selected is a green rim', () {
    final here = mapNodeMarkerStyle(isHere: true, isSelected: false);
    final picked = mapNodeMarkerStyle(isHere: false, isSelected: true);
    final both = mapNodeMarkerStyle(isHere: true, isSelected: true);
    expect(here.fill, Palette.borderSelected);
    expect(here.border, isNot(Palette.borderSelected));
    expect(picked.fill, Palette.parchmentText);
    expect(picked.border, Palette.borderSelected);
    expect(both.fill, Palette.borderSelected);
    expect(both.border, here.border);
    expect(both.border, isNot(picked.border));
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

  testWidgets('disabled confirm is grey on wood and stone, not faded green', (tester) async {
    for (final chrome in [UiChrome.wood, UiChrome.stone]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: UiChromeScope(
            chrome: chrome,
            child: const Scaffold(
              body: GameButton(label: 'Buy', tone: GameButtonTone.confirm, onPressed: null),
            ),
          ),
        ),
      );
      final plate = tester.widget<PixelInkPlate>(find.byType(PixelInkPlate));
      expect(plate.gradient, Palette.confirmDisabledFill);
      expect(plate.gradient, isNot(Palette.confirmFill));
      final label = tester.widget<Text>(find.text('Buy'));
      expect(label.style?.color, Palette.confirmDisabledLabel);
    }
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

  testWidgets('GoldAmount on a tan panel uses gold ink', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.wood,
          child: const Scaffold(body: GamePanel(child: GoldAmount(amount: 12))),
        ),
      ),
    );
    final amount = tester.widget<Text>(find.text('12'));
    expect(amount.style?.color, Palette.goldInk);
  });

  testWidgets('GoldCopy on a tan panel uses gold ink', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.wood,
          child: const Scaffold(body: GamePanel(child: GoldCopy('Shop'))),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('Shop')).style?.color, Palette.goldInk);
  });

  testWidgets('GameTextButton is parchment on boards, green when selected', (tester) async {
    for (final chrome in [UiChrome.wood, UiChrome.stone]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: UiChromeScope(
            chrome: chrome,
            child: Scaffold(
              body: ColoredBox(
                color: chrome.board,
                child: GameTextButton(label: 'Report a bug', selected: false, onPressed: () {}),
              ),
            ),
          ),
        ),
      );
      expect(tester.widget<Text>(find.text('Report a bug')).style?.color, Palette.parchmentText);
      expect(contrastRatio(Palette.parchmentText, chrome.board), greaterThanOrEqualTo(4.5));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: UiChromeScope(
            chrome: chrome,
            child: Scaffold(
              body: ColoredBox(
                color: chrome.board,
                child: GameTextButton(label: 'Share an idea', selected: true, onPressed: () {}),
              ),
            ),
          ),
        ),
      );
      expect(tester.widget<Text>(find.text('Share an idea')).style?.color, Palette.borderSelected);
    }
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
