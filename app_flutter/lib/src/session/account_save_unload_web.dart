import 'dart:js_interop';

@JS('window.addEventListener')
external void _addEventListener(JSString type, JSFunction listener);

/// Flushes the account save when the browser tab is hiding or unloading.
void listenForPageUnload(void Function() flush) {
  void handle(JSAny? _) => flush();
  _addEventListener('pagehide'.toJS, handle.toJS);
}
