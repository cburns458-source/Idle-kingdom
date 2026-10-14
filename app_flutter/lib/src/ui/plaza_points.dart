import 'package:ik_rules/ik_rules.dart';

import 'format.dart';

/// Offline, local save, and any session without a hosted server connection.
const String plazaShopNeedsConnection = 'Plaza purchases need a connection to the server';

/// Player-facing price, or why this row cannot be bought.
String plazaShopPriceLabel(num? price) {
  if (price == null) return plazaShopUnknownItem;
  return '${formatThousands(price)} plaza points';
}

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
