import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'social_bits.dart';

/// Guilds: the browser when you have none, the roster when you do.
class GuildPanel extends StatefulWidget {
  const GuildPanel({super.key, required this.controller, required this.multiplayer});

  final GameController controller;
  final MultiplayerController multiplayer;

  @override
  State<GuildPanel> createState() => _GuildPanelState();
}

class _GuildPanelState extends State<GuildPanel> {
  final TextEditingController _search = TextEditingController();
  GuildRosterSort _sort = GuildRosterSort.oldest;
  bool _confirmingLeave = false;

  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => widget.controller.save;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guild = net.guild;
    if (net.guildId == null || guild == null) return _buildBrowser();
    return _buildHome(guild);
  }

  // --- Browser --------------------------------------------------------------

  Widget _buildBrowser() {
    final rows = guildBrowseRows(net.listings, _search.text);
    final form = createGuildFormView(save.gold, '');
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(labelText: 'Search guilds', hintText: 'Name or tag…'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const MutedText('No guilds match that search.')
        else
          for (final row in rows) ...[
            SocialRow(
              title: row.title,
              subtitle: row.subtitle,
              leading: GuildEmblemBadge(emblem: row.emblem),
              trailing: OutlinedButton(
                onPressed: row.full || net.busy
                    ? null
                    : () => net.applyToGuild(
                        row.guildId,
                        defaultApplicationMessage(save.characterName),
                        save,
                      ),
                child: Text(row.actionLabel),
              ),
            ),
            const SizedBox(height: 6),
          ],
        const SizedBox(height: 10),
        FilledButton(
          onPressed: net.busy ? null : _openCreateSheet,
          child: Text('Create guild (${form.goldCost} gold)'),
        ),
        SocialNotice(notice: net.notice),
      ],
    );
  }

  Future<void> _openCreateSheet() async {
    final input = await showModalBottomSheet<CreateGuildInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.parchmentDeep,
      builder: (context) => _CreateGuildSheet(gold: save.gold),
    );
    if (input == null || !mounted) return;
    await net.createGuild(input, save, (goldCost) {
      widget.controller.commit(save.copyWith(gold: (save.gold - goldCost).clamp(0, save.gold)));
    });
  }

  // --- Home -----------------------------------------------------------------

  Widget _buildHome(GuildRecord guild) {
    final header = guildHomeHeader(guild, net.members.length, net.session?.userId);
    final rows = guildRosterRows(guild, net.members, _sort, net.session?.userId);
    final options = guildRankOptions(guild);
    final applications = guildApplicationRows(net.applications);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SocialRow(
          title: header.title,
          subtitle: header.subtitle,
          leading: GuildEmblemBadge(emblem: header.emblem, size: 40),
          trailing: header.canManage
              ? IconButton(
                  onPressed: () => _openSettingsSheet(guild),
                  tooltip: 'Guild settings',
                  icon: const Icon(Icons.settings, size: 20),
                )
              : null,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Text('Members', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            DropdownButton<GuildRosterSort>(
              value: _sort,
              underline: const SizedBox.shrink(),
              items: const <DropdownMenuItem<GuildRosterSort>>[
                DropdownMenuItem(value: GuildRosterSort.oldest, child: Text('Join date (oldest)')),
                DropdownMenuItem(value: GuildRosterSort.newest, child: Text('Join date (newest)')),
              ],
              onChanged: (sort) {
                if (sort != null) setState(() => _sort = sort);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final row in rows) ...[
          SocialRow(
            title: '${row.position}. ${row.username}',
            subtitle: row.rankLabel,
            leading: SocialPortrait(appearance: row.appearance),
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
        if (header.canManage && applications.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Pending applications', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final row in applications) ...[
            SocialRow(
              title: row.username,
              subtitle: row.message,
              trailing: Row(
                children: [
                  IconButton(
                    onPressed: net.busy
                        ? null
                        : () => net.decideApplication(row.applicationId, true, save),
                    tooltip: 'Accept',
                    icon: const Icon(Icons.check, size: 20),
                  ),
                  IconButton(
                    onPressed: net.busy
                        ? null
                        : () => net.decideApplication(row.applicationId, false, save),
                    tooltip: 'Decline',
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
        const SizedBox(height: 10),
        if (!_confirmingLeave)
          OutlinedButton(
            onPressed: () => setState(() => _confirmingLeave = true),
            child: const Text('Leave guild'),
          )
        else ...[
          Text(leaveGuildPrompt(guild), style: const TextStyle(color: Palette.danger)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _confirmingLeave = false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Palette.danger),
                  onPressed: net.busy
                      ? null
                      : () {
                          setState(() => _confirmingLeave = false);
                          net.leaveGuild(save);
                        },
                  child: const Text('Leave'),
                ),
              ),
            ],
          ),
        ],
        SocialNotice(notice: net.notice),
      ],
    );
  }

  Future<void> _openSettingsSheet(GuildRecord guild) async {
    final settings = await showModalBottomSheet<_GuildSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.parchmentDeep,
      builder: (context) => _GuildSettingsSheet(guild: guild),
    );
    if (settings == null || !mounted) return;
    await net.saveGuildSettings(
      joinPolicy: settings.joinPolicy,
      emblem: settings.emblem,
      rankLabels: settings.rankLabels,
      save: save,
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
    return DropdownButton<GuildRole>(
      value: role,
      underline: const SizedBox.shrink(),
      items: options
          .map(
            (option) => DropdownMenuItem<GuildRole>(
              value: option.role,
              child: Text(option.label, style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null && next != role) onChanged(next);
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
          color: const Color(0x33120C08),
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
  const _CreateGuildSheet({required this.gold});

  final num gold;

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

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = createGuildFormView(widget.gold, _tag.text);
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
            ),
            const SizedBox(height: 8),
            _EmblemEditor(emblem: _emblem, onChanged: (next) => setState(() => _emblem = next)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: form.canAfford
                  ? () => Navigator.of(context)
                        .pop(CreateGuildInput(name: _name.text, tag: _tag.text, emblem: _emblem))
                  : null,
              child: Text(form.submitLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the settings sheet hands back, so the controller saves it in one go.
class _GuildSettings {
  const _GuildSettings({required this.joinPolicy, required this.emblem, required this.rankLabels});

  final GuildJoinPolicy joinPolicy;
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
            DropdownButtonFormField<GuildJoinPolicy>(
              initialValue: _policy,
              decoration: const InputDecoration(labelText: 'Join policy'),
              items: const <DropdownMenuItem<GuildJoinPolicy>>[
                DropdownMenuItem(value: guildJoinOpen, child: Text('Accept applications')),
                DropdownMenuItem(value: guildJoinClosed, child: Text('Closed')),
              ],
              onChanged: (policy) {
                if (policy != null) setState(() => _policy = policy);
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
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _GuildSettings(
                  joinPolicy: _policy,
                  emblem: _emblem,
                  rankLabels: <GuildRankKey, String>{
                    for (final entry in _labels.entries) entry.key: entry.value.text,
                  },
                ),
              ),
              child: const Text('Save settings'),
            ),
          ],
        ),
      ),
    );
  }
}
