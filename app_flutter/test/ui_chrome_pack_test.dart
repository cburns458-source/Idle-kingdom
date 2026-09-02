import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/ingredient_chip.dart';
import 'package:ik_content/ik_content.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('Settings General offers Wood and Stone UI looks', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));
    await tester.pump();

    expect(controller.uiChromePack, UiChromePack.wood);

    await openChinScreen(tester, 'Settings');
    await tester.tap(find.text('UI'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('UI look'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('UI look'), findsOneWidget);
    expect(find.text('Stone'), findsOneWidget);

    await tester.tap(find.widgetWithText(GameTextButton, 'Stone'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.uiChromePack, UiChromePack.stone);

    await tester.tap(find.widgetWithText(GameTextButton, 'Wood'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.uiChromePack, UiChromePack.wood);
  });

  test('Wood primaries are brown; Stone turns those browns grey and gold iron', () {
    expect(UiChrome.wood.primaryFill.colors, isNot(contains(const Color(0xFF7F9D63))));
    expect(UiChrome.wood.primaryFill.colors.first, const Color(0xFF8B5E34));
    expect(UiChrome.wood.embossFace, const Color(0xFF7A5F24));
    expect(UiChrome.stone.primaryFill.colors.first, const Color(0xFF6A6E78));
    expect(UiChrome.stone.embossFace, const Color(0xFF4A4E56));
    expect(UiChrome.stone.embossShade, const Color(0xFF141618));
  });

  testWidgets('Stone chat and dropdowns drop the wood parchment fill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.stone,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                return Column(
                  children: [
                    Material(key: const Key('chat-panel'), color: UiChrome.of(context).board),
                    GameDropdown<String>(
                      label: 'Recipe',
                      value: 'a',
                      items: const [GameDropdownItem(value: 'a', label: 'Baked Potato (Lv 1)')],
                      onChanged: (_) {},
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    final chat = tester.widget<Material>(find.byKey(const Key('chat-panel')));
    expect(chat.color, UiChrome.stone.board);
    expect(chat.color, isNot(Palette.parchmentDeep));

    final field = tester.widget<Text>(find.text('Baked Potato (Lv 1)'));
    expect(field.style?.color, UiChrome.stone.primaryLabel);
    expect(field.style?.color, isNot(UiChrome.stone.panelInk));

    final arrow = tester.widget<Icon>(find.byIcon(Icons.expand_more));
    expect(arrow.color, UiChrome.stone.primaryLabel);
    expect(arrow.color, isNot(Palette.gold));
  });

  testWidgets('Stone wells drop the wood slot brown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.stone,
          child: const Scaffold(body: IngredientChip(item: null, need: 2, owned: 1)),
        ),
      ),
    );

    final well = tester.widget<Container>(find.byType(Container).first);
    expect(well.decoration, isA<BoxDecoration>());
    expect((well.decoration as BoxDecoration).color, UiChrome.stone.slot);
    expect((well.decoration as BoxDecoration).color, isNot(Palette.slot));
  });

  testWidgets('GameButton wears the active pack fill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.stone,
          child: Scaffold(
            body: GameButton(label: 'Go', onPressed: () {}),
          ),
        ),
      ),
    );
    final plate = tester.widget<PixelInkPlate>(find.byType(PixelInkPlate));
    expect(plate.gradient, UiChrome.stone.primaryFill);
  });
}
