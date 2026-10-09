/// Client-side parse of a developer chat line (`/give …`).
///
/// Authorization and mutation live on the server. This only splits the line so
/// the chat composer can intercept it before `send-chat`.
library;

import 'package:ik_rules/ik_rules.dart';

class ParsedDevCommand {
  const ParsedDevCommand({required this.command, required this.tokens});

  final String command;
  final List<String> tokens;
}

/// Result of a hosted `dev_command` invoke.
class DevCommandInvokeResult {
  const DevCommandInvokeResult.ok({required PlayerSave this.save, required this.message})
    : reason = null;

  const DevCommandInvokeResult.failed(this.reason) : save = null, message = null;

  final PlayerSave? save;
  final String? message;
  final String? reason;

  bool get ok => reason == null;
}

/// Returns null when [line] is not a slash command.
ParsedDevCommand? parseDevCommandLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('/')) return null;
  final body = trimmed.substring(1).trim();
  if (body.isEmpty) return const ParsedDevCommand(command: 'help', tokens: <String>[]);
  final parts = body.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  final command = parts.first.toLowerCase();
  return ParsedDevCommand(command: command, tokens: parts.skip(1).toList());
}
