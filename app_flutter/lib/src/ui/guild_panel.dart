import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'catalog_popup.dart';
import 'game_popup.dart';
import 'page_header.dart';
import 'player_profile_sheet.dart';
import 'social_bits.dart';

const List<(GuildRosterSort, String)> _rosterSortOptions = [
  (GuildRosterSort.oldest, 'Join date (oldest)'),
  (GuildRosterSort.newest, 'Join date (newest)'),
  (GuildRosterSort.totalLevel, 'Total level'),
  (GuildRosterSort.guildRank, 'Guild rank'),
];

String _rosterSortLabel(GuildRosterSort sort) {
  for (final option in _rosterSortOptions) {
    if (option.$1 == sort) return option.$2;
  }
  return 'Sort';
}

Future<GuildRosterSort?> _pickRosterSort(BuildContext context, GuildRosterSort current) async {
  final chosen = await showGameCatalogPopup(
    context: context,
    eyebrow: 'Sort',
    title: 'Members',
    selectable: true,
    entries: [
      for (final option in _rosterSortOptions)
        CatalogPopupEntry(title: option.$2, emphasized: option.$1 == current),
    ],
  );
  if (chosen == null) return null;
  return _rosterSortOptions[chosen].$1;
}

/// Guilds: the browser when you have none, the roster when you do.
class GuildPanel extends StatefulWidget {
  const GuildPanel({
    super.key,
    required this.controller,
    required this.multiplayer,
    this.onTravelToHall,
    this.onClose,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback? onTravelToHall;
  final VoidCallback? onClose;

  @override
  State<GuildPanel> createState() => _GuildPanelState();
}

sealed class _GuildRoute {
  const _GuildRoute();
}

class _GuildHomeRoute extends _GuildRoute {
  const _GuildHomeRoute();
}

class _GuildOthersRoute extends _GuildRoute {
  const _GuildOthersRoute();
}

class _GuildDetailRoute extends _GuildRoute {
  const _GuildDetailRoute({required this.guild, required this.mode, this.browseRow});

  final GuildRecord guild;
  final _GuildDetailMode mode;
  final GuildBrowseRow? browseRow;
}

class _GuildPanelState extends State<GuildPanel> {
  final TextEditingController _search = TextEditingController();
  final List<_GuildRoute> _routes = [const _GuildHomeRoute()];
  GuildRosterSort _sort = GuildRosterSort.oldest;
  bool _confirmingLeave = false;

  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => widget.controller.save;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _popGuild() {
    if (_routes.length > 1) {
      setState(() => _routes.removeLast());
      return;
    }
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final route = _routes.last;
    return switch (route) {
      _GuildHomeRoute() => _buildHomeOrBrowser(),
      _GuildOthersRoute() => _OtherGuildsPage(
        controller: widget.controller,
        multiplayer: net,
        onClose: _popGuild,
        onOpenDetail: (guild, row) => _pushDetail(guild, _GuildDetailMode.guestOnly, row),
      ),
      _GuildDetailRoute(:final guild, :final mode, :final browseRow) => _GuildDetailPage(
        controller: widget.controller,
        multiplayer: net,
        guild: guild,
        mode: mode,
        browseRow: browseRow,
        onClose: _popGuild,
      ),
    };
  }

  Widget _buildHomeOrBrowser() {
    final guild = net.guild;
    final body = net.guildId == null || guild == null ? _buildBrowser() : _buildHome(guild);
    if (widget.onClose == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: 'Guilds', onClose: widget.onClose!),
        Expanded(child: body),
      ],
    );
  }

  // --- Browser --------------------------------------------------------------

  Widget _buildBrowser() {
    final rows = guildBrowseRows(net.listings, _search.text);
    final form = createGuildFormView(save.gold, '');
    final listingById = <String, GuildListing>{for (final row in net.listings) row.id: row};
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(labelText: 'Search guilds', hintText: 'Name or tag…'),
          onChanged: (_) => setState(() {}),
        ),
        // Near the top, because a list of guilds is as long as the game is old
        // and a message under it is a message nobody reads.
        if (net.guestGuild case final guest?) ...[
          SocialRow(
            title: 'Guest of [${guest.tag}] ${guest.name}',
            subtitle: 'Chat only — not on their roster.',
            trailing: GameButton(
              label: 'Leave guest',
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: net.busy ? null : () => net.leaveGuest(save),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (rows.isEmpty)
          const MutedText('No guilds match that search.')
        else
          for (final row in rows) ...[
            SocialRow(
              title: row.title,
              subtitle: row.subtitle,
              leading: GuildEmblemBadge(emblem: row.emblem),
              onTap: () {
                final listing = listingById[row.guildId];
                if (listing == null) return;
                _openGuildDetail(listing.guild, mode: _GuildDetailMode.joinOrGuest, browseRow: row);
              },
            ),
            const SizedBox(height: 6),
          ],
        const SizedBox(height: 10),
        GameButton(
          label: 'Create guild (${form.goldCost} gold)',
          onPressed: net.busy ? null : _openCreateSheet,
        ),
      ],
    );
  }

