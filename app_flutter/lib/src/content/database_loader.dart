import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ik_content/ik_content.dart';

/// Reads the bundled copy of the shared database.
///
/// `ik_content` deliberately does no IO, so getting the bytes is the client's
/// job; the parsing, validation, and index building are all shared.
Future<LoadedDatabase> loadBundledDatabase() async {
  final raw = await rootBundle.loadString('content/$databaseAssetPath');
  return prepareDatabase(jsonDecode(raw));
}
