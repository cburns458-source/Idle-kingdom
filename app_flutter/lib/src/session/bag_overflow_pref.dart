import 'package:ik_runtime/ik_runtime.dart';

/// Client-only mark that loot was left behind because the bag was full.
///
/// Lives on this device — it is not written into the save — so a restart still
/// shows the bag-tab badge until the player opens the bag. The key is the
/// save's [createdAt], which stays put across a rename. A leftover name-keyed
/// value from an older build is copied across once and then deleted.
class BagOverflowPref {
  BagOverflowPref({this.storage, String? identity, bool? hasBadge})
    : _identity = normalizeIdentity(identity),
      _hasBadge = hasBadge ?? false;

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String keyPrefix = 'idle-kingdoms.client.bag-overflow-badge';

  /// Used when the device has no save stamp (signed out / empty createdAt).
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

  /// Stable key for a save: [createdAt] does not change when the name does.
  static String identityForCreatedAt(String? createdAt) => normalizeIdentity(createdAt);

  static String storageKeyFor(String? identity) => '$keyPrefix.${normalizeIdentity(identity)}';

  factory BagOverflowPref.load(SaveStorage? storage, {String? identity, String? legacyName}) {
    final pref = BagOverflowPref(storage: storage, identity: identity);
    pref._readOrMigrate(legacyName);
    return pref;
  }

  /// Switches to [identity]'s stored badge. Does not copy the previous save's mark.
  ///
  /// When [identity] has no stored value, [legacyName] is read once, written
  /// under [identity], and then removed so a leftover name-keyed value from an
  /// older build still shows the badge.
  void bindTo(String? identity, {String? legacyName}) {
    _identity = normalizeIdentity(identity);
    _readOrMigrate(legacyName);
  }

  void bindToCreatedAt(String? createdAt, {String? legacyName}) {
    bindTo(identityForCreatedAt(createdAt), legacyName: legacyName);
  }

  void setHasBadge(bool value) {
    _hasBadge = value;
    storage?.setItem(storageKeyFor(_identity), value ? '1' : '0');
  }

  void _readOrMigrate(String? legacyName) {
    final stored = storage?.getItem(storageKeyFor(_identity));
    if (stored == '1' || stored == '0') {
      _hasBadge = stored == '1';
      return;
    }
    final name = legacyName?.trim() ?? '';
    if (name.isEmpty) {
      _hasBadge = false;
      return;
    }
    final legacyKey = storageKeyFor(name);
    if (legacyKey == storageKeyFor(_identity)) {
      _hasBadge = storage?.getItem(legacyKey) == '1';
      return;
    }
    final legacy = storage?.getItem(legacyKey);
    if (legacy != '1' && legacy != '0') {
      _hasBadge = false;
      return;
    }
    storage?.setItem(storageKeyFor(_identity), legacy!);
    storage?.removeItem(legacyKey);
    _hasBadge = legacy == '1';
  }
}
