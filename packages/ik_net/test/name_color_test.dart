import 'package:ik_net/ik_net.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes #RGB and #RRGGBB, with or without #', () {
    expect(normalizeNameColorHex('#FA3'), '#FFAA33');
    expect(normalizeNameColorHex('fa3'), '#FFAA33');
    expect(normalizeNameColorHex('#d4af37'), '#D4AF37');
    expect(normalizeNameColorHex('D4AF37'), '#D4AF37');
    expect(normalizeNameColorHex('  #abc  '), '#AABBCC');
  });

  test('rejects empty or invalid hex', () {
    expect(normalizeNameColorHex(null), isNull);
    expect(normalizeNameColorHex(''), isNull);
    expect(normalizeNameColorHex('gold'), isNull);
    expect(normalizeNameColorHex('#GG0000'), isNull);
    expect(normalizeNameColorHex('#12'), isNull);
    expect(normalizeNameColorHex('#1234'), isNull);
    expect(normalizeNameColorHex('#1234567'), isNull);
  });

  test('stores the draft per account', () {
    expect(nameColorStorageKey('usr_1'), 'idle-kingdoms.client.name-color:usr_1');
  });
}
