import 'package:ik_runtime/ik_runtime.dart';

/// Client-only mark that loot was left behind because the bag was full.
///
/// Lives on this device — it is not written into the save — so a restart still
/// shows the bag-tab badge until the player opens the bag. The key is per
/// account/save so a new character does not inherit another save's badge.
class BagOverflowPref {
  BagOverflowPref({this.storage, String? identity, bool? hasBadge})
    : _identity = normalizeIdentity(identity),
      _hasBadge = hasBadge ?? false;

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String keyPrefix = 'idle-kingdoms.client.bag-overflow-badge';

  /// Used when the device has no named character (signed out / new save).
  static const String unsignedIdentity = 'unsigned';

  final SaveStorage? storage;
  String _identity;
  bool _hasBadge;

  bool get hasBadge => _hasBadge;

  String get identity => _identity;

  /// Storage key for the save this pref is currently bound to.
  String get storageKey => storageKeyFor(_identity);

  static String normalizeIdentity(String? identity) {
    final cleaned = identity?.trim() ?? '';
    return cleaned.isEmpty ? unsignedIdentity : cleaned;
  }

  static String storageKeyFor(String? identity) => '$keyPrefix.${normalizeIdentity(identity)}';

  factory BagOverflowPref.load(SaveStorage? storage, {String? identity}) {
    final id = normalizeIdentity(identity);
    final stored = storage?.getItem(storageKeyFor(id));
    return BagOverflowPref(storage: storage, identity: id, hasBadge: stored == '1');
  }

  /// Switches to [identity]'s stored badge. Does not copy the previous save's mark.
  void bindTo(String? identity) {
    final next = normalizeIdentity(identity);
    if (next == _identity) return;
    _identity = next;
    _hasBadge = storage?.getItem(storageKeyFor(next)) == '1';
  }

  void setHasBadge(bool value) {
    _hasBadge = value;
    storage?.setItem(storageKeyFor(_identity), value ? '1' : '0');
  }
}
