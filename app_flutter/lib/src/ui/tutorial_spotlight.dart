import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'out_of_sight.dart';

/// Extra pixels around the real widget so the cutout clears the chrome.
const double tutorialSpotlightPad = 2;

/// Hand + arrow cluster used to keep the pointer on-screen.
const double tutorialPointerExtent = 60;
const double tutorialPointerHand = 32;

/// Holds spotlight target keys across AppShell rebuilds.
class TutorialAnchorsScope extends StatefulWidget {
  const TutorialAnchorsScope({super.key, required this.child});

  final Widget child;

  @override
  State<TutorialAnchorsScope> createState() => TutorialAnchorsScopeState();
}

class TutorialAnchorsScopeState extends State<TutorialAnchorsScope> {
  final Map<TutorialSpotlightId, List<_AnchorEntry>> _keys = {
    for (final id in TutorialSpotlightId.values) id: <_AnchorEntry>[],
  };

  void register(TutorialSpotlightId id, GlobalKey key, {bool prefer = false}) {
    final list = _keys[id]!;
    list.removeWhere((entry) => identical(entry.key, key));
    list.add(_AnchorEntry(key, prefer));
  }

  void unregister(TutorialSpotlightId id, GlobalKey key) {
    _keys[id]!.removeWhere((entry) => identical(entry.key, key));
  }

  /// Prefers a [TutorialAnchor.prefer] target that is on-screen and not sitting
  /// behind a covering page.
  RenderBox? boxFor(TutorialSpotlightId id, {Rect? viewport}) {
    RenderBox? regular;
    for (final prefer in [true, false]) {
      for (final entry in _keys[id]!) {
        if (entry.prefer != prefer) continue;
        final box = _visibleBox(entry.key, viewport);
        if (box == null) continue;
        if (prefer) return box;
        regular ??= box;
      }
    }
    return regular;
  }

  RenderBox? _visibleBox(GlobalKey key, Rect? viewport) {
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    if (OutOfSight.of(ctx)) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    if (viewport != null) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (!rect.overlaps(viewport)) return null;
    }
    return box;
  }

  @override
  Widget build(BuildContext context) {
    return TutorialAnchors(state: this, child: widget.child);
  }
}

class _AnchorEntry {
  const _AnchorEntry(this.key, this.prefer);

  final GlobalKey key;
  final bool prefer;
}

/// Registry of on-screen tutorial targets.
class TutorialAnchors extends InheritedWidget {
  const TutorialAnchors({super.key, required this.state, required super.child});

  final TutorialAnchorsScopeState state;

  static TutorialAnchors? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TutorialAnchors>();
  }

  @override
  bool updateShouldNotify(TutorialAnchors oldWidget) => false;
}

/// Marks the one widget the tutorial spotlight should cut a hole around.
class TutorialAnchor extends StatefulWidget {
  const TutorialAnchor({super.key, required this.id, required this.child, this.prefer = false});

  final TutorialSpotlightId id;
  final Widget child;

  /// Bag items win over empty equipment wells when both are on-screen.
  final bool prefer;

  @override
  State<TutorialAnchor> createState() => _TutorialAnchorState();
}

class _TutorialAnchorState extends State<TutorialAnchor> {
  final GlobalKey _key = GlobalKey();
  TutorialAnchorsScopeState? _scope;

  void _attach(TutorialAnchorsScopeState? next) {
    if (identical(next, _scope)) {
      _scope?.register(widget.id, _key, prefer: widget.prefer);
      return;
    }
    _scope?.unregister(widget.id, _key);
    _scope = next;
    _scope?.register(widget.id, _key, prefer: widget.prefer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attach(TutorialAnchors.maybeOf(context)?.state);
  }

  @override
  void didUpdateWidget(covariant TutorialAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _scope?.unregister(oldWidget.id, _key);
    }
    _attach(_scope);
  }

