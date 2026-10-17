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
    expect(Palette.successInk, isNot(Palette.success));
    expect(Palette.currencyOnSlot, isNot(Palette.currency));
    expect(PixelChrome.goldFace, Palette.gold);
    expect(PixelChrome.goldHighlight, Palette.goldHighlight);
    expect(PixelChrome.goldShade, Palette.goldShade);
    expect(PixelChrome.wood, Palette.wood);
  });

  test('gold ink and confirm cream clear 4.5:1 on tan, ash, and green fills', () {
    expect(contrastRatio(Palette.goldInk, Palette.panelTan), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.goldInk, UiChrome.stone.panel), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.gold, Palette.wood), greaterThanOrEqualTo(4.5));
    for (final fill in [
      ...Palette.confirmFill.colors,
      ...Palette.confirmPressed.colors,
      ...Palette.confirmSelected.colors,
    ]) {
      expect(contrastRatio(Palette.confirmLabel, fill), greaterThanOrEqualTo(4.5));
    }
    expect(contrastRatio(Palette.heading, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.heading, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.parchmentText, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.parchmentText, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
    expect(
      contrastRatio(UiChrome.wood.primaryLabel, UiChrome.wood.primarySelected.colors.first),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(UiChrome.wood.secondaryLabel, UiChrome.wood.secondarySelected.colors.first),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('green ink and selected green clear 4.5:1 on tan, ash, wood, and stone', () {
    expect(contrastRatio(Palette.successInk, Palette.panelTan), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.successInk, UiChrome.stone.panel), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.skillXp, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.skillXp, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
  });

  test('shop slot currency clears 4.5:1 on wood and stone wells', () {
    expect(contrastRatio(Palette.currencyOnSlot, UiChrome.wood.slot), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.currencyOnSlot, UiChrome.stone.slot), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.currency, UiChrome.wood.slot), lessThan(4.5));
    expect(contrastRatio(Palette.currency, UiChrome.stone.slot), lessThan(4.5));
  });

  test('unselected option parchment clears 4.5:1 on wood and stone boards', () {
    expect(contrastRatio(Palette.parchmentText, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.parchmentText, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.panelInk, Palette.panelTan), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(UiChrome.stone.panelInk, UiChrome.stone.panel), greaterThanOrEqualTo(4.5));
  });

  test('you-are-here is a filled gold marker; selected is a gold rim', () {
    final here = mapNodeMarkerStyle(isHere: true, isSelected: false);
    final picked = mapNodeMarkerStyle(isHere: false, isSelected: true);
    final both = mapNodeMarkerStyle(isHere: true, isSelected: true);
    expect(here.fill, Palette.goldHighlight);
    expect(here.fill, isNot(Palette.borderSelected));
    expect(here.border, isNot(Palette.borderSelected));
    expect(picked.fill, Palette.parchmentText);
    expect(picked.border, Palette.gold);
    expect(picked.border, isNot(Palette.borderSelected));
    expect(both.fill, Palette.goldHighlight);
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

  testWidgets('selected GameButton uses a brighter fill and the pack rim, not a green rim', (
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
                const GameButton(label: 'Wait', onPressed: null),
              ],
            ),
          ),
        ),
      ),
    );

    final plates = tester.widgetList<PixelInkPlate>(find.byType(PixelInkPlate)).toList();
    expect(plates, hasLength(3));
    expect(plates[0].selected, isFalse);
    expect(plates[0].emboss, isTrue);
    expect(plates[0].gradient, UiChrome.stone.primarySelected);
    expect(plates[0].gradient, isNot(UiChrome.stone.primaryPressed));
    expect(plates[1].selected, isFalse);
    expect(plates[1].gradient, Palette.confirmFill);
    expect(plates[2].gradient, Palette.confirmDisabledFill);
    expect(tester.widget<Text>(find.text('Wait')).style?.color, Palette.confirmDisabledLabel);
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
      expect(tester.widget<Text>(find.text('Share an idea')).style?.color, Palette.skillXp);
      expect(contrastRatio(Palette.skillXp, chrome.board), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('GameTextButton selected green on a tan panel uses success ink', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.wood,
          child: Scaffold(
            body: GamePanel(
              child: GameTextButton(label: 'Bug', selected: true, onPressed: () {}),
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('Bug')).style?.color, Palette.successInk);
    expect(contrastRatio(Palette.successInk, Palette.panelTan), greaterThanOrEqualTo(4.5));
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
