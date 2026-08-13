import 'package:web/web.dart' as web;

/// The value the React client stored under the bare save key, if it is still there.
///
/// Left in place after it is adopted: it costs nothing, and a player who wants
/// the old client back should still find their character in it.
String? readLegacyBrowserSave(String key) => web.window.localStorage.getItem(key);
