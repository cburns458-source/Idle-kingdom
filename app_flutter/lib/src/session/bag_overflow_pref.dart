import 'package:ik_runtime/ik_runtime.dart';

/// Client-only mark that loot was left behind because the bag was full.
///
/// Lives on this device — it is not written into the save — so a restart still
/// shows the bag-tab badge until the player opens the bag.
class BagOverflowPref {
  BagOverflowPref({this.storage, bool? hasBadge}) : _hasBadge = hasBadge ?? false;

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String storageKey = 'idle-kingdoms.client.bag-overflow-badge';

  final SaveStorage? storage;
  bool _hasBadge;

  bool get hasBadge => _hasBadge;

  factory BagOverflowPref.load(SaveStorage? storage) {
    final stored = storage?.getItem(storageKey);
    return BagOverflowPref(storage: storage, hasBadge: stored == '1');
  }

  void setHasBadge(bool value) {
    _hasBadge = value;
    storage?.setItem(storageKey, value ? '1' : '0');
  }
}
