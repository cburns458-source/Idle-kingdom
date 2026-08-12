import 'package:ik_parity/ik_parity.dart';
import 'package:test/test.dart';

void main() {
  group('canonicalJson', () {
    test('sorts object keys so encoding is order independent', () {
      expect(canonicalJson({'b': 1, 'a': 2}), '{"a":2,"b":1}');
      expect(canonicalEquals({'b': 1, 'a': 2}, {'a': 2, 'b': 1}), isTrue);
    });

    test('encodes int and integral double identically', () {
      expect(canonicalNumber(1), '1');
      expect(canonicalNumber(1.0), '1');
      expect(canonicalNumber(-0.0), '0');
      expect(canonicalNumber(1.0000001), '1.0000001');
    });

    test('treats a null value as distinct from an absent key', () {
      expect(canonicalJson({'a': 1}), '{"a":1}');
      expect(canonicalJson({'a': 1, 'b': null}), '{"a":1,"b":null}');
    });

    test('rejects values that cannot round-trip', () {
      expect(() => canonicalJson(double.nan), throwsArgumentError);
      expect(() => canonicalJson(double.infinity), throwsArgumentError);
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      expect(() => canonicalJson(cyclic), throwsArgumentError);
    });
  });
}
