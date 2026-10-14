import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/plaza_points.dart';
import 'package:ik_rules/ik_rules.dart';

void main() {
  group('plazaPointsGainedNotice', () {
    test('bounty and ranked show nothing when pointsGained is missing or 0', () {
      expect(plazaPointsGainedNotice(null), isNull);
      expect(plazaPointsGainedNotice(0), isNull);
      expect(plazaPointsGainedNotice(-4), isNull);
      expect(plazaPointsGainedNotice(double.nan), isNull);
    });

    test('bounty and ranked show +N plaza points from pointsGained', () {
      expect(plazaPointsGainedNotice(25), '+25 plaza points');
      expect(plazaPointsGainedNotice(rankedPvpWinPoints), '+25 plaza points');
      expect(plazaPointsGainedNotice(25.9), '+25 plaza points');
      expect(plazaPointsGainedNotice(1200), '+1,200 plaza points');
    });
  });

  test('a row with no catalog price shows the unknown-item reason', () {
    expect(plazaShopPriceLabel(null), plazaShopUnknownItem);
    expect(plazaShopPriceLabel(210), '210 plaza points');
  });

  group('plazaPointsSpentNotice', () {
    test('shows nothing when the field is missing or 0', () {
      expect(plazaPointsSpentNotice(null), isNull);
      expect(plazaPointsSpentNotice(0), isNull);
      expect(plazaPointsSpentNotice(-4), isNull);
    });

    test('shows -N plaza points from pointsSpent', () {
      expect(plazaPointsSpentNotice(210), '-210 plaza points');
      expect(plazaPointsSpentNotice(210.4), '-210 plaza points');
    });
  });
}
