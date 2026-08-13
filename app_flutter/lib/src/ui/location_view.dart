import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'activity_panel.dart';
import 'critter_overlay.dart';
import 'format.dart';
import 'npc_panel.dart';
import 'production_panel.dart';
import 'project_panel.dart';
import 'shop_panel.dart';

/// Whatever the player has open on top of the location, if anything.
sealed class LocationPanel {
  const LocationPanel();
}

class ShopOpen extends LocationPanel {
  const ShopOpen(this.shopId);

  final String shopId;
}

/// The recipe picker for a Standard Production station.
class WorkshopOpen extends LocationPanel {
  const WorkshopOpen(this.activity);

  final ActivityRow activity;
}

class NpcOpen extends LocationPanel {
  const NpcOpen(this.npc);

  final NpcRow npc;
}

/// The project list for a Special Production station.
class StationOpen extends LocationPanel {
  const StationOpen(this.station);

  final SpecialProductionStation station;
}

/// Where the player is standing: the art, what can be done here, and whatever
/// is currently running or open.
class LocationView extends StatefulWidget {
  const LocationView({super.key, required this.controller, required this.onOpenMap});

  final GameController controller;
  final VoidCallback onOpenMap;

  @override
  State<LocationView> createState() => _LocationViewState();
}

class _LocationViewState extends State<LocationView> {
  LocationPanel? _open;

  /// The location the open panel belongs to, so travelling closes it.
  String? _openAt;

  GameController get controller => widget.controller;

  void _openPanel(LocationPanel panel) {
    setState(() {
      _open = panel;
      _openAt = controller.save.currentLocationId;
    });
  }

  void _closePanel() => setState(() => _open = null);

  void _search(String searchId) {
    final result = claimLocationSearch(
      controller.db,
      controller.save,
      searchId,
      controller.session.clock(),
    );
    if (!result.ok) {
      controller.report(result.reason);
      return;
    }
    controller.commit(result.save);
    controller.announce('Found a ${result.itemName}!');
  }

