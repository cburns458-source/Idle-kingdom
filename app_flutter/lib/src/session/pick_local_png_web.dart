import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'local_player_art.dart';
import 'pick_local_png_types.dart';

/// Held so the input is not collected before the player finishes choosing.
web.HTMLInputElement? _activePicker;

/// Opens a PNG file picker and returns the chosen bytes, a refusal, or cancel.
Future<PickedLocalPng> pickLocalPng({int? maxBytes}) {
  final cap = maxBytes ?? LocalPlayerArt.maxBytes;
  final completer = Completer<PickedLocalPng>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/png,.png';
  _activePicker = input;

  void finish(PickedLocalPng result) {
    if (!completer.isCompleted) completer.complete(result);
    if (identical(_activePicker, input)) _activePicker = null;
  }

  input.onchange = (web.Event event) {
    final files = input.files;
    final file = files == null || files.length == 0 ? null : files.item(0);
    if (file == null) {
      finish(const PickedLocalPng.cancelled());
      return;
    }
    unawaited(_readPng(file, cap).then(finish));
  }.toJS;

  input.oncancel = (web.Event event) {
    finish(const PickedLocalPng.cancelled());
  }.toJS;

  input.click();
  return completer.future;
}

Future<PickedLocalPng> _readPng(web.File file, int maxBytes) async {
  if (file.size > maxBytes) {
    return const PickedLocalPng.failed(LocalPlayerArt.tooLargeMessage);
  }
  try {
    final buffer = await file.arrayBuffer().toDart;
    return PickedLocalPng.ok(buffer.toDart.asUint8List());
  } on Object {
    return const PickedLocalPng.failed('Could not read that file.');
  }
}
