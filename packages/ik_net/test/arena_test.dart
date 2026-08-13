import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase database;

  setUpAll(() {
    database = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('search finds a stored player by name and ranked picks closest combat level', () {
    final harness = LocalMultiplayerBackend(storage: MemorySaveStorage());
    harness.ensureDemoWorld(database);
    final hero = harness.signUp('hero@example.com', 'Hero', 'secret').session!;
    harness.writeCloudSave(hero.userId, createNewSave(database, 1));

    final all = harness.listArenaOpponents(excludeUserId: hero.userId);
    expect(all.map((row) => row.username).toList(), containsAll(<String>['Bram', 'Kael', 'Mira']));
    expect(all.any((row) => row.userId == hero.userId), isFalse);

    expect(searchArenaOpponents(all, 'mi').single.username, 'Mira');
    expect(pickRankedOpponent(1, 13, all)?.username, 'Bram');
    expect(pickRankedOpponent(8, 13, all)?.username, 'Mira');
    expect(pickRankedOpponent(18, 18, all)?.username, 'Kael');

    final mira = harness.opponentSave(demoMiraId);
    expect(mira, isNotNull);
    expect(combatLevelOf(mira!), 8);
  });
}