  @override
  void dispose() {
    _scope?.unregister(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

/// Which side of the hole the pointer sits on.
enum TutorialPointerSide { right, left, below, above }

/// Picks a side that keeps the hand off the hole and on-screen.
@visibleForTesting
TutorialPointerSide tutorialPointerSideFor(Rect hole, Size screen) {
  final spaceRight = screen.width - hole.right;
  final spaceLeft = hole.left;
  final spaceBelow = screen.height - hole.bottom;
  final spaceAbove = hole.top;
  const need = tutorialPointerExtent;

  if (spaceRight >= need && spaceRight >= spaceLeft) return TutorialPointerSide.right;
  if (spaceLeft >= need) return TutorialPointerSide.left;
  if (spaceRight >= need) return TutorialPointerSide.right;
  if (spaceBelow >= need && spaceBelow >= spaceAbove) return TutorialPointerSide.below;
  if (spaceAbove >= need) return TutorialPointerSide.above;
  if (spaceBelow >= need) return TutorialPointerSide.below;

  final best = [
    (spaceRight, TutorialPointerSide.right),
    (spaceLeft, TutorialPointerSide.left),
    (spaceBelow, TutorialPointerSide.below),
    (spaceAbove, TutorialPointerSide.above),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return best.first.$2;
}

/// Top-left of the pointer cluster, clamped to [screen].
@visibleForTesting
Offset tutorialPointerOffsetFor(Rect hole, Size screen, TutorialPointerSide side, double lift) {
  final wide = side == TutorialPointerSide.right || side == TutorialPointerSide.left;
  final width = wide ? tutorialPointerExtent : tutorialPointerHand;
  final height = wide ? tutorialPointerHand : tutorialPointerExtent;
  late Offset raw;
  switch (side) {
    case TutorialPointerSide.right:
      raw = Offset(hole.right + 4, hole.center.dy - height / 2 - lift);
    case TutorialPointerSide.left:
      raw = Offset(hole.left - width - 4, hole.center.dy - height / 2 - lift);
    case TutorialPointerSide.below:
      raw = Offset(hole.center.dx - width / 2, hole.bottom + 4 + lift);
    case TutorialPointerSide.above:
      raw = Offset(hole.center.dx - width / 2, hole.top - height - 4 - lift);
  }
  return Offset(
    raw.dx.clamp(2.0, math.max(2.0, screen.width - width - 2)),
    raw.dy.clamp(2.0, math.max(2.0, screen.height - height - 2)),
  );
}

/// Dims the screen except a hole around [target]. Only that hole accepts taps.
///
/// When [target] is missing or off-screen, this paints nothing so Fennel's
/// dialogue can continue instead of trapping the player.
class TutorialSpotlight extends StatefulWidget {
  const TutorialSpotlight({super.key, required this.target, this.child});

  final TutorialSpotlightId? target;
  final Widget? child;

  @override
  State<TutorialSpotlight> createState() => _TutorialSpotlightState();
}

class _TutorialSpotlightState extends State<TutorialSpotlight>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  Rect? _hole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bob.addListener(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bob.removeListener(_onTick);
    _bob.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant TutorialSpotlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _onTick() => _measure();

  void _clearHole() {
    if (_hole != null) setState(() => _hole = null);
  }

  void _measure() {
    if (!mounted) return;
    final id = widget.target;
    if (id == null) {
      _clearHole();
      return;
    }
    final stackBox = context.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize || !stackBox.attached) {
      _clearHole();
      return;
    }
    final origin = stackBox.localToGlobal(Offset.zero);
    final viewport = origin & stackBox.size;
    final box = TutorialAnchors.maybeOf(context)?.state.boxFor(id, viewport: viewport);
    if (box == null || !box.hasSize || !box.attached) {
      _clearHole();
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero) - origin;
    final next = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      box.size.width,
      box.size.height,
    ).inflate(tutorialSpotlightPad);
    if (!next.overlaps(Offset.zero & stackBox.size)) {
      _clearHole();
      return;
    }
    if (_hole != next) setState(() => _hole = next);
  }

  @override
  Widget build(BuildContext context) {
    final hole = _hole;
    if (widget.target == null || hole == null) {
      return widget.child ?? const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(context);
    final side = tutorialPointerSideFor(hole, size);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _SpotlightBarrier(hole: hole)),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const Key('tutorial-spotlight-dim'),
                painter: TutorialDimPainter(hole: hole),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _bob,
            builder: (context, _) {
              final lift = _bob.value * 8;
              final offset = tutorialPointerOffsetFor(hole, size, side, lift);
              return Positioned(
                left: offset.dx,
                top: offset.dy,
                child: IgnorePointer(
                  child: TutorialPointer(key: const Key('tutorial-spotlight-pointer'), side: side),
                ),
              );
            },
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

/// Bobbing hand with an arrow that points at the hole.
@visibleForTesting
class TutorialPointer extends StatelessWidget {
  const TutorialPointer({super.key, required this.side});

  final TutorialPointerSide side;

  @override
  Widget build(BuildContext context) {
    const hand = Icon(
      Icons.touch_app,
      size: 32,
      color: Palette.goldHighlight,
      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
    );
    final arrow = Icon(
      switch (side) {
        TutorialPointerSide.right => Icons.arrow_left,
        TutorialPointerSide.left => Icons.arrow_right,
        TutorialPointerSide.below => Icons.arrow_drop_up,
        TutorialPointerSide.above => Icons.arrow_drop_down,
      },
      size: 28,
      color: Palette.goldHighlight,
      shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
    );
    return switch (side) {
      TutorialPointerSide.right => Row(mainAxisSize: MainAxisSize.min, children: [arrow, hand]),
      TutorialPointerSide.left => Row(mainAxisSize: MainAxisSize.min, children: [hand, arrow]),
      TutorialPointerSide.below => Column(mainAxisSize: MainAxisSize.min, children: [arrow, hand]),
      TutorialPointerSide.above => Column(mainAxisSize: MainAxisSize.min, children: [hand, arrow]),
    };
  }
}

/// Absorbs pointer hits everywhere except [hole], so the target underneath can
/// still be tapped.
class _SpotlightBarrier extends SingleChildRenderObjectWidget {
  const _SpotlightBarrier({required this.hole});

  final Rect hole;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSpotlightBarrier(hole);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderSpotlightBarrier renderObject) {
    renderObject.hole = hole;
  }
}

class _RenderSpotlightBarrier extends RenderProxyBox {
  _RenderSpotlightBarrier(this._hole);

  Rect _hole;
  Rect get hole => _hole;
  set hole(Rect value) {
    if (_hole == value) return;
    _hole = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_hole.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

@visibleForTesting
class TutorialDimPainter extends CustomPainter {
  const TutorialDimPainter({required this.hole});

  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()..addRect(Offset.zero & size);
    final cut = Path()..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(10)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, dim, cut),
      Paint()..color = const Color(0xB3120C08),
    );
  }

  @override
  bool shouldRepaint(covariant TutorialDimPainter oldDelegate) => oldDelegate.hole != hole;
}

/// Next-step line under the HUD. Tap travels to the hinted place.
class TutorialHintBar extends StatelessWidget {
  const TutorialHintBar({super.key, required this.hint, required this.onTap});

  final TutorialHudHint hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.wood,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.flag, size: 16, color: Palette.goldHighlight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint.label,
                  style: const TextStyle(fontSize: GameFont.s, color: Palette.parchmentText),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Palette.goldHighlight),
            ],
          ),
        ),
      ),
    );
  }
}
