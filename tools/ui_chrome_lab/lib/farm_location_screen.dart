import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pixel_ui/pixel_ui.dart';

/// Full Farm location UI test — pixel_ui chrome + real farm art/copy roles.
/// Uses the same [PixeloidSans] family as the game client (no new fonts).
class FarmLocationScreen extends StatefulWidget {
  const FarmLocationScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<FarmLocationScreen> createState() => _FarmLocationScreenState();
}

enum _Tab { adventure, inventory, skills, quests }

enum _Activity { none, pasture, fields }

class _FarmLocationScreenState extends State<FarmLocationScreen> {
  static const cream = Color(0xFFF0E0B8);
  static const muted = Color(0xFFD2C09A);
  static const gold = Color(0xFFE0C878);

  /// Lighter grain so PixeloidSans stays readable on plates.
  static const panelStyle = PixelShapeStyle(
    corners: PixelCorners.lg,
    fillColor: Color(0xFF2E1C10),
    borderColor: cream,
    borderWidth: 3,
    shadow: PixelShadow(offset: Offset(3, 3), color: Color(0xEE000000)),
    texture: PixelTexture(color: Color(0x33FFFFFF), density: 0.14, size: 1, seed: 17),
  );

  static const insetStyle = PixelShapeStyle(
    corners: PixelCorners.md,
    fillColor: Color(0xFF24160E),
    borderColor: Color(0xFFC9B07A),
    borderWidth: 2,
    texture: PixelTexture(color: Color(0x28FFFFFF), density: 0.12, size: 1, seed: 29),
  );

  static const primaryStyle = PixelShapeStyle(
    corners: PixelCorners.lg,
    fillColor: Color(0xFF5F7A45),
    borderColor: cream,
    borderWidth: 3,
    shadow: PixelShadow(offset: Offset(3, 3), color: Color(0xDD000000)),
    texture: PixelTexture(color: Color(0x22000000), density: 0.12, size: 1, seed: 3),
  );

  static const secondaryStyle = PixelShapeStyle(
    corners: PixelCorners.lg,
    fillColor: Color(0xFF5A3A22),
    borderColor: Color(0xFFE0C878),
    borderWidth: 3,
    shadow: PixelShadow(offset: Offset(3, 3), color: Color(0xDD000000)),
    texture: PixelTexture(color: Color(0x22000000), density: 0.12, size: 1, seed: 7),
  );

  static const portraitStyle = PixelShapeStyle(
    corners: PixelCorners.sm,
    fillColor: Color(0xFF6A8FA8),
    borderColor: cream,
    borderWidth: 3,
    shadow: PixelShadow(offset: Offset(2, 2), color: Color(0xCC000000)),
  );

  _Tab _tab = _Tab.adventure;
  _Activity _activity = _Activity.none;
  double _progress = 0;
  Timer? _timer;
  int _hp = 68;
  final int _maxHp = 84;
  int _goldAmount = 312;
  int _xp = 1250;
  final int _xpMax = 2100;
  String? _toast;
  bool _talking = false;

  TextStyle _tx(
    double size, {
    Color color = cream,
    FontWeight weight = FontWeight.w400,
    double? tracking,
  }) {
    return TextStyle(
      fontFamily: 'PixeloidSans',
      fontSize: size,
      color: color,
      // Game theme keeps UI on regular cut; bold file is registered for w700.
      fontWeight: weight,
      letterSpacing: tracking,
      height: 1.2,
      shadows: const [Shadow(offset: Offset(1, 1), color: Color(0xAA000000))],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _flash(String message) {
    setState(() => _toast = message);
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      if (_toast == message) setState(() => _toast = null);
    });
  }

  void _start(_Activity activity) {
    _timer?.cancel();
    setState(() {
      _activity = activity;
      _progress = 0;
      _talking = false;
      _tab = _Tab.adventure;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      setState(() {
        _progress += 0.012;
        if (_progress < 1) return;
        _progress = 0;
        if (activity == _Activity.pasture) {
          _hp = (_hp - 4).clamp(1, _maxHp);
          _xp = (_xp + 18).clamp(0, _xpMax);
          _flash('Cow fought · +18 XP');
        } else {
          _goldAmount += 3;
          _xp = (_xp + 12).clamp(0, _xpMax);
          _flash('Potato harvested · +3g');
        }
      });
    });
  }