  void _pushDetail(GuildRecord guild, _GuildDetailMode mode, GuildBrowseRow? browseRow) {
    setState(() {
      _routes.add(_GuildDetailRoute(guild: guild, mode: mode, browseRow: browseRow));
    });
  }

  void _openGuildDetail(
    GuildRecord guild, {
    required _GuildDetailMode mode,
    GuildBrowseRow? browseRow,
  }) {
    _pushDetail(guild, mode, browseRow);
  }

  void _openOtherGuilds() {
    setState(() => _routes.add(const _GuildOthersRoute()));
  }

  Future<void> _openCreateSheet() {
    return showGamePopup<void>(
      context: context,
      builder: (context) => GamePopupCard(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _CreateGuildSheet(gold: save.gold, onSubmit: _foundGuild),
      ),
    );
  }

  /// Founds the guild, answering the sheet with the reason it did not happen.
  ///
  /// The sheet asks for this rather than handing an input back and closing,
  /// because a refusal belongs next to the form that caused it: closing first
  /// throws away what was typed and leaves the reason at the far end of a list
  /// nobody scrolls to.
  Future<String?> _foundGuild(CreateGuildInput input) {
    return net.createGuild(input, save, (goldCost) {
      widget.controller.commit(save.copyWith(gold: (save.gold - goldCost).clamp(0, save.gold)));
    });
  }

  // --- Home -----------------------------------------------------------------

