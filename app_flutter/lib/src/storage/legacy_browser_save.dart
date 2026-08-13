/// The save the React client left in the browser, where there is a browser.
///
/// `shared_preferences` namespaces its web keys, so a save written by the old
/// client sits beside the Flutter one rather than being found by it. Reading the
/// bare key is a one-time courtesy for a player opening the new client at the
/// address the old one was served from.
library;

export 'legacy_browser_save_stub.dart' if (dart.library.js_interop) 'legacy_browser_save_web.dart';