  void _stop() {
    _timer?.cancel();
    setState(() {
      _activity = _Activity.none;
      _progress = 0;
    });
  }

  /// PixelBox needs finite width/height — never pass [double.infinity] raw.
  Widget _plate({
    required double width,
    required double height,
    required PixelShapeStyle style,
    Widget? label,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
    AlignmentGeometry alignment = Alignment.center,
    required Widget child,
  }) {
    final logicalW = width.clamp(24, 96).round().clamp(16, 96);
    final logicalH =
        (logicalW * height / width).round().clamp(8, 96);
    return PixelBox(
      logicalWidth: logicalW,
      logicalHeight: logicalH,
      width: width,
      height: height,
      style: style,
      label: label,
      padding: padding,
      alignment: alignment,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF140E0A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0E0A07),
                  border: Border.all(color: const Color(0xFF5C4027), width: 3),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/loc_farm.webp',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Color(0xFF1A2A12)),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x99000000),
                            Color(0x22000000),
                            Color(0xCC000000),
                          ],
                          stops: [0, 0.4, 1],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          _buildHud(),
                          const SizedBox(height: 8),
                          Expanded(child: _buildBody()),
                          const SizedBox(height: 8),
                          _buildNav(),
                        ],
                      ),
                    ),
                    if (_toast != null)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 100,
                        child: LayoutBuilder(
                          builder: (context, c) {
                            return _plate(
                              width: c.maxWidth,
                              height: 44,
                              style: insetStyle,
                              child: Text(
                                _toast!,
                                style: _tx(13),
                                textAlign: TextAlign.center,
                              ),
                            );
                          },
                        ),
                      ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: PixelButton(
                        logicalWidth: 14,
                        logicalHeight: 9,
                        width: 64,
                        height: 34,
                        normalStyle: secondaryStyle,
                        pressChildOffset: const Offset(0, 2),
                        onPressed: widget.onBack,
                        child: Text('BACK', style: _tx(12, weight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHud() {
    final blocks = List<Widget>.generate(_maxHp ~/ 7, (i) {
      final filled = i < (_hp / 7).floor();
      return Text(
        filled ? '█' : '░',
        style: _tx(
          12,
          color: filled ? const Color(0xFFC45A3A) : const Color(0xFF6A5040),
        ),
      );
    });
    return LayoutBuilder(
      builder: (context, c) {
        return _plate(
          width: c.maxWidth,
          height: 88,
          style: panelStyle,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Row(
            children: [
              PixelBox(
                logicalWidth: 12,
                logicalHeight: 12,
                width: 52,
                height: 52,
                style: portraitStyle,
                padding: const EdgeInsets.all(3),
                child: Image.asset(
                  'assets/player_portrait.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ARIC  LV07',
                      style: _tx(14, weight: FontWeight.w700, tracking: 0.4),
                    ),
                    const SizedBox(height: 2),
                    Row(children: blocks),
                    Text('HP $_hp / $_maxHp', style: _tx(12, color: muted)),
                    Text(
                      'XP $_xp/$_xpMax   ${_goldAmount}g',
                      style: _tx(12, color: gold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, c) {
        if (_tab != _Tab.adventure) {
          return _plate(
            width: c.maxWidth,
            height: c.maxHeight,
            style: panelStyle,
            label: Text(
              _tab.name.toUpperCase(),
              style: _tx(12, weight: FontWeight.w700),
            ),
            padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
            child: Text(
              'Stub tab — farm chrome test focuses on Adventure.',
              style: _tx(13, color: muted),
              textAlign: TextAlign.center,
            ),
          );
        }

        if (_talking) {
          return _plate(
            width: c.maxWidth,
            height: c.maxHeight,
            style: panelStyle,
            label: Text('FENNEL', style: _tx(12, weight: FontWeight.w700)),
            padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, inner) {
                      return _plate(
                        width: inner.maxWidth,
                        height: inner.maxHeight,
                        style: insetStyle,
                        padding: const EdgeInsets.all(12),
                        alignment: Alignment.topLeft,
                        child: Text(
                          'Welcome to the lands. I am Fennel.\n\n'
                          'This farm is a good place to start — harvest, cook, and fight are all close by.',
                          style: _tx(13, color: muted),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                PixelButton(
                  logicalWidth: 40,
                  logicalHeight: 10,
                  width: c.maxWidth - 28,
                  height: 42,
                  normalStyle: primaryStyle,
                  pressChildOffset: const Offset(0, 2),
                  onPressed: () => setState(() => _talking = false),
                  child: Text('CLOSE', style: _tx(14, weight: FontWeight.w700)),
                ),
              ],
            ),
          );
        }

        return _plate(
          width: c.maxWidth,
          height: c.maxHeight,
          style: panelStyle,
          label: Text('THE FARM', style: _tx(12, weight: FontWeight.w700)),
          padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pasture-focused starting area with Cow and Bull encounters.',
                style: _tx(12, color: muted),
              ),
              const SizedBox(height: 10),
              if (_activity != _Activity.none) ...[
                _plate(
                  width: c.maxWidth - 24,
                  height: 56,
                  style: insetStyle,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _activity == _Activity.pasture
                            ? 'Tending pasture…'
                            : 'Working fields…',
                        style: _tx(13, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _SegmentBar(progress: _progress),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _activityCard(
                      width: c.maxWidth - 24,
                      title: 'Tend the pasture',
                      detail: 'Fight cows · rare bull',
                      icon: 'assets/skl_combat.webp',
                      active: _activity == _Activity.pasture,
                      onStart: () => _start(_Activity.pasture),
                    ),
                    const SizedBox(height: 8),
                    _activityCard(
                      width: c.maxWidth - 24,
                      title: 'Work the fields',
                      detail: 'Harvest potatoes · rare golden spud',
                      icon: 'assets/skl_harvesting.webp',
                      active: _activity == _Activity.fields,
                      onStart: () => _start(_Activity.fields),
                    ),
                    const SizedBox(height: 8),
                    _npcCard(width: c.maxWidth - 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _activityCard({
    required double width,
    required String title,
    required String detail,
    required String icon,
    required bool active,
    required VoidCallback onStart,
  }) {
    return _plate(
      width: width,
      height: 78,
      style: insetStyle,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Image.asset(
              icon,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: _tx(13, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(detail, style: _tx(11, color: muted)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          PixelButton(
            logicalWidth: 14,
            logicalHeight: 9,
            width: 72,
            height: 36,
            normalStyle: active ? secondaryStyle : primaryStyle,
            pressChildOffset: const Offset(0, 2),
            onPressed: active ? _stop : onStart,
            child: Text(
              active ? 'STOP' : 'START',
              style: _tx(12, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _npcCard({required double width}) {
    return _plate(
      width: width,
      height: 68,
      style: insetStyle,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Fennel', style: _tx(13, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('Guide · Farm welcome', style: _tx(11, color: muted)),
              ],
            ),
          ),
          PixelButton(
            logicalWidth: 14,
            logicalHeight: 9,
            width: 72,
            height: 36,
            normalStyle: secondaryStyle,
            pressChildOffset: const Offset(0, 2),
            onPressed: () {
              _stop();
              setState(() => _talking = true);
            },
            child: Text('TALK', style: _tx(12, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildNav() {
    const items = <(_Tab, String)>[
      (_Tab.adventure, 'ADV'),
      (_Tab.inventory, 'BAG'),
      (_Tab.skills, 'SKL'),
      (_Tab.quests, 'QST'),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final slot = (c.maxWidth / items.length) - 6;
        return Row(
          children: [
            for (final (tab, label) in items)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: PixelButton(
                    logicalWidth: 14,
                    logicalHeight: 11,
                    width: slot.clamp(48, 120),
                    height: 48,
                    normalStyle: _tab == tab ? primaryStyle : secondaryStyle,
                    pressChildOffset: const Offset(0, 2),
                    onPressed: () => setState(() {
                      _tab = tab;
                      _talking = false;
                    }),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: _tx(13, weight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const total = 12;
    final filled = (progress.clamp(0, 1) * total).floor();
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: Container(
              height: 10,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 2),
              decoration: BoxDecoration(
                color: i < filled ? const Color(0xFF8FCE6B) : const Color(0xFF3A2A1A),
                border: Border.all(color: const Color(0xFFC9B07A)),
              ),
            ),
          ),
      ],
    );
  }
}
