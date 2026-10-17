import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/item_icon.dart';
import 'package:idle_kingdoms/src/ui/overlay_notice.dart';
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
    for (final fill in [...Palette.confirmFill.colors, ...Palette.confirmPressed.colors]) {
      expect(contrastRatio(Palette.confirmLabel, fill), greaterThanOrEqualTo(4.5));
    }
    expect(contrastRatio(Palette.heading, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.heading, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.parchmentText, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.parchmentText, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
    expect(
      contrastRatio(UiChrome.wood.primaryLabel, UiChrome.wood.primaryFill.colors.first),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(UiChrome.wood.secondaryLabel, UiChrome.wood.secondaryFill.colors.first),
      greaterThanOrEqualTo(4.5),
    );
    for (final fill in [...Palette.selectedFill.colors, ...Palette.selectedPressed.colors]) {
      expect(contrastRatio(Palette.selectedLabel, fill), greaterThanOrEqualTo(4.5));
    }
    for (final fill in Palette.confirmDisabledFill.colors) {
      expect(contrastRatio(Palette.confirmDisabledLabel, fill), greaterThanOrEqualTo(4.5));
    }
    for (final fill in [...Palette.dangerFill.colors, ...Palette.dangerPressed.colors]) {
      expect(contrastRatio(Palette.dangerLabel, fill), greaterThanOrEqualTo(4.5));
    }
    expect(contrastRatio(Palette.dangerText, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.dangerText, UiChrome.wood.slot), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.dangerText, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.dangerText, UiChrome.stone.slot), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.danger, UiChrome.wood.board), lessThan(4.5));
    expect(
      contrastRatio(Palette.dangerText, Palette.panelMuted),
      lessThan(4.5),
      reason: 'dangerText must never render on panelMuted #6B5338',
    );
  });

  test('selected gold fill is ≥1.5:1 vs idle green and brown', () {
    expect(Palette.confirmSelected, Palette.selectedFill);
    expect(UiChrome.wood.primarySelected, Palette.selectedFill);
    expect(UiChrome.stone.primarySelected, Palette.selectedFill);
    expect(
      contrastRatio(Palette.selectedFill.colors.first, Palette.confirmFill.colors.first),
      greaterThanOrEqualTo(1.5),
    );
    expect(
      contrastRatio(Palette.selectedFill.colors.first, UiChrome.wood.primaryFill.colors.first),
      greaterThanOrEqualTo(1.5),
    );
    expect(
      contrastRatio(Palette.selectedFill.colors.first, UiChrome.stone.primaryFill.colors.first),
      greaterThanOrEqualTo(1.5),
    );
  });

  test('gold copy on parchment uses goldInk, not gold', () {
    expect(contrastRatio(Palette.gold, Palette.parchmentText), lessThan(4.5));
    expect(contrastRatio(Palette.goldInk, Palette.parchmentText), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.goldInk, Palette.panelTan), greaterThanOrEqualTo(4.5));
  });

  test('colorScheme.secondary is gold, not green', () {
    expect(buildAppTheme().colorScheme.secondary, Palette.gold);
    expect(buildAppTheme().colorScheme.secondary, isNot(Palette.softGreen));
  });

  test('green ink and selected green clear 4.5:1 on tan, ash, wood, and stone', () {
    expect(contrastRatio(Palette.successInk, Palette.panelTan), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.successInk, UiChrome.stone.panel), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.skillXp, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.skillXp, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.skillXp, UiChrome.wood.slot), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.skillXp, UiChrome.stone.slot), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.heading, Palette.goldShade), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.borderSelected, UiChrome.wood.board), lessThan(4.5));
  });

  testWidgets('OverlayChipButton defaults to a gold plate, not green', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.wood,
          child: Scaffold(
            body: OverlayChipButton(
              tooltip: 'XP',
              onPressed: () {},
              child: const Text('XP', style: TextStyle(color: Palette.heading)),
            ),
          ),
        ),
      ),
    );
    final chip = tester.widgetList<Material>(find.byType(Material)).firstWhere((row) {
      return row.shape is PixelSteppedBorder;
    });
    expect((chip.shape! as PixelSteppedBorder).side.color, Palette.gold.withValues(alpha: 0.70));
    expect(
      (chip.shape! as PixelSteppedBorder).side.color,
      isNot(Palette.softGreenShade.withValues(alpha: 0.70)),
    );
    final ink = tester.widget<Ink>(find.byType(Ink));
    expect(ink.decoration, isA<BoxDecoration>());
    expect((ink.decoration! as BoxDecoration).color, Palette.goldShade);
    expect((ink.decoration! as BoxDecoration).color, isNot(Palette.softGreen));
  });

  testWidgets('sub-map back arrow is parchment gold, not green', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.wood,
          child: Scaffold(
            body: OverlayChipButton(
              tooltip: 'Back to Town',
              onPressed: () {},
              child: const Icon(Icons.arrow_back, size: 18, color: Palette.heading),
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.arrow_back)).color, Palette.heading);
    expect(tester.widget<Icon>(find.byIcon(Icons.arrow_back)).color, isNot(Palette.softGreenShade));
    expect(contrastRatio(Palette.heading, Palette.goldShade), greaterThanOrEqualTo(4.5));
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
    expect(picked.border, Palette.goldInk);
    expect(picked.border, isNot(Palette.gold));
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

  testWidgets('selected GameButton uses a gold inset plate, not a green rim', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.stone,
          child: Scaffold(
            body: Column(
              children: [
                GameButton(label: 'Hall', selected: true, onPressed: () {}),
                GameButton(
                  label: 'Pay',
                  tone: GameButtonTone.confirm,
                  selected: true,
                  onPressed: () {},
                ),
                GameButton(label: 'Buy', tone: GameButtonTone.confirm, onPressed: () {}),
                const GameButton(label: 'Wait', onPressed: null),
              ],
            ),
          ),
        ),
      ),
    );

    final plates = tester.widgetList<PixelInkPlate>(find.byType(PixelInkPlate)).toList();
    expect(plates, hasLength(4));
    expect(plates[0].selected, isFalse);
    expect(plates[0].inset, isTrue);
    expect(plates[0].emboss, isTrue);
    expect(plates[0].innerHighlight, Palette.parchmentText);
    expect(plates[0].gradient, Palette.selectedFill);
    expect(plates[0].gradient, isNot(UiChrome.stone.primaryFill));
    expect(tester.widget<Text>(find.text('Hall')).style?.color, Palette.goldInk);
    expect(plates[1].selected, isFalse);
    expect(plates[1].inset, isTrue);
    expect(plates[1].gradient, Palette.selectedFill);
    expect(plates[1].gradient, isNot(Palette.confirmFill));
    expect(tester.widget<Text>(find.text('Pay')).style?.color, Palette.goldInk);
    expect(plates[2].inset, isFalse);
    expect(plates[2].innerHighlight, isNull);
    expect(plates[2].gradient, Palette.confirmFill);
    expect(tester.widget<Text>(find.text('Buy')).style?.color, Palette.confirmLabel);
    expect(plates[3].gradient, Palette.confirmDisabledFill);
    expect(plates[3].emboss, isFalse);
    expect(plates[3].inset, isFalse);
    expect(tester.widget<Text>(find.text('Wait')).style?.color, Palette.confirmDisabledLabel);
  });

  testWidgets('disabled confirm is flat dark grey on wood and stone, not faded green', (
    tester,
  ) async {
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
      expect(plate.emboss, isFalse);
      expect(plate.inset, isFalse);
      expect(plate.shadow, isFalse);
      final label = tester.widget<Text>(find.text('Buy'));
      expect(label.style?.color, Palette.confirmDisabledLabel);
      for (final fill in Palette.confirmDisabledFill.colors) {
        expect(contrastRatio(Palette.confirmDisabledLabel, fill), greaterThanOrEqualTo(4.5));
      }
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

  testWidgets('OverlayNotice success copy uses success ink on the tan plate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.wood,
          child: const Scaffold(
            body: OverlayNotice(text: 'Bought.', tone: Palette.success),
          ),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('Bought.')).style?.color, Palette.successInk);
    expect(contrastRatio(Palette.successInk, Palette.panelTan), greaterThanOrEqualTo(4.5));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
