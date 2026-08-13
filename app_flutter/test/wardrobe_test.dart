import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Future<void> openWardrobe(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Open wardrobe'));
    await tester.pump();
  }

  testWidgets('the portrait opens the wardrobe and retires its hint', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    // The starter outfit is owned from the first tick, so the hint is on.
    expect(controller.save.hasSeenWardrobeIntro, isFalse);
    await pumpShell(tester, controller);

    await openWardrobe(tester);

    expect(find.text('Wardrobe'), findsOne);
    expect(find.text("Traveler's Tunic"), findsOne);
    expect(controller.save.hasSeenWardrobeIntro, isTrue);
  });

  testWidgets('a cosmetic comes off and goes back on', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openWardrobe(tester);

    await tester.tap(find.text('None'));
    await tester.pump();
    expect(equippedCosmeticId(controller.save, 'CSLOT-0001'), isNull);

    await tester.tap(find.text("Traveler's Tunic"));
    await tester.pump();
    expect(equippedCosmeticId(controller.save, 'CSLOT-0001'), 'COS-0001');
  });

  testWidgets('a slot with nothing in it says so', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openWardrobe(tester);

    await tester.tap(find.text('Pet'));
    await tester.pump();

    expect(find.text('No Pet unlocked yet.'), findsOne);
    expect(find.text("Traveler's Tunic"), findsNothing);

    await tester.tap(find.text('Titles'));
    await tester.pump();
    expect(find.text('No Titles unlocked yet.'), findsOne);
  });

  testWidgets('a slider changes the look and the portrait follows', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openWardrobe(tester);

    final before = controller.save.appearance.skinTone;
    // Drag the first slider (skin tone) to its far end.
    await tester.drag(find.byType(Slider).first, const Offset(500, 0));
    await tester.pump();

    expect(controller.save.appearance.skinTone, isNot(before));
    expect(controller.save.appearance.skinTone, 'APR-0003');
  });

  testWidgets('the wardrobe closes back to the game', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openWardrobe(tester);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(find.text('Wardrobe'), findsNothing);
  });

  testWidgets('character creation picks a starting look', (tester) async {
    final controller = buildController(database);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.enterText(find.byType(TextField), 'Tester');
    // Gender presentation is the last slider, and the only one the art follows.
    await tester.drag(find.byType(Slider).last, const Offset(500, 0));
    await tester.pump();
    await tester.tap(find.text('Human'));
    await tester.pump();
    await tester.tap(find.text('Begin'));
    await tester.pump();

    expect(controller.save.characterName, 'Tester');
    expect(controller.save.appearance.genderPresentation, 'APR-0018');
  });

  testWidgets('buying a cosmetic pops the unlock and adds it to the wardrobe', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        gold: 100000,
        // At the General Store, which is the counter that stocks the outfit.
        currentLocationId: 'LOC-0024',
        cosmetics: const CosmeticsState(unlocked: <String>[], equipped: <String, String?>{}),
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    final result = confirmShopOffer(
      controller.db,
      controller.save,
      'SHP-0001',
      const ShopOffer(
        buys: <ShopOfferLine>[ShopOfferLine(itemId: 'ITEM-0296', quantity: 1)],
        sells: <ShopOfferLine>[],
      ),
    );
    expect(result.ok, isTrue, reason: result.reason);
    controller.commitLoadout(result.save!);
    controller.noteCosmeticUnlocks(result.cosmeticsGranted);
    await tester.pump();

    expect(find.text('You found a Cosmetic!'), findsOne);
    // First cosmetic ever, so the popup also says where to wear it.
    expect(find.textContaining('Tap your portrait'), findsOne);

    await tester.tap(find.text('Nice!'));
    await tester.pump();
    expect(find.text('You found a Cosmetic!'), findsNothing);

    await openWardrobe(tester);
    expect(find.text("Traveler's Tunic"), findsOne);
  });
}
