import 'package:ik_runtime/ik_runtime.dart';

/// Client-only HUD toggle for the equipped character title.
///
/// Default is on, matching the current HUD. Turning it off hides the title
/// on the HUD only — the Wardrobe and Settings name still show it.
class HudTitlePref {
  HudTitlePref({this.storage, bool? showTitle}) : _showTitle = showTitle ?? true;

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String storageKey = 'idle-kingdoms.client.hud-show-title';

  final SaveStorage? storage;
  bool _showTitle;

  bool get showTitle => _showTitle;

  factory HudTitlePref.load(SaveStorage? storage) {
    final stored = storage?.getItem(storageKey);
    if (stored == '0') return HudTitlePref(storage: storage, showTitle: false);
    return HudTitlePref(storage: storage, showTitle: true);
  }

  void setShowTitle(bool value) {
    _showTitle = value;
    storage?.setItem(storageKey, value ? '1' : '0');
  }
}
