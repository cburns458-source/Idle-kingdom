/// The multiplayer port, shared by every Dart client.
///
/// Ported from `src/game/multiplayer`. Nothing here reaches for a clock, a
/// random number, or a network client directly: the local backend takes both
/// time and ids as ports so it replays identically against the TypeScript
/// fixtures, and a remote backend arrives as another [MultiplayerService].
library;

export 'src/bazaar.dart';
export 'src/bounty_turn_in.dart';
export 'src/cloud_save.dart';
export 'src/config.dart';
export 'src/demo_world.dart';
export 'src/emblems.dart';
export 'src/guild_rules.dart';
export 'src/local_backend.dart';
export 'src/local_db.dart';
export 'src/moderation.dart';
export 'src/name_color.dart';
export 'src/noted_reads.dart';
export 'src/presence.dart';
export 'src/ranking_update.dart';
export 'src/remote.dart';
export 'src/remote_guild_backend.dart';
export 'src/remote_guilds.dart';
export 'src/remote_service.dart';
export 'src/remote_transport.dart';
export 'src/results.dart';
export 'src/service.dart';
export 'src/session_store.dart';
export 'src/snapshots.dart';
export 'src/types.dart';
export 'src/views.dart';
