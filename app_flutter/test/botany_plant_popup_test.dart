import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/botany_plant_popup.dart';
import 'package:idle_kingdoms/src/ui/floating_slot.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('selected seed count uses success green on the slot, not rim green', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UiChromeScope(
          chrome: UiChrome.wood,
          child: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showBotanyPlantGridPopup(
                    context: context,
                    controller: controller,
                    options: const [
                      PlantableBotanyOption(
                        itemId: 'ITEM-0025',
                        displayName: 'Potato seed',
                        spec: BotanySeedSpec(
                          outputItemId: 'ITEM-0024',
                          growSeconds: 10,
                          xp: 1,
                          requiresLevel: 1,
                          shallowsOnly: false,
                          isSapling: false,
                        ),
                        owned: 5,
                        plantQuantity: 1,
                        canPlant: true,
                        reason: '',
                      ),
                    ],
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(FloatingItemSlot));
    await tester.pump();

    final count = tester.widget<Text>(find.text('1').last);
    expect(count.style?.color, Palette.skillXp);
    expect(count.style?.color, isNot(Palette.borderSelected));
    expect(contrastRatio(Palette.skillXp, UiChrome.wood.slot), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.skillXp, UiChrome.stone.slot), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.borderSelected, UiChrome.wood.board), lessThan(4.5));
  });
}
