import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'action_stage.dart';
import 'activity_panel.dart';
import 'arena_panel.dart';
import 'bank_panel.dart';
import 'citadel_hub_panel.dart';
import 'guild_hall_panel.dart';
import 'critter_overlay.dart';
import 'format.dart';
import 'game_image.dart';
import 'game_popup.dart';
import 'nearby_panel.dart';
import 'npc_panel.dart';
import 'production_panel.dart';
import 'project_panel.dart';
import 'reward_strip.dart';
import 'shop_panel.dart';

/// Whatever the player has open on top of the location, if anything.
sealed class LocationPanel {
  const LocationPanel();
}

class ShopOpen extends LocationPanel {
  const ShopOpen(this.shopId);

  final String shopId;
}

/// The Town / Castle / Citadel item chest.
class BankOpen extends LocationPanel {
  const BankOpen();
}

/// The Citadel arena: search by name or ranked by combat level.
class ArenaOpen extends LocationPanel {
  const ArenaOpen();
}

/// The per-guild hall: the store house it is built out of, and its debt.
class GuildHallOpen extends LocationPanel {
  const GuildHallOpen();
}

class NpcOpen extends LocationPanel {
  const NpcOpen(this.npc);

  final NpcRow npc;
}

/// One of the Citadel's boards: hourly bounties or the Grand Bazaar.
class CitadelHubOpen extends LocationPanel {
  const CitadelHubOpen(this.tab);

  final CitadelHubTab tab;
}

/// Opening a shop replaces any shop already on the stack so menus do not pile up.
/// An NPC under that shop stays, so Close still returns to the NPC.
List<LocationPanel> pushLocationPanel(List<LocationPanel> open, LocationPanel panel) {
  final next = List<LocationPanel>.of(open);
  if (panel is ShopOpen) {
    next.removeWhere((entry) => entry is ShopOpen);
  }
  next.add(panel);
  return next;
}

/// Where the player is standing: the art, what can be done here, and whatever
/// is currently running or open.
class LocationView extends StatefulWidget {
  const LocationView({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.onOpenMap,
    this.onOpenSubMap,
    this.onEnterGateway,
    this.onOpenGuilds,
  });

  final GameController controller;

  /// Needed by the Citadel boards, which are the one part of a location that
  /// other players can reach into.
  final MultiplayerController multiplayer;
  final VoidCallback onOpenMap;

  /// Opens a district map from a location on that map (Back).
  final ValueChanged<String>? onOpenSubMap;

  /// Travels from a gateway into its landing node.
  final ValueChanged<String>? onEnterGateway;

  final VoidCallback? onOpenGuilds;

  @override
  State<LocationView> createState() => _LocationViewState();
}

class _LocationViewState extends State<LocationView> {
  final List<LocationPanel> _open = [];

  /// The location the open panel belongs to, so travelling closes it.
  String? _openAt;

  /// The activity/NPC/shop band stays short until the player asks for more.
  bool _bandExpanded = false;

  /// The location the expand state belongs to, so travel collapses it.
  String? _bandAt;

  /// Which option group is showing. Reset when the place changes.
  String? _bandTab;

  static const double _collapsedBand = 176;

  /// Town, the cave mouth, and the castle gate still use the old square plates.
  static const Set<String> _squarePlates = {'LOC-0002', 'LOC-0010', 'LOC-0013'};

  /// Keeps arena search state when the panel lifts above the keyboard.
  final GlobalKey _arenaPanelKey = GlobalKey();

  GameController get controller => widget.controller;

  void _openPanel(LocationPanel panel) {
    var save = controller.save;
    if (panel is CitadelHubOpen) {
      save = applyQuestInspectProgress(
        controller.db,
        save,
        panel.tab == CitadelHubTab.bazaar ? 'bazaar' : 'bounties',
      );
    }
    if (!identical(save, controller.save)) controller.commit(save);
    setState(() {
      final next = pushLocationPanel(_open, panel);
      _open
        ..clear()
        ..addAll(next);
      _openAt = controller.save.currentLocationId;
      _bandExpanded = false;
    });
  }

  void _closePanel() => setState(() {
    if (_open.isNotEmpty) _open.removeLast();
  });

