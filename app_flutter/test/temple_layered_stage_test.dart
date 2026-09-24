import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/content/asset_paths.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/action_stage.dart';
import 'package:idle_kingdoms/src/ui/equipment_presets_bar.dart';
import 'package:idle_kingdoms/src/ui/temple_stage.dart';
import 'package:ik_content/ik_content.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  bool assetNamed(Widget widget, String needle) {
    if (widget is! Image) return false;
    final image = widget.image;
    return image is AssetImage && image.assetName.contains(needle);
  }

  Finder dockRow(String title) {
    return find.ancestor(of: find.text(title), matching: find.byType(DockRow));
  }

  testWidgets('Temple uses the layered plate and a solid lower panel', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0036'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 420 * 16 / 9));

    expect(find.byType(TempleLayeredBackdrop), findsOne);
    expect(find.byWidgetPredicate((widget) => assetNamed(widget, 'loc_temple_sky.webp')), findsOne);
    expect(
      find.byWidgetPredicate((widget) => assetNamed(widget, 'loc_temple_terrain.webp')),
      findsOne,
    );
    expect(
      find.byWidgetPredicate((widget) => assetNamed(widget, 'loc_temple_foreground.webp')),
      findsOne,
    );
    expect(find.byType(LocationIdlePlayer), findsOne);
    expect(find.bySemanticsLabel('Adventurer'), findsOne);
    expect(find.byType(StageLoadoutStrip), findsOne);
    expect(find.byType(EquipmentPresetsBar), findsOne);

    final player = tester.getRect(find.bySemanticsLabel('Adventurer'));
    final presets = tester.getRect(find.byType(StageLoadoutStrip));
    final backdrop = tester.getRect(find.byType(TempleLayeredBackdrop));
    expect(presets.top, greaterThan(player.bottom - 8));
    expect(presets.top, greaterThanOrEqualTo(backdrop.bottom - 1));
    expect(presets.top - backdrop.bottom, lessThan(16));

    final layout = TempleStageLayout(backdrop.size);
    expect(layout.scale, closeTo(backdrop.width / templeViewWidth, 0.001));
    expect(player.bottom, closeTo(layout.playerFoot.dy + backdrop.top, 8));
    expect(player.center.dx, closeTo(layout.playerFoot.dx + backdrop.left, 16));

    final eat = tester.getRect(find.byKey(const Key('stage-eat-now')));
    final expand = tester.getRect(find.byTooltip('Expand list'));
    final activities = tester.getRect(find.widgetWithText(GameButton, 'Activities'));
    expect(expand.top, greaterThan(eat.bottom - 4));
    expect((expand.center.dy - activities.center.dy).abs(), lessThan(16));
    expect(expand.left, greaterThan(activities.right - 8));
  });

  testWidgets('Temple gathering plants action art on the right shadow', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0036'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 420 * 16 / 9));

    await tapVisible(
      tester,
      find.descendant(of: dockRow('Pick weeds'), matching: find.bySemanticsLabel('Start')),
    );

    expect(controller.save.currentActivityId, isNotNull);
    expect(find.byType(ActionStage), findsOne);
    final action = tester.getRect(
      find.byWidgetPredicate((widget) => assetNamed(widget, '/actions/')),
    );
    final player = tester.getRect(find.bySemanticsLabel('Adventurer'));
    final backdrop = tester.getRect(find.byType(TempleLayeredBackdrop));
    final layout = TempleStageLayout(backdrop.size);
    expect(action.bottom, closeTo(layout.actionFoot.dy + backdrop.top, 8));
    expect(action.center.dx, closeTo(layout.actionFoot.dx + backdrop.left, 16));
    expect(player.center.dx, lessThan(action.center.dx));

    final presets = tester.getRect(find.byType(StageLoadoutStrip));
    final actionId = controller.save.currentActionId;
    expect(actionId, isNotNull);
    expect(actionId, anyOf('ACN-0109', 'ACN-0110'));
    final actionName = controller.indexes.actionsById[actionId!]?.displayName;
    expect(actionName, isNotNull);
    final name = tester.getRect(
      find.byKey(ValueKey('stage-scene-name:$actionName'), skipOffstage: false),
    );
    final timer = tester.getRect(find.textContaining('0s /', skipOffstage: false));
    expect(name.bottom, lessThanOrEqualTo(presets.top + 8));
    expect(timer.bottom, lessThanOrEqualTo(presets.top + 8));
    expect(presets.top - timer.bottom, lessThan(40));
    expect(name.top, greaterThan(backdrop.top + backdrop.height * 0.35));
  });

  test('Temple layer paths sit next to the existing plate', () {
    expect(templeSkyAssetPath(), 'content/assets/locations/loc_temple_sky.webp');
    expect(usesTempleLayeredBackground('LOC-0036'), isTrue);
    expect(usesTempleLayeredBackground('LOC-0001'), isFalse);
    // Lower-middle of each ellipse, a few art pixels below the oval center.
    expect(templePlayerFootDesign.dy, closeTo(404.8125, 0.01));
    expect(templeActionFootDesign.dy, closeTo(404.5625, 0.01));
    expect(templePlayerFootDesign.dy, greaterThan(398.875));
    expect(templeActionFootDesign.dy, greaterThan(398.375));
  });
}
