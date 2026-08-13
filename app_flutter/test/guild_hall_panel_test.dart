import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/guild_hall_panel.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('offers the hall at the Guild Hall and hides it in the Meadow', (tester) async {
    final hall = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: guildHallLocationId),
    );
    addTearDown(hall.dispose);
    await pumpPanel(
      tester,
      LocationView(
        controller: hall,
        multiplayer: buildMultiplayer(database),
        onOpenMap: () {},
        onOpenSubMap: (_) {},
      ),
      size: const Size(900, 2400),
    );
    expect(find.text('Hall services'), findsOne);

    final meadow = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(meadow.dispose);
    await pumpPanel(
      tester,
      LocationView(
        controller: meadow,
        multiplayer: buildMultiplayer(database),
        onOpenMap: () {},
        onOpenSubMap: (_) {},
      ),
    );
    expect(find.text('Hall services'), findsNothing);
  });

  testWidgets('a signed-in guild leader can open the hall panel', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(currentLocationId: guildHallLocationId, gold: guildHallDebtGold),
    );
    addTearDown(controller.dispose);
    final net = buildMultiplayer(database);
    addTearDown(net.dispose);
    final signed = await net.service.signUp('leader@example.com', 'Leader', 'secret');
    expect(signed.ok, isTrue);
    final created = await net.service.createGuild(
      CreateGuildInput(
        name: 'Oak',
        tag: 'OAK',
        description: '',
        emblem: const GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      controller.save.gold,
    );
    expect(created.ok, isTrue);
    await net.refresh(controller.save);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();
    expect(find.text('Guild Hall'), findsOne);
    expect(find.text('Debt'), findsOne);
    await tester.tap(find.text('Debt'));
    await tester.pump();
    expect(find.textContaining('Remaining:'), findsOne);
  });
}
