import 'package:ik_runtime/ik_runtime.dart';

/// Client-only toggle for the map-node travel tween. Default is off, so travel
/// is instant until a player opts into watching the walk.
class MapTravelPref {
  MapTravelPref({this.storage, bool? enabled}) : _enabled = enabled ?? false;

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String storageKey = 'idle-kingdoms.client.map-travel-animation';

  final SaveStorage? storage;
  bool _enabled;

  bool get enabled => _enabled;

  factory MapTravelPref.load(SaveStorage? storage) {
    final stored = storage?.getItem(storageKey);
    return MapTravelPref(storage: storage, enabled: stored == '1');
  }

  void setEnabled(bool value) {
    _enabled = value;
    storage?.setItem(storageKey, value ? '1' : '0');
  }
}
