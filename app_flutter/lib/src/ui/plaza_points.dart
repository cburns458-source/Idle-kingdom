import 'format.dart';

/// Player-facing plaza-point gain, or null when the field is missing or 0.
String? plazaPointsGainedNotice(num? pointsGained) {
  final amount = _plazaNoticeAmount(pointsGained);
  if (amount <= 0) return null;
  return '+${formatThousands(amount)} plaza points';
}

/// Player-facing plaza-point spend, or null when the field is missing or 0.
String? plazaPointsSpentNotice(num? pointsSpent) {
  final amount = _plazaNoticeAmount(pointsSpent);
  if (amount <= 0) return null;
  return '-${formatThousands(amount)} plaza points';
}

num _plazaNoticeAmount(num? value) {
  if (value == null || !value.isFinite) return 0;
  return value.floor();
}
