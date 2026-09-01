import 'package:flutter/material.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// Client-only toggle that skips cosmetic motion and paints the UI less often.
///
/// Default is off. The choice stays on this device — it is not written into
/// the save or the account row.
class BatterySaverPref {
  BatterySaverPref({this.storage, bool? enabled}) : _enabled = enabled ?? false;

  /// Not [saveStorageKey], so an export or a cloud write cannot pick this up.
  static const String storageKey = 'idle-kingdoms.client.battery-saver';

  final SaveStorage? storage;
  bool _enabled;

  bool get enabled => _enabled;

  factory BatterySaverPref.load(SaveStorage? storage) {
    final stored = storage?.getItem(storageKey);
    return BatterySaverPref(storage: storage, enabled: stored == '1');
  }

  void setEnabled(bool value) {
    _enabled = value;
    storage?.setItem(storageKey, value ? '1' : '0');
  }
}

/// Lets overlays and popups read the saver without threading the controller.
class BatterySaverScope extends InheritedWidget {
  const BatterySaverScope({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BatterySaverScope>()?.enabled ?? false;
  }

  @override
  bool updateShouldNotify(BatterySaverScope oldWidget) => enabled != oldWidget.enabled;
}
