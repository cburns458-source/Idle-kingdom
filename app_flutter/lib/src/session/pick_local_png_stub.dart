import 'pick_local_png_types.dart';

/// Native and tests have no file input; the Menu button still reports that.
Future<PickedLocalPng> pickLocalPng({int? maxBytes}) async {
  return const PickedLocalPng.unavailable();
}
