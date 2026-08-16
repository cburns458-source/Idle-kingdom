import 'package:ik_content/ik_content.dart';

import '../config.dart';

class AmenityCopy {
  const AmenityCopy({required this.title, required this.subtitle, required this.actionLabel});

  final String title;
  final String subtitle;
  final String actionLabel;
}

AmenityCopy amenityCopy(GameDatabase db, String kind) {
  return AmenityCopy(
    title: configString(db, 'copy.amenity.$kind.title', _fallbackTitle(kind)),
    subtitle: configString(db, 'copy.amenity.$kind.subtitle', _fallbackSubtitle(kind)),
    actionLabel: configString(db, 'copy.amenity.$kind.action', _fallbackAction(kind)),
  );
}

String _fallbackTitle(String kind) {
  return switch (kind) {
    'blessing' => 'Be blessed',
    'bank' => 'Item storage',
    'arena' => 'Player fights',
    'hall' => 'Hall services',
    _ => kind,
  };
}

String _fallbackSubtitle(String kind) {
  return switch (kind) {
    'blessing' => 'The monks restore you to full health.',
    'bank' => 'Deposit and withdraw items.',
    'arena' => 'Search by name, or ranked by combat level.',
    'hall' => 'Storehouse, debt, and boxing ring.',
    _ => '',
  };
}

String _fallbackAction(String kind) {
  return switch (kind) {
    'blessing' => 'Bless',
    'bank' => 'Bank',
    'arena' => 'Arena',
    'hall' => 'Hall',
    _ => kind,
  };
}
