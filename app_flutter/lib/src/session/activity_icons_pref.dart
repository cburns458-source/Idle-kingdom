import 'package:ik_runtime/ik_runtime.dart';

/// Client-only toggle for skill and shop icons on the map location popup.
///
/// Default is on. Turning it off hides those icons on the popup only — map
/// nodes themselves never show them.
class ActivityIconsPref {
  ActivityIconsPref({this.storage, bool? showIcons}) : _showIcons = showIcons ?? true;

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String storageKey = 'idle-kingdoms.client.map-activity-icons';

  final SaveStorage? storage;
  bool _showIcons;

  bool get showIcons => _showIcons;

  factory ActivityIconsPref.load(SaveStorage? storage) {
    final stored = storage?.getItem(storageKey);
    if (stored == '0') return ActivityIconsPref(storage: storage, showIcons: false);
    return ActivityIconsPref(storage: storage, showIcons: true);
  }

  void setShowIcons(bool value) {
    _showIcons = value;
    storage?.setItem(storageKey, value ? '1' : '0');
  }
}
