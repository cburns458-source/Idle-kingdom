import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/new_character_sheet.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('character create writes the public name even when the session already matches', (
    tester,
  ) async {
    final transport = FakeTransport();
    transport.seedAccount(email: 'vari@example.com');
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(net.dispose);
    final game = buildController(database, seed: createNewSave(database.launch, testStartMs));
    addTearDown(game.dispose);

    await net.signIn('vari@example.com', 'secret', game.save, adopt: (save, {nowMs}) {});
    expect(net.session?.username, 'vari');
    expect(
      isUnclaimedAccountUsername('${transport.tables[RemoteTables.profiles]!.single['username']}'),
      isTrue,
    );

    await pumpPanel(tester, NewCharacterSheet(controller: game, multiplayer: net));
    await tester.enterText(find.widgetWithText(TextField, 'Character name'), 'vari');
    await tester.tap(find.text('Begin'));
    await tester.pump();
    await tester.pump();

    expect(transport.tables[RemoteTables.profiles]!.single['username'], 'vari');
    expect(game.save.characterName, 'vari');
    expect(net.session?.username, 'vari');
  });
}
