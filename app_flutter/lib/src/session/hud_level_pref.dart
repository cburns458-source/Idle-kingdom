import 'package:ik_runtime/ik_runtime.dart';

/// Client-only HUD toggle between total level and total XP.
///
/// Default is level. A tap on the HUD identity line flips it, and the choice
/// stays on this device — it is not written into the save.
class HudLevelPref {
  HudLevelPref({this.storage, bool? showTotalXp}) : _showTotalXp = showTotalXp ?? false;

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String storageKey = 'idle-kingdoms.client.hud-show-total-xp';

  final SaveStorage? storage;
  bool _showTotalXp;

  bool get showTotalXp => _showTotalXp;

  factory HudLevelPref.load(SaveStorage? storage) {
    final stored = storage?.getItem(storageKey);
    return HudLevelPref(storage: storage, showTotalXp: stored == '1');
  }

  void setShowTotalXp(bool value) {
    _showTotalXp = value;
    storage?.setItem(storageKey, value ? '1' : '0');
  }

  void toggle() => setShowTotalXp(!_showTotalXp);
}
