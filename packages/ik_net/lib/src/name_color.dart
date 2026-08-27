/// Chat name colors are account-wide hex codes published on a ranking submit.

final _hex3 = RegExp(r'^[0-9a-fA-F]{3}$');
final _hex6 = RegExp(r'^[0-9a-fA-F]{6}$');

String nameColorStorageKey(String userId) => 'idle-kingdoms.client.name-color:$userId';

/// Accepts `#RGB` or `#RRGGBB`, with or without `#`. Returns `#RRGGBB` or null.
String? normalizeNameColorHex(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (_hex3.hasMatch(value)) {
    return '#${value[0]}${value[0]}${value[1]}${value[1]}${value[2]}${value[2]}'.toUpperCase();
  }
  if (_hex6.hasMatch(value)) return '#${value.toUpperCase()}';
  return null;
}