  @override
  Widget build(BuildContext context) {
    final location = controller.location;
    if (location == null) {
      return const Center(child: Text('This place is not on any map.'));
    }
    final locationId = location.locationId;
    if (_openAt != null && _openAt != locationId) {
      _open = null;
      _openAt = null;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          locationAssetPath(locationId),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0xCC1F1610)],
              stops: [0.25, 1],
            ),
          ),
        ),
        ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // The art behind the text is busy, so the header carries its own panel.
            GamePanel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location.displayName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  if (location.description case final blurb?) MutedText(blurb),
                  if (location.dangerHostility case final danger?)
                    Text(danger, style: const TextStyle(color: Palette.danger, fontSize: 12)),
                ],
              ),
            ),
            // Inline rather than floating over the art: on a phone the art is
            // mostly behind this list, and a tap target has to be reachable.
            Align(
              alignment: Alignment.centerRight,
              child: CritterOverlay(controller: controller),
            ),
            const SizedBox(height: 10),
            if (_open case final panel?) ...[_buildPanel(panel), const SizedBox(height: 10)],
            if (controller.isRecovering) ...[
              _RecoveringPanel(controller: controller),
              const SizedBox(height: 10),
            ],
            if (controller.save.currentActivityId != null) ...[
              ActivityPanel(controller: controller),
              const SizedBox(height: 10),
            ],
            if (controller.activityError case final error?) ...[
              _Notice(text: error, tone: Palette.danger),
              const SizedBox(height: 10),
            ],
            if (controller.message case final message?) ...[
              _Notice(text: message, tone: Palette.gold),
              const SizedBox(height: 10),
            ],
            ..._activities(locationId),
            ..._stations(locationId),
            ..._people(locationId),
            ..._shops(locationId),
            ..._searches(locationId),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: widget.onOpenMap, child: const Text('Open the map')),
          ],
        ),
      ],
    );
  }

  Widget _buildPanel(LocationPanel panel) {
    switch (panel) {
      case ShopOpen(shopId: final shopId):
        return ShopPanel(controller: controller, shopId: shopId, onClose: _closePanel);
      case WorkshopOpen(activity: final activity):
        return ProductionPicker(controller: controller, activity: activity, onClose: _closePanel);
      case StationOpen(station: final station):
        return ProjectPicker(controller: controller, station: station, onClose: _closePanel);
      case NpcOpen(npc: final npc):
        return NpcPanel(
          controller: controller,
          npc: npc,
          onClose: _closePanel,
          onOpenShop: (shopId) => _openPanel(ShopOpen(shopId)),
        );
    }
  }

  List<Widget> _activities(String locationId) {
    final activities = controller.indexes.activitiesByLocationId[locationId] ?? const [];
    if (activities.isEmpty) {
      return [const GamePanel(child: Text('Nothing to do here yet.'))];
    }
    return [
      _SectionHeading('Activities'),
      for (final activity in activities)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ActivityCard(
            controller: controller,
            activity: activity,
            onOpenWorkshop: () => _openPanel(WorkshopOpen(activity)),
          ),
        ),
    ];
  }

  List<Widget> _stations(String locationId) {
    final stations = specialProductionStationsAt(controller.db, locationId);
    if (stations.isEmpty) return const [];
    return [
      _SectionHeading('Special production'),
      for (final station in stations)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _InteractionCard(
            title: station.label,
            actionLabel: 'Projects',
            onPressed: () => _openPanel(StationOpen(station)),
          ),
        ),
    ];
  }

  List<Widget> _people(String locationId) {
    final npcs = controller.indexes.npcsByLocationId[locationId] ?? const [];
    if (npcs.isEmpty) return const [];
    return [
      _SectionHeading('People'),
      for (final npc in npcs)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _InteractionCard(
            title: npc.displayName,
            subtitle: npc.role,
            actionLabel: 'Talk',
            onPressed: () => _openPanel(NpcOpen(npc)),
          ),
        ),
    ];
  }

  List<Widget> _shops(String locationId) {
    final shops = controller.indexes.shopsByLocationId[locationId] ?? const [];
    if (shops.isEmpty) return const [];
    return [
      _SectionHeading('Shops'),
      for (final shop in shops)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _InteractionCard(
            title: shop.raw['Display Name'] as String? ?? shop.raw['Shop ID'] as String,
            actionLabel: 'Shop',
            onPressed: () => _openPanel(ShopOpen(shop.raw['Shop ID'] as String)),
          ),
        ),
    ];
  }

  List<Widget> _searches(String locationId) {
    final spots = controller.indexes.locationSearchesByLocationId[locationId] ?? const [];
    if (spots.isEmpty) return const [];
    final nowMs = controller.session.clock();
    return [
      _SectionHeading('Search'),
      for (final spot in spots)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _InteractionCard(
            title: spot.displayName,
            subtitle: canClaimLocationSearch(controller.save, spot, nowMs)
                ? null
                : 'Come back in '
                      '${formatDurationMs(locationSearchCooldownRemainingMs(controller.save, spot, nowMs))}.',
            actionLabel: spot.buttonLabel,
            onPressed: canClaimLocationSearch(controller.save, spot, nowMs)
                ? () => _search(spot.searchId)
                : null,
          ),
        ),
    ];
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}

/// A shop, a person, or a search spot: one line and one button.
class _InteractionCard extends StatelessWidget {
  const _InteractionCard({
    required this.title,
    required this.actionLabel,
    required this.onPressed,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (subtitle case final line?) MutedText(line),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.controller,
    required this.activity,
    required this.onOpenWorkshop,
  });

  final GameController controller;
  final ActivityRow activity;
  final VoidCallback onOpenWorkshop;

  @override
  Widget build(BuildContext context) {
    final activityId = activity.activityId;
    final running = controller.save.currentActivityId == activityId;
    final check = validateActivityStart(controller.db, controller.save, activityId);
    final production = isStandardProductionActivity(controller.db, activity);

    return GamePanel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.contextualName ?? activityId,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (activity.description case final blurb?) MutedText(blurb),
                if (activity.dangerWarningCombatLevel case final level?)
                  Text(
                    'Combat warning ~ Level $level',
                    style: const TextStyle(color: Palette.danger, fontSize: 12),
                  ),
                if (!check.ok) MutedText(check.reason ?? ''),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (running)
            OutlinedButton(onPressed: controller.stopActivity, child: const Text('Stop'))
          else
            FilledButton(
              // Enabled even when the check failed: starting is what turns a
              // missing tool into the offer to equip one, and otherwise says why.
              onPressed: production ? onOpenWorkshop : () => controller.startActivity(activityId),
              // A station asks which recipe first, so it does not start on a tap.
              child: Text(production ? 'Recipes' : 'Start'),
            ),
        ],
      ),
    );
  }
}

class _RecoveringPanel extends StatelessWidget {
  const _RecoveringPanel({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Row(
        children: [
          const Expanded(
            child: Text('Recovering', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(
            'Resuming in ${formatDurationMs(controller.deathPauseRemainingMs)}',
            style: const TextStyle(color: Palette.danger),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, style: TextStyle(color: tone, fontSize: 13)),
    );
  }
}
