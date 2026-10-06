import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';

/// The database a fixture was recorded against.
GameDatabase databaseOf(ParityFixture fixture) =>
    assertGameDatabaseShape(fixtureDatabaseJson(fixture));

/// The starting save, carried in the fixture input.
///
/// Reading it back through the generated model also proves `fromJson` and
/// `toJson` preserve every field, since the resulting save is what gets compared.
PlayerSave saveOf(ParityFixture fixture) {
  final nowMs = fixture.inputMap['nowMs'];
  final clock = nowMs is num ? nowMs : 0;
  return PlayerSave.fromJson(migrateSaveJson(asJsonMap(fixture.inputMap['save']), clock));
}