  void _inspectProcessing() {
    if (controller.save.currentLocationId != 'LOC-0030') return;
    final save = applyQuestInspectProgress(controller.db, controller.save, 'processing');
    if (!identical(save, controller.save)) controller.commit(save);
  }

  void _openWorkshop(ActivityRow activity, BuildContext buttonContext) {
    _inspectProcessing();
    showProductionPicker(
      buttonContext,
      controller: controller,
      activity: activity,
      origin: popupOrigin(buttonContext),
    );
  }

  void _openStation(SpecialProductionStation station, BuildContext buttonContext) {
    _inspectProcessing();
    showProjectPicker(
      buttonContext,
      controller: controller,
      station: station,
      origin: popupOrigin(buttonContext),
    );
  }

  LocationPanel? get _currentPanel => _open.isEmpty ? null : _open.last;

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
      _open.clear();
      _openAt = null;
    }
    if (_bandAt != locationId) {
      _bandAt = locationId;
      _bandExpanded = false;
      _bandTab = null;
    }

    final running = controller.save.currentActivityId != null;
    final openPanel = _currentPanel;
    // A running action keeps the stage. An open shop/NPC overlays that stage
    // the same way it does when idle, so combat stays visible behind it.
    final stage = running
        ? ActivityPanel(controller: controller)
        : openPanel != null
        ? _buildPanel(openPanel)
        : null;
    final overlayPanel = running && openPanel != null ? _buildPanel(openPanel) : null;

    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final liftArena = openPanel is ArenaOpen && keyboard > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 8, 10, liftArena ? 0 : keyboard),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero /* pixel step 3 */,
          border: Border.all(color: const Color(0x479A7B32)),
        ),
        child: ClipPath(
          clipper: const PixelSteppedClipper(step: 3),
          child: LayoutBuilder(
            builder: (context, card) {
              final bandTop = _bandExpanded ? 8.0 : card.maxHeight - _collapsedBand - 8;
              return Stack(
                fit: StackFit.expand,
                children: [
                  _locationPlate(locationId),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x6B140D08), Color(0x2E140D08), Color(0xB8140D08)],
                        stops: [0, 0.28, 1],
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(13, 12, 13, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _LocationHead(db: controller.db, location: location),
                            ),
                            const SizedBox(width: 11),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.onOpenSubMap != null)
                                  if (backToSubMapLabel(controller.db, location)
                                      case final backLabel?) ...[
                                    OverlayChipButton(
                                      tooltip: backLabel,
                                      onPressed: () =>
                                          widget.onOpenSubMap!(getLocationMapId(location)),
                                      child: const Icon(
                                        Icons.arrow_back,
                                        size: 18,
                                        color: Palette.softGreenShade,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                  ],
                                Builder(
                                  builder: (context) {
                                    return ListenableBuilder(
                                      listenable: widget.multiplayer,
                                      builder: (context, _) {
                                        return OverlayChipButton(
                                          tooltip: 'Nearby adventurers',
                                          onPressed: () => showNearbyPopup(
                                            context,
                                            controller: controller,
                                            multiplayer: widget.multiplayer,
                                            origin: popupOrigin(context),
                                          ),
                                          dark: true,
                                          highlightColor: widget.multiplayer.peers.isEmpty
                                              ? null
                                              : widget.multiplayer.nearbyHasAllies
                                              ? Palette.softGreen
                                              : Palette.gold,
                                          child: const Icon(
                                            Icons.groups,
                                            size: 18,
                                            color: Color(0xF2ECD6A8),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(width: 7),
                                QuestHintPulse(
                                  enabled: questHintsWorldMapButton(controller.db, controller.save),
                                  child: OverlayChipButton(
                                    tooltip: 'Open world map',
                                    onPressed: widget.onOpenMap,
                                    plain: true,
                                    child: GameImage(uiMapAssetPath(), width: 32, height: 32),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isSubMapGateway(location) &&
                          (widget.onEnterGateway != null || widget.onOpenSubMap != null) &&
                          subMapIdForGateway(controller.db, locationId) != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: GameButton(
                              label: enterSubMapLabel(controller.db, location) ?? 'Enter',
                              compact: true,
                              onPressed: () {
                                if (widget.onEnterGateway != null) {
                                  widget.onEnterGateway!(locationId);
                                  return;
                                }
                                widget.onOpenSubMap!(
                                  subMapIdForGateway(controller.db, locationId)!,
                                );
                              },
                            ),
                          ),
                        ),
                      if (controller.showRecoveringStage && stage == null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
                          child: _RecoveringPanel(controller: controller),
                        ),
                      Expanded(
                        child: Stack(
                          children: [
                            if (!liftArena)
                              Positioned(
                                top: 0,
                                left: 13,
                                right: 13,
                                bottom: _collapsedBand + 8,
                                child: _groundedStage(
                                  // Separate bottom layers so starting a gather
                                  // does not resize a shared stack and jump the art.
                                  Stack(
                                    fit: StackFit.expand,
                                    clipBehavior: Clip.none,
                                    children: [
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: OverflowBox(
                                          maxHeight: double.infinity,
                                          alignment: Alignment.bottomCenter,
                                          child: LocationIdlePlayer(controller: controller),
                                        ),
                                      ),
                                      if (running)
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: OverflowBox(
                                            maxHeight: double.infinity,
                                            alignment: Alignment.bottomCenter,
                                            child: IgnorePointer(
                                              child: ActivityPanel(controller: controller),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (stage != null && !running && !liftArena)
                              Positioned(
                                top: 0,
                                left: 13,
                                right: 13,
                                bottom: _collapsedBand + 8,
                                child: openPanel is ArenaOpen
                                    ? stage
                                    : _fittedPanel(stage, fill: _panelFillsSlot(openPanel)),
                              ),
                            if (overlayPanel != null && !liftArena)
                              Positioned(
                                top: 0,
                                left: 13,
                                right: 13,
                                bottom: _collapsedBand + 8,
                                child: openPanel is ArenaOpen
                                    ? overlayPanel
                                    : _fittedPanel(overlayPanel, fill: _panelFillsSlot(openPanel)),
                              ),
                            if (liftArena && (overlayPanel ?? stage) != null)
                              Positioned(
                                left: 10,
                                right: 10,
                                bottom: 8 + keyboard,
                                child: SizedBox(
                                  height: (card.maxHeight - keyboard - 16).clamp(
                                    180,
                                    card.maxHeight * 0.62,
                                  ),
                                  child: overlayPanel ?? stage,
                                ),
                              ),
                            if (controller.recentRewards.isNotEmpty)
                              Positioned(
                                top: 6,
                                left: 13,
                                right: 13,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: RewardStrip(controller: controller),
                                ),
                              ),
                            Positioned(
                              top: 24,
                              left: 0,
                              right: 0,
                              child: Center(child: CritterOverlay(controller: controller)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    top: bandTop,
                    child: _FloatingOptionBand(
                      expanded: _bandExpanded,
                      onToggle: () => setState(() => _bandExpanded = !_bandExpanded),
                      tabs: _optionSections(locationId).map((section) => section.label).toList(),
                      selectedTab: _selectedBandTab(locationId),
                      onSelectTab: (tab) => setState(() => _bandTab = tab),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _selectedBandChildren(locationId),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 9:16 plates pin to the bottom so the walking band stays with the sprites.
  Widget _locationPlate(String locationId) {
    final square = _squarePlates.contains(locationId);
    return GameImage(
      locationAssetPath(locationId),
      fit: BoxFit.cover,
      alignment: square ? Alignment.topCenter : Alignment.bottomCenter,
      filterQuality: square ? FilterQuality.none : FilterQuality.medium,
    );
  }

  /// The grounded actors fill this slot; each layer bottom-aligns itself.
  Widget _groundedStage(Widget panel) {
    return panel;
  }

  /// Shop and bank fill the slot so their inventories scroll; shorter cards
  /// stay at the top and scroll only if they would pass the activity band.
  bool _panelFillsSlot(LocationPanel? panel) {
    return panel is ShopOpen ||
        panel is BankOpen ||
        panel is GuildHallOpen ||
        panel is CitadelHubOpen;
  }

  /// Pins a location overlay to the stage slot above the activity band.
  Widget _fittedPanel(Widget panel, {required bool fill}) {
    return LayoutBuilder(
      builder: (context, stage) {
        final child = fill
            ? SizedBox(width: stage.maxWidth, height: stage.maxHeight, child: panel)
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: stage.maxWidth, maxHeight: stage.maxHeight),
                child: SingleChildScrollView(
                  child: SizedBox(width: stage.maxWidth, child: panel),
                ),
              );
        return Align(alignment: Alignment.topCenter, child: child);
      },
    );
  }

  Widget _buildPanel(LocationPanel panel) {
    switch (panel) {
      case ShopOpen(shopId: final shopId):
        return ShopPanel(controller: controller, shopId: shopId, onClose: _closePanel);
      case BankOpen():
        return BankPanel(controller: controller, onClose: _closePanel);
      case ArenaOpen():
        return ArenaPanel(
          key: _arenaPanelKey,
          controller: controller,
          multiplayer: widget.multiplayer,
          onClose: _closePanel,
        );
      case GuildHallOpen():
        return GuildHallPanel(
          controller: controller,
          multiplayer: widget.multiplayer,
          onClose: _closePanel,
          onOpenBank: () => _openPanel(const BankOpen()),
        );
      case NpcOpen(npc: final npc):
        return NpcPanel(
          controller: controller,
          npc: npc,
          onClose: _closePanel,
          onOpenShop: (shopId) => _openPanel(ShopOpen(shopId)),
        );
      case CitadelHubOpen(tab: final tab):
        return CitadelHubPanel(
          tab: tab,
          controller: controller,
          multiplayer: widget.multiplayer,
          onClose: _closePanel,
          onOpenGuilds: widget.onOpenGuilds,
        );
    }
  }

  List<_BandSection> _optionSections(String locationId) {
    final sections = <_BandSection>[];
    void add(String label, List<Widget> children) {
      if (children.isEmpty) return;
      sections.add(_BandSection(label, children));
    }

    add('Activities', _activities(locationId));
    add('Blessing', _blessing());
    add('Special production', _stations(locationId));
    add('People', _people(locationId));
    add('Shops', _shops(locationId));
    add('Bank', _bank());
    add('Arena', _arena());
    add('Guild hall', _guildHall());
    add(citadelHubTitleFor(locationId), _citadelBoards(locationId));
    add('Search', _searches(locationId));
    return sections;
  }

  String? _selectedBandTab(String locationId) {
    final sections = _optionSections(locationId);
    if (sections.isEmpty) return null;
    if (sections.any((section) => section.label == _bandTab)) return _bandTab;
    return sections.first.label;
  }

  List<Widget> _selectedBandChildren(String locationId) {
    final sections = _optionSections(locationId);
    if (sections.isEmpty) return const [MutedText('Nothing to do here yet.')];
    final selected = _selectedBandTab(locationId);
    return sections.firstWhere((section) => section.label == selected).children;
  }

  List<Widget> _citadelBoards(String locationId) {
    final tabs = citadelHubTabsFor(locationId);
    if (tabs.isEmpty) return const [];
    return [
      for (final tab in tabs)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _InteractionCard(
            title: citadelHubTabLabels[tab]!,
            actionLabel: tab == CitadelHubTab.bazaar ? 'Post' : 'Open',
            tone: GameButtonTone.primary,
            onPressed: () => _openPanel(CitadelHubOpen(tab)),
          ),
        ),
    ];
  }

  List<Widget> _activities(String locationId) {
    final activities = (controller.indexes.activitiesByLocationId[locationId] ?? const [])
        .where(
          (activity) => activityVisibleForSave(controller.db, controller.save, activity.activityId),
        )
        .toList();
    if (activities.isEmpty) return const [];
    return [
      for (final activity in activities)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ActivityCard(
            controller: controller,
            activity: activity,
            onOpenWorkshop: (buttonContext) => _openWorkshop(activity, buttonContext),
          ),
        ),
    ];
  }

  List<Widget> _blessing() {
    if (!locationHasBlessing(controller.location)) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _InteractionCard(
          title: amenityCopy(controller.db, 'blessing').title,
          subtitle: amenityCopy(controller.db, 'blessing').subtitle,
          actionLabel: amenityCopy(controller.db, 'blessing').actionLabel,
          tone: GameButtonTone.primary,
          onPressed: controller.isRecovering ? null : _bless,
        ),
      ),
    ];
  }

  Future<void> _bless() async {
    final result = controller.receiveBlessing();
    if (!result.ok || !mounted) return;
    await showGameAlert(
      context: context,
      title: amenityCopy(controller.db, 'blessing').title,
      message: result.message,
      confirmLabel: 'OK',
      placement: GamePopupPlacement.center,
    );
  }

  List<Widget> _stations(String locationId) {
    final stations = specialProductionStationsVisibleAt(controller.db, controller.save, locationId);
    if (stations.isEmpty) return const [];
    return [
      for (final station in stations)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Builder(
            builder: (context) => _InteractionCard(
              title: station.label,
              actionLabel: 'Projects',
              tone: GameButtonTone.primary,
              onPressed: () => _openStation(station, context),
            ),
          ),
        ),
    ];
  }

  List<Widget> _people(String locationId) {
    final npcs = npcsAtLocationForSave(
      controller.db,
      controller.save,
      locationId,
      controller.session.clock(),
    );
    if (npcs.isEmpty) return const [];
    return [
      for (final npc in npcs)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _InteractionCard(
            title: npc.displayName,
            subtitle: npc.role?.toLowerCase() == 'quest giver' ? null : npc.role,
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

  List<Widget> _bank() {
    if (!locationHasBank(controller.location)) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _InteractionCard(
          title: amenityCopy(controller.db, 'bank').title,
          subtitle: amenityCopy(controller.db, 'bank').subtitle,
          actionLabel: amenityCopy(controller.db, 'bank').actionLabel,
          tone: GameButtonTone.primary,
          onPressed: () => _openPanel(const BankOpen()),
        ),
      ),
    ];
  }

  List<Widget> _arena() {
    if (!locationHasArena(controller.location)) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _InteractionCard(
          title: amenityCopy(controller.db, 'arena').title,
          subtitle: amenityCopy(controller.db, 'arena').subtitle,
          actionLabel: amenityCopy(controller.db, 'arena').actionLabel,
          tone: GameButtonTone.primary,
          onPressed: () => _openPanel(const ArenaOpen()),
        ),
      ),
    ];
  }

  List<Widget> _guildHall() {
    if (!locationHasGuildHall(controller.location)) return const [];
    if (widget.multiplayer.guildId == null &&
        controller.save.currentLocationId != guildHallLocationId) {
      return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _InteractionCard(
          title: amenityCopy(controller.db, 'hall').title,
          subtitle: amenityCopy(controller.db, 'hall').subtitle,
          actionLabel: amenityCopy(controller.db, 'hall').actionLabel,
          tone: GameButtonTone.primary,
          onPressed: () => _openPanel(const GuildHallOpen()),
        ),
      ),
    ];
  }

  List<Widget> _searches(String locationId) {
    final spots = controller.indexes.locationSearchesByLocationId[locationId] ?? const [];
    if (spots.isEmpty) return const [];
    final nowMs = controller.session.clock();
    return [
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
            tone: GameButtonTone.primary,
            onPressed:
                controller.isRecovering || !canClaimLocationSearch(controller.save, spot, nowMs)
                ? null
                : () => _search(spot.searchId),
          ),
        ),
    ];
  }
}

class _BandSection {
  const _BandSection(this.label, this.children);

  final String label;
  final List<Widget> children;
}

/// Inset option list that floats over the location art.
class _FloatingOptionBand extends StatelessWidget {
  const _FloatingOptionBand({
    required this.expanded,
    required this.onToggle,
    required this.tabs,
    required this.selectedTab,
    required this.onSelectTab,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final List<String> tabs;
  final String? selectedTab;
  final ValueChanged<String> onSelectTab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.zero /* pixel step 3 */,
        border: Border.all(color: const Color(0x479A7B32)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tabs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 40, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final tab in tabs)
                            _BandTabButton(
                              label: tab,
                              selected: tab == selectedTab,
                              onPressed: () => onSelectTab(tab),
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    clipBehavior: Clip.hardEdge,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GameIconButton(
              tooltip: expanded ? 'Collapse list' : 'Expand list',
              onPressed: onToggle,
              icon: expanded ? Icons.expand_more : Icons.expand_less,
            ),
          ),
        ],
      ),
    );
  }
}

class _BandTabButton extends StatelessWidget {
  const _BandTabButton({required this.label, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GameButton(
        label: label,
        compact: true,
        tone: selected ? GameButtonTone.primary : GameButtonTone.secondary,
        onPressed: onPressed,
      ),
    );
  }
}

/// The name of the place, what it is, and what it will do to you.
class _LocationHead extends StatelessWidget {
  const _LocationHead({required this.db, required this.location});

  final GameDatabase db;
  final LocationRow location;

  @override
  Widget build(BuildContext context) {
    final danger = location.dangerHostility;
    final showDanger = danger != null && locationShowsDangerWarning(db, location.locationId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          location.displayName,
          style: const TextStyle(
            fontSize: 21.5,
            fontWeight: FontWeight.w400,
            color: Palette.heading,
            height: 1.2,
            shadows: overlayShadow,
          ),
        ),
        const SizedBox(height: 3),
        if (showDanger)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(danger, style: warningStyle),
          ),
      ],
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
    this.tone = GameButtonTone.secondary,
  });

  final String title;
  final String? subtitle;
  final String actionLabel;
  final GameButtonTone tone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DockRow(
      title: title,
      lines: [if (subtitle case final line?) MutedText(line)],
      trailing: GameButton(label: actionLabel, tone: tone, compact: true, onPressed: onPressed),
    );
  }
}

Future<void> _startOrComingSoon(
  BuildContext context,
  GameController controller,
  ActivityRow activity,
) async {
  if (activityIsComingSoon(activity)) {
    if (!context.mounted) return;
    await showGameAlert(
      context: context,
      title: 'Coming soon',
      message: activity.description ?? comingSoonReason,
      confirmLabel: 'OK',
      placement: GamePopupPlacement.center,
    );
    return;
  }
  controller.startActivity(activity.activityId);
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.controller,
    required this.activity,
    required this.onOpenWorkshop,
  });

  final GameController controller;
  final ActivityRow activity;
  final ValueChanged<BuildContext> onOpenWorkshop;

  @override
  Widget build(BuildContext context) {
    final activityId = activity.activityId;
    final running = controller.save.currentActivityId == activityId;
    final check = validateActivityStart(controller.db, controller.save, activityId);
    final production = isStandardProductionActivity(controller.db, activity);

    final recovering = controller.isRecovering;
    final hostileLock = locationIsHostileFor(controller.db, controller.save);
    final favorited = favoriteActivityAt(controller.save) == activityId;
    final questProgress = questActionProgressForActivity(
      controller.db,
      controller.save,
      activityId,
    );
    return DockRow(
      leading: GameIconButton(
        tooltip: favorited ? 'Clear favorite' : 'Favorite this activity',
        onPressed: () => controller.toggleFavorite(activityId),
        icon: favorited ? Icons.star : Icons.star_border,
        size: 28,
        iconColor: favorited ? Palette.gold : null,
      ),
      title: activity.contextualName ?? activityId,
      lines: [
        if (activity.dangerWarningCombatLevel case final level?)
          Text('Combat warning ~ Level $level', style: warningStyle),
        if (hostileLock && running) MutedText(hostileActivityLockReason),
        if (!check.ok && !running) MutedText(check.reason ?? ''),
        for (final line in questProgress) MutedText(line.caption),
      ],
      trailing: running
          ? GameButton(
              label: 'Stop',
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: recovering || hostileLock ? null : controller.stopActivity,
            )
          : GameButton(
              // Enabled even when the check failed: starting is what turns a
              // missing tool into the offer to equip one, and otherwise says why.
              label: production
                  ? 'Recipes'
                  : controller.save.currentActivityId != null
                  ? 'Replace'
                  : 'Start',
              compact: true,
              onPressed: recovering
                  ? null
                  : production
                  ? () => onOpenWorkshop(context)
                  : () => _startOrComingSoon(context, controller, activity),
            ),
    );
  }
}

class _RecoveringPanel extends StatelessWidget {
  const _RecoveringPanel({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, controller.progress]),
      builder: (context, _) {
        return GamePanel(
          child: Row(
            children: [
              const Expanded(
                child: Text('Recovering…', style: TextStyle(fontWeight: FontWeight.w400)),
              ),
              SizedBox(
                width: 96,
                child: Semantics(
                  label: 'Resume progress',
                  child: PillBar(
                    value: controller.deathPauseProgress,
                    gradient: Meters.combatRound,
                    height: 8,
                    borderColor: const Color(0x38FFECC4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