  Widget _buildHome(GuildRecord guild) {
    final header = guildHomeHeader(guild, net.members.length, net.session?.userId);
    final rows = guildRosterRows(
      guild,
      net.members,
      _sort,
      net.session?.userId,
      presence: net.presence,
      nowMs: widget.controller.session.clock(),
    );
    final options = guildRankOptions(guild);
    final applications = guildApplicationRows(net.applications);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SocialRow(
          title: header.title,
          subtitle: header.subtitle,
          leading: GuildEmblemBadge(emblem: header.emblem, size: 40),
          onTap: () => _openGuildDetail(guild, mode: _GuildDetailMode.own),
          trailing: header.canManage
              ? GameIconButton(
                  onPressed: () => _openSettingsSheet(guild),
                  tooltip: 'Guild settings',
                  icon: Icons.settings,
                )
              : null,
        ),
        const SizedBox(height: 10),
        GameButton(
          label: save.currentLocationId == guildHallLocationId ? 'In the hall' : 'Travel to hall',
          onPressed: widget.onTravelToHall,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 10),
          child: MutedText('Each guild has its own hall: a store house and a debt to work off.'),
        ),
        if (net.guestGuild case final guest?) ...[
          SocialRow(
            title: 'Guest of [${guest.tag}] ${guest.name}',
            subtitle: 'Chat only — not on their roster.',
            trailing: GameButton(
              label: 'Leave guest',
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: net.busy ? null : () => net.leaveGuest(save),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (header.canManage && applications.isNotEmpty) ...[
          const Text('Pending applications', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final row in applications) ...[
            SocialRow(
              title: row.username,
              subtitle: row.message,
              trailing: Row(
                children: [
                  GameIconButton(
                    onPressed: net.busy
                        ? null
                        : () => net.decideApplication(row.applicationId, true, save),
                    tooltip: 'Accept',
                    icon: Icons.check,
                  ),
                  GameIconButton(
                    onPressed: net.busy
                        ? null
                        : () => net.decideApplication(row.applicationId, false, save),
                    tooltip: 'Decline',
                    icon: Icons.close,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            const Expanded(
              child: Text('Members', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            GameButton(
              label: _rosterSortLabel(_sort),
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () async {
                final sort = await _pickRosterSort(context, _sort);
                if (sort != null && mounted) setState(() => _sort = sort);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final row in rows) ...[
          SocialRow(
            title: '${row.position}. ${row.username}',
            subtitle: '${row.rankLabel} · ${row.lastOnlineLabel}',
            leading: SocialPortrait(appearance: row.appearance),
            onTap: () => openPlayerProfile(
              context,
              controller: widget.controller,
              multiplayer: net,
              userId: row.userId,
            ),
            trailing: row.manageable
                ? _RankPicker(
                    role: row.role,
                    options: options,
                    onChanged: (role) => net.setMemberRole(row.userId, role, save),
                  )
                : Text('${row.totalLevel}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
        ],
        if (net.guests.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Guests', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(width: 8),
              Expanded(child: MutedText('Chat only — not in roster')),
            ],
          ),
          const SizedBox(height: 6),
          for (final guest in net.guests) ...[
            SocialRow(
              title: guest.username,
              subtitle: '',
              leading: SocialPortrait(appearance: guest.appearance),
              onTap: () => openPlayerProfile(
                context,
                controller: widget.controller,
                multiplayer: net,
                userId: guest.userId,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
        const SizedBox(height: 10),
        GameButton(label: 'Other guilds', onPressed: _openOtherGuilds),
        const SizedBox(height: 10),
        if (!_confirmingLeave)
          GameButton(
            label: 'Leave guild',
            tone: GameButtonTone.secondary,
            onPressed: () => setState(() => _confirmingLeave = true),
          )
        else ...[
          Text(leaveGuildPrompt(guild), style: const TextStyle(color: Palette.danger)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: GameButton(
                  label: 'Cancel',
                  tone: GameButtonTone.secondary,
                  onPressed: () => setState(() => _confirmingLeave = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GameButton(
                  label: 'Leave',
                  tone: GameButtonTone.secondary,
                  onPressed: net.busy
                      ? null
                      : () {
                          setState(() => _confirmingLeave = false);
                          net.leaveGuild(save);
                        },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _openSettingsSheet(GuildRecord guild) async {
    final settings = await showGamePopup<_GuildSettings>(
      context: context,
      builder: (context) => GamePopupCard(child: _GuildSettingsSheet(guild: guild)),
    );
    if (settings == null || !mounted) return;
    await net.saveGuildSettings(
      joinPolicy: settings.joinPolicy,
      guestAutoAccept: settings.guestAutoAccept,
      rankIconTheme: settings.rankIconTheme,
      emblem: settings.emblem,
      rankLabels: settings.rankLabels,
      save: save,
    );
  }
}

/// How a guild detail page treats Join / Guest actions.
enum _GuildDetailMode { own, joinOrGuest, guestOnly }

/// Full-screen list of other guilds (Guest only) while already in a guild.
class _OtherGuildsPage extends StatefulWidget {
  const _OtherGuildsPage({
    required this.controller,
    required this.multiplayer,
    required this.onClose,
    required this.onOpenDetail,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback onClose;
  final void Function(GuildRecord guild, GuildBrowseRow row) onOpenDetail;

  @override
  State<_OtherGuildsPage> createState() => _OtherGuildsPageState();
}

class _OtherGuildsPageState extends State<_OtherGuildsPage> {
  final TextEditingController _search = TextEditingController();

  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => widget.controller.save;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) {
        final ownId = net.guildId;
        final skip = <String>{?ownId, if (net.guestGuildId != null) net.guestGuildId!};
        final listings = net.listings.where((row) => !skip.contains(row.id)).toList();
        final rows = guildBrowseRows(listings, _search.text);
        final listingById = <String, GuildListing>{for (final row in listings) row.id: row};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(title: 'Other guilds', onClose: widget.onClose),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: 'Search guilds',
                      hintText: 'Name or tag…',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  if (rows.isEmpty)
                    const MutedText('No other guilds yet.')
                  else
                    for (final row in rows) ...[
                      SocialRow(
                        title: row.title,
                        subtitle: row.subtitle,
                        leading: GuildEmblemBadge(emblem: row.emblem),
                        trailing: GameButton(
                          label: row.guestLabel,
                          tone: GameButtonTone.secondary,
                          compact: true,
                          onPressed: net.busy
                              ? null
                              : () => net.joinAsGuest(
                                  row.guildId,
                                  defaultApplicationMessage(save.characterName),
                                  save,
                                ),
                        ),
                        onTap: () {
                          final listing = listingById[row.guildId];
                          if (listing == null) return;
                          widget.onOpenDetail(listing.guild, row);
                        },
                      ),
                      const SizedBox(height: 6),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Members and guests for one guild, with optional Join / Guest actions.
class _GuildDetailPage extends StatefulWidget {
  const _GuildDetailPage({
    required this.controller,
    required this.multiplayer,
    required this.guild,
    required this.mode,
    required this.onClose,
    this.browseRow,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final GuildRecord guild;
  final _GuildDetailMode mode;
  final GuildBrowseRow? browseRow;
  final VoidCallback onClose;

  @override
  State<_GuildDetailPage> createState() => _GuildDetailPageState();
}

class _GuildDetailPageState extends State<_GuildDetailPage> {
  GuildRosterSort _sort = GuildRosterSort.oldest;
  List<GuildMember>? _members;
  List<GuildGuest>? _guests;
  String? _error;
  bool _loading = true;

  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => widget.controller.save;
  GuildRecord get guild => widget.guild;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await net.service.guildMembers(guild.id);
      final guests = await net.service.guildGuests(guild.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _guests = guests;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) {
        final members = widget.mode == _GuildDetailMode.own ? net.members : _members;
        final guests = widget.mode == _GuildDetailMode.own ? net.guests : _guests;
        final header = guildHomeHeader(guild, members?.length ?? 0, net.session?.userId);
        final rows = members == null
            ? const <GuildRosterRow>[]
            : guildRosterRows(
                guild,
                members,
                _sort,
                widget.mode == _GuildDetailMode.own ? net.session?.userId : null,
                presence: widget.mode == _GuildDetailMode.own ? net.presence : const [],
                nowMs: widget.controller.session.clock(),
              );
        final browse = widget.browseRow;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(title: header.title, onClose: widget.onClose),
            Expanded(
              child: _loading && widget.mode != _GuildDetailMode.own
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        SocialRow(
                          title: header.title,
                          subtitle: header.subtitle,
                          leading: GuildEmblemBadge(emblem: header.emblem, size: 40),
                        ),
                        if (_error case final error?) ...[
                          const SizedBox(height: 8),
                          Text(error, style: const TextStyle(color: Palette.danger)),
                        ],
                        if (browse != null && widget.mode != _GuildDetailMode.own) ...[
                          const SizedBox(height: 10),
                          if (widget.mode == _GuildDetailMode.joinOrGuest)
                            Row(
                              children: [
                                Expanded(
                                  child: GameButton(
                                    label: browse.actionLabel,
                                    tone: GameButtonTone.secondary,
                                    compact: true,
                                    onPressed: browse.full || net.busy
                                        ? null
                                        : () => net.applyToGuild(
                                            browse.guildId,
                                            defaultApplicationMessage(save.characterName),
                                            save,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GameButton(
                                    label: browse.guestLabel,
                                    tone: GameButtonTone.secondary,
                                    compact: true,
                                    onPressed: net.busy || net.guestGuildId == browse.guildId
                                        ? null
                                        : () => net.joinAsGuest(
                                            browse.guildId,
                                            defaultApplicationMessage(save.characterName),
                                            save,
                                          ),
                                  ),
                                ),
                              ],
                            )
                          else
                            GameButton(
                              label: browse.guestLabel,
                              tone: GameButtonTone.secondary,
                              compact: true,
                              onPressed: net.busy || net.guestGuildId == browse.guildId
                                  ? null
                                  : () => net.joinAsGuest(
                                      browse.guildId,
                                      defaultApplicationMessage(save.characterName),
                                      save,
                                    ),
                            ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Members', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            GameButton(
                              label: _rosterSortLabel(_sort),
                              tone: GameButtonTone.secondary,
                              compact: true,
                              onPressed: () async {
                                final sort = await _pickRosterSort(context, _sort);
                                if (sort != null && mounted) setState(() => _sort = sort);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (rows.isEmpty)
                          const MutedText('No members yet.')
                        else
                          for (final row in rows) ...[
                            SocialRow(
                              title: '${row.position}. ${row.username}',
                              subtitle: '${row.rankLabel} · ${row.lastOnlineLabel}',
                              leading: SocialPortrait(appearance: row.appearance),
                              onTap: () => openPlayerProfile(
                                context,
                                controller: widget.controller,
                                multiplayer: net,
                                userId: row.userId,
                              ),
                              trailing: Text(
                                '${row.totalLevel}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                        if (guests != null && guests.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('Guests', style: TextStyle(fontWeight: FontWeight.w700)),
                              SizedBox(width: 8),
                              Expanded(child: MutedText('Chat only — not in roster')),
                            ],
                          ),
                          const SizedBox(height: 6),
                          for (final guest in guests) ...[
                            SocialRow(
                              title: guest.username,
                              subtitle: '',
                              leading: SocialPortrait(appearance: guest.appearance),
                              onTap: () => openPlayerProfile(
                                context,
                                controller: widget.controller,
                                multiplayer: net,
                                userId: guest.userId,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _RankPicker extends StatelessWidget {
  const _RankPicker({required this.role, required this.options, required this.onChanged});

  final GuildRole role;
  final List<GuildRankOption> options;
  final ValueChanged<GuildRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return GameButton(
      label: options
          .where((option) => option.role == role)
          .map((option) => option.label)
          .firstOrNull ??
          role,
      tone: GameButtonTone.secondary,
      compact: true,
      onPressed: () async {
        final chosen = await showGameCatalogPopup(
          context: context,
          eyebrow: 'Rank',
          title: 'Guild rank',
          selectable: true,
          entries: [
            for (final option in options)
              CatalogPopupEntry(title: option.label, emphasized: option.role == role),
          ],
        );
        if (chosen == null) return;
        final next = options[chosen].role;
        if (next != role) onChanged(next);
      },
    );
  }
}

/// The emblem picker: a color, then a mark.
class _EmblemEditor extends StatelessWidget {
  const _EmblemEditor({required this.emblem, required this.onChanged});

  final GuildEmblem emblem;
  final ValueChanged<GuildEmblem> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GuildEmblemBadge(emblem: emblem, size: 44),
            const SizedBox(width: 10),
            const MutedText('Color + solid icon'),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: guildEmblemColors
              .map(
                (color) => _Swatch(
                  color: color,
                  selected: color == emblem.color,
                  onTap: () => onChanged(GuildEmblem(color: color, symbol: emblem.symbol)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: guildEmblemSymbols
              .map(
                (symbol) => _SymbolButton(
                  symbol: symbol,
                  selected: symbol == emblem.symbol,
                  onTap: () => onChanged(GuildEmblem(color: emblem.color, symbol: symbol)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final String color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Color(0xFF000000 | (int.tryParse(color.replaceFirst('#', ''), radix: 16) ?? 0)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Palette.gold : Palette.edge,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _SymbolButton extends StatelessWidget {
  const _SymbolButton({required this.symbol, required this.selected, required this.onTap});

  final String symbol;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Palette.gold : Palette.edge,
            width: selected ? 2 : 1,
          ),
        ),
        child: GuildEmblemMark(symbol: symbol),
      ),
    );
  }
}

class _CreateGuildSheet extends StatefulWidget {
  const _CreateGuildSheet({required this.gold, required this.onSubmit});

  final num gold;

  /// Founds the guild, answering with why it did not happen.
  final Future<String?> Function(CreateGuildInput input) onSubmit;

  @override
  State<_CreateGuildSheet> createState() => _CreateGuildSheetState();
}

class _CreateGuildSheetState extends State<_CreateGuildSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _tag = TextEditingController();
  GuildEmblem _emblem = GuildEmblem(
    color: guildEmblemColors.first,
    symbol: guildEmblemSymbols.first,
  );
  bool _sending = false;

  /// What the last press was told, which outranks what the form guessed.
  String? _refused;

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _refused = null;
    });
    final refused = await widget.onSubmit(
      CreateGuildInput(name: _name.text, tag: _tag.text, emblem: _emblem),
    );
    if (!mounted) return;
    if (refused == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _sending = false;
      _refused = refused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final form = createGuildFormView(widget.gold, _tag.text, name: _name.text);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create guild', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            MutedText(form.costLine),
            const SizedBox(height: 12),
            TextField(
              controller: _tag,
              decoration: const InputDecoration(labelText: 'Tag (2–4 letters)', hintText: 'EG'),
              onChanged: (raw) {
                final cleaned = sanitizeGuildTagInput(raw);
                if (cleaned != raw) {
                  _tag.value = TextEditingValue(
                    text: cleaned,
                    selection: TextSelection.collapsed(offset: cleaned.length),
                  );
                }
                setState(() {});
              },
            ),
            const SizedBox(height: 4),
            MutedText('Preview: ${form.tagPreview}'),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              maxLength: 28,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            _EmblemEditor(emblem: _emblem, onChanged: (next) => setState(() => _emblem = next)),
            const SizedBox(height: 12),
            // Whatever is missing is said here, above a button that always
            // presses. A greyed-out button reads as a game that is broken, and
            // one labelled with its own complaint still does nothing when
            // pressed, so the complaint gets its own line.
            if (_refused ?? form.refusal case final reason?) ...[
              Text(reason, style: const TextStyle(color: Palette.danger)),
              const SizedBox(height: 6),
            ],
            GameButton(
              label: _sending ? 'Creating…' : form.submitLabel,
              onPressed: _sending ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the settings sheet hands back, so the controller saves it in one go.
class _GuildSettings {
  const _GuildSettings({
    required this.joinPolicy,
    required this.guestAutoAccept,
    required this.rankIconTheme,
    required this.emblem,
    required this.rankLabels,
  });

  final GuildJoinPolicy joinPolicy;
  final bool guestAutoAccept;
  final String rankIconTheme;
  final GuildEmblem emblem;
  final Map<GuildRankKey, String> rankLabels;
}

class _GuildSettingsSheet extends StatefulWidget {
  const _GuildSettingsSheet({required this.guild});

  final GuildRecord guild;

  @override
  State<_GuildSettingsSheet> createState() => _GuildSettingsSheetState();
}

class _GuildSettingsSheetState extends State<_GuildSettingsSheet> {
  late GuildJoinPolicy _policy = widget.guild.joinPolicy;
  late bool _guestAutoAccept = widget.guild.guestAutoAccept;
  late String _rankIconTheme = widget.guild.rankIconTheme;
  late GuildEmblem _emblem = widget.guild.emblem;
  late final Map<GuildRankKey, TextEditingController> _labels =
      <GuildRankKey, TextEditingController>{
        for (final field in rankLabelFields(widget.guild))
          field.role: TextEditingController(text: field.value),
      };

  @override
  void dispose() {
    for (final controller in _labels.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Guild settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            GameSelectField(
              label: 'Join policy',
              value: _policy == guildJoinOpen ? 'Accept applications' : 'Closed',
              onPressed: () async {
                final chosen = await showGameCatalogPopup(
                  context: context,
                  eyebrow: 'Join policy',
                  title: 'Guild settings',
                  selectable: true,
                  entries: const [
                    CatalogPopupEntry(title: 'Accept applications'),
                    CatalogPopupEntry(title: 'Closed'),
                  ],
                );
                if (chosen == null || !mounted) return;
                setState(() => _policy = chosen == 0 ? guildJoinOpen : guildJoinClosed);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Guest auto-accept', style: TextStyle(fontWeight: FontWeight.w700)),
                      MutedText('Guests join chat without an application.'),
                    ],
                  ),
                ),
                GameSwitch(
                  value: _guestAutoAccept,
                  onChanged: (value) => setState(() => _guestAutoAccept = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GameSelectField(
              label: 'Rank icons',
              value: _rankIconTheme == guildRankIconThemeCrowns
                  ? 'Crowns and pips'
                  : 'Army stripes',
              onPressed: () async {
                final chosen = await showGameCatalogPopup(
                  context: context,
                  eyebrow: 'Rank icons',
                  title: 'Guild settings',
                  selectable: true,
                  entries: const [
                    CatalogPopupEntry(title: 'Army stripes'),
                    CatalogPopupEntry(title: 'Crowns and pips'),
                  ],
                );
                if (chosen == null || !mounted) return;
                setState(
                  () => _rankIconTheme = chosen == 1
                      ? guildRankIconThemeCrowns
                      : guildRankIconThemeStripes,
                );
              },
            ),
            const SizedBox(height: 12),
            _EmblemEditor(emblem: _emblem, onChanged: (next) => setState(() => _emblem = next)),
            const SizedBox(height: 12),
            const Text('Rank names', style: TextStyle(fontWeight: FontWeight.w700)),
            const MutedText('Rename Leader and the four promotable ranks.'),
            const SizedBox(height: 6),
            for (final field in rankLabelFields(widget.guild)) ...[
              TextField(
                controller: _labels[field.role],
                maxLength: 18,
                decoration: InputDecoration(labelText: field.fieldLabel),
              ),
            ],
            const SizedBox(height: 6),
            GameButton(
              label: 'Save settings',
              onPressed: () => Navigator.of(context).pop(
                _GuildSettings(
                  joinPolicy: _policy,
                  guestAutoAccept: _guestAutoAccept,
                  rankIconTheme: _rankIconTheme,
                  emblem: _emblem,
                  rankLabels: <GuildRankKey, String>{
                    for (final entry in _labels.entries) entry.key: entry.value.text,
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
