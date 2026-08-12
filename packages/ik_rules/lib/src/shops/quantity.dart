import '../js_compat.dart';

/// A parsed shop buy/sell quantity, or why the typed text was rejected.
class ShopQuantity {
  const ShopQuantity.ok(this.quantity) : reason = null;

  const ShopQuantity.failed(this.reason) : quantity = 0;

  bool get ok => reason == null;
  final num quantity;
  final String? reason;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'quantity': quantity}
      : <String, Object?>{'ok': false, 'reason': reason};
}

final RegExp _digits = RegExp(r'^\d+$');

/// Parses a typed quantity. [max] clamps it to what is left to sell.
ShopQuantity parseShopQuantity(String raw, [num? max]) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const ShopQuantity.failed('Enter a quantity.');
  if (!_digits.hasMatch(trimmed)) return const ShopQuantity.failed('Enter a whole number.');
  final quantity = jsNumber(trimmed);
  if (!_isSafeInteger(quantity) || quantity < 1) {
    return const ShopQuantity.failed('Quantity must be at least 1.');
  }
  if (max != null && quantity > max) {
    return ShopQuantity.failed(
      max <= 0 ? 'Nothing left to sell.' : 'You can sell at most ${jsNumberToString(max)}.',
    );
  }
  return ShopQuantity.ok(quantity);
}

/// `Number.isSafeInteger(value)`.
bool _isSafeInteger(num value) {
  return jsIsInteger(value) && value.abs() <= 9007199254740991;
}
