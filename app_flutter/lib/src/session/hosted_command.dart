import 'package:ik_rules/ik_rules.dart';

/// What a hosted command came back with: the refusal, or the server's numbers.
class HostedCommandReceipt {
  const HostedCommandReceipt({
    this.reason,
    this.code,
    this.noRoom,
    this.pointsSpent = 0,
    this.plazaPoints = 0,
    this.save,
  });

  final String? reason;
  final String? code;
  final NoRoom? noRoom;
  final int pointsSpent;
  final int plazaPoints;
  final PlayerSave? save;

  bool get ok => reason == null;
}

typedef HostedCommandSubmit = Future<HostedCommandReceipt> Function(
  String command, [
  Map<String, Object?> args,
]);
