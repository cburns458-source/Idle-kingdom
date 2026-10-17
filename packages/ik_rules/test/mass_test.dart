import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  final db = prepareDatabase(contentDatabaseJson()).launch;

  test('adds 50% of solo HP per extra player', () {
    expect(massHealthMultiplier(1), 1);
    expect(massHealthMultiplier(2), 1.5);
    expect(massHpFor(1000, 2), 1500);
    expect(massDropScale(1), 1);
    expect(massDropScale(2), closeTo(0.675, 0.0001));
    expect(massMinimumDamage(1000, 1), 30);
    expect(massMinimumDamage(1000, 10), 25);
  });

  test('starts without damage and ignores an early or duplicate clock', () {
    const startMs = 1767225600000;
    var save = createNewSave(
      db,
      startMs,
    ).copyWith(currentLocationId: dragonLocationId, currentHp: 20000, maxHp: 20000);
    final started = simulateMassFightTick(
      db,
      save,
      MassFightTickInput(
        nowMs: startMs,
        random: () => 0,
        encounterId: 'enc-1',
        enemyId: dragonEnemyId,
        sharedRemainingHp: 1000,
        healthMultiplier: 1,
        lockedIn: true,
        late: false,
      ),
    );
    expect(started.started, isTrue);
    expect(started.damageDealt, 0);
    save = started.save;
    expect(save.massEncounterId, 'enc-1');

    final early = simulateMassFightTick(
      db,
      save,
      MassFightTickInput(
        nowMs: startMs + 1000,
        random: () => 0,
        encounterId: 'enc-1',
        enemyId: dragonEnemyId,
        sharedRemainingHp: 1000,
        healthMultiplier: 1,
        lockedIn: true,
        late: false,
        lastRoundStartedAt: save.combatRoundStartedAt,
      ),
    );
    expect(early.early, isTrue);
    expect(early.damageDealt, 0);

    final due = jsDateParse(save.combatRoundStartedAt) + 6000;
    final first = simulateMassFightTick(
      db,
      save,
      MassFightTickInput(
        nowMs: due,
        random: () => 0,
        encounterId: 'enc-1',
        enemyId: dragonEnemyId,
        sharedRemainingHp: 1000,
        healthMultiplier: 1,
        lockedIn: true,
        late: false,
      ),
    );
    expect(first.damageDealt, greaterThan(0));

    final dup = simulateMassFightTick(
      db,
      save,
      MassFightTickInput(
        nowMs: due,
        random: () => 0,
        encounterId: 'enc-1',
        enemyId: dragonEnemyId,
        sharedRemainingHp: 1000,
        healthMultiplier: 1,
        lockedIn: true,
        late: false,
        lastRoundStartedAt: save.combatRoundStartedAt,
      ),
    );
    expect(dup.duplicate, isTrue);
    expect(dup.damageDealt, 0);
  });

  test('a late joiner does not change shared HP', () {
    const startMs = 1767225600000;
    final action = db.actions.firstWhere((row) => row.actionId == 'ACN-0092');
    final enemy = getEnemy(db, dragonEnemyId)!;
    final begun = beginCombatSave(
      db,
      createNewSave(db, startMs).copyWith(
        currentLocationId: dragonLocationId,
        currentHp: 20000,
        maxHp: 20000,
        massEncounterId: 'enc-1',
      ),
      action,
      enemy,
      isoFromMs(startMs),
      5000,
    );
    final due = jsDateParse(begun.combatRoundStartedAt) + 6000;
    final tick = simulateMassFightTick(
      db,
      begun,
      MassFightTickInput(
        nowMs: due,
        random: () => 0,
        encounterId: 'enc-1',
        enemyId: dragonEnemyId,
        sharedRemainingHp: 5000,
        healthMultiplier: 1.5,
        lockedIn: false,
        late: true,
      ),
    );
    expect(tick.damageDealt, 0);
  });

  test('keeps baby dragon and baby squid untradeable', () {
    expect(db.cosmetics.firstWhere((row) => row.cosmeticId == 'COS-0012').itemId, 'ITEM-0404');
    expect(db.cosmetics.firstWhere((row) => row.cosmeticId == 'COS-0020').itemId, 'ITEM-0443');
    expect(db.items.firstWhere((row) => row.itemId == 'ITEM-0404').isTradeable, isFalse);
    expect(db.items.firstWhere((row) => row.itemId == 'ITEM-0443').isTradeable, isFalse);
  });

  test('closed and settled snapshots are not lobby or fighting', () {
    MassEncounterSnapshot snap(String status) {
      return MassEncounterSnapshot(
        encounterId: 'enc-1',
        enemyId: dragonEnemyId,
        status: status,
        lockedCount: 0,
        soloHp: 1,
        healthMultiplier: 1,
        totalHp: 1,
        remainingHp: 1,
        dropScale: 1,
        minDamage: 1,
        participants: const <MassParticipantView>[],
      );
    }

    expect(snap('lobby').isLobby, isTrue);
    expect(snap('fighting').isFighting, isTrue);
    expect(snap('closed').isClosed, isTrue);
    expect(snap('closed').isSettled, isFalse);
    expect(snap('settled').isSettled, isTrue);
    expect(snap('settled').isClosed, isFalse);
    expect(snap('closed').isLobby, isFalse);
    expect(snap('settled').isFighting, isFalse);
  });

  test('clamps the caller-supplied squid health scale', () {
    expect(clampMassPlayerBaseHpScale(2.2), 2.2);
    expect(clampMassPlayerBaseHpScale(0), isNull);
    expect(clampMassPlayerBaseHpScale(-1), isNull);
    expect(clampMassPlayerBaseHpScale(999), 10);
    expect(clampMassPlayerBaseHpScale(0.01), 0.1);
  });
}
