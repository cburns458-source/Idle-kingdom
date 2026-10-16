import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'out_of_sight.dart';

/// Holds spotlight target keys across AppShell rebuilds.
class TutorialAnchorsScope extends StatefulWidget {
  const TutorialAnchorsScope({super.key, required this.child});

  final Widget child;

  @override
  State<TutorialAnchorsScope> createState() => TutorialAnchorsScopeState();
}

class TutorialAnchorsScopeState extends State<TutorialAnchorsScope> {
  final Map<TutorialSpotlightId, Set<GlobalKey>> _keys = {
    for (final id in TutorialSpotlightId.values) id: <GlobalKey>{},
  };

  void register(TutorialSpotlightId id, GlobalKey key) {
    _keys[id]!.add(key);
  }

  void unregister(TutorialSpotlightId id, GlobalKey key) {
    _keys[id]!.remove(key);
  }

  /// Prefers a target that is not sitting behind a covering page.
  RenderBox? boxFor(TutorialSpotlightId id) {
    for (final key in _keys[id]!) {
      final ctx = key.currentContext;
      if (ctx == null || !ctx.mounted) continue;
      if (OutOfSight.of(ctx)) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      return box;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TutorialAnchors(state: this, child: widget.child);
  }
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
  const TutorialAnchor({super.key, required this.id, required this.child});

  final TutorialSpotlightId id;
  final Widget child;

  @override
  State<TutorialAnchor> createState() => _TutorialAnchorState();
}

class _TutorialAnchorState extends State<TutorialAnchor> {
  final GlobalKey _key = GlobalKey();
  TutorialAnchorsScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TutorialAnchors.maybeOf(context)?.state;
    if (!identical(next, _scope)) {
      _scope?.unregister(widget.id, _key);
      _scope = next;
      _scope?.register(widget.id, _key);
    }
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

/// Dims the screen except a hole around [target]. Only that hole accepts taps.
///
/// When [target] is missing, this paints nothing so Fennel's dialogue can
/// continue instead of trapping the player.
class TutorialSpotlight extends StatefulWidget {
  const TutorialSpotlight({super.key, required this.target, this.child});

  final TutorialSpotlightId? target;
  final Widget? child;

  @override
  State<TutorialSpotlight> createState() => _TutorialSpotlightState();
}

class _TutorialSpotlightState extends State<TutorialSpotlight> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  Rect? _hole;

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
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

  void _measure() {
    if (!mounted) return;
    final id = widget.target;
    if (id == null) {
      if (_hole != null) setState(() => _hole = null);
      return;
    }
    final box = TutorialAnchors.maybeOf(context)?.state.boxFor(id);
    if (box == null || !box.hasSize || !box.attached) {
      if (_hole != null) setState(() => _hole = null);
      return;
    }
    final stackBox = context.findRenderObject() as RenderBox?;
    final origin = stackBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final topLeft = box.localToGlobal(Offset.zero) - origin;
    final next = Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height).inflate(8);
    if (_hole != next) setState(() => _hole = next);
  }

  @override
  Widget build(BuildContext context) {
    final hole = _hole;
    if (widget.target == null || hole == null) {
      return widget.child ?? const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(context);
    final pointerOnRight = (size.width - hole.right) >= hole.left;

    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(child: ColoredBox(color: Colors.transparent)),
        Positioned.fill(
          child: _SpotlightBarrier(
            hole: hole,
            child: const CustomPaint(painter: _DimHolePainterPlaceholder()),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _DimHolePainter(hole: hole)),
          ),
        ),
        AnimatedBuilder(
          animation: _bob,
          builder: (context, _) {
            final lift = 6 + _bob.value * 10;
            final dx = pointerOnRight ? hole.right + 4 : hole.left - 36;
            return Positioned(
              left: dx,
              top: hole.center.dy - 16 - lift,
              child: IgnorePointer(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(pointerOnRight ? 0 : math.pi),
                  child: const Icon(
                    Icons.touch_app,
                    size: 32,
                    color: Palette.gold,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _DimHolePainterPlaceholder extends CustomPainter {
  const _DimHolePainterPlaceholder();

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Absorbs pointer hits everywhere except [hole], so the target underneath can
/// still be tapped.
class _SpotlightBarrier extends SingleChildRenderObjectWidget {
  const _SpotlightBarrier({required this.hole, required super.child});

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
    if (_hole.inflate(4).contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

class _DimHolePainter extends CustomPainter {
  const _DimHolePainter({required this.hole});

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
  bool shouldRepaint(covariant _DimHolePainter oldDelegate) => oldDelegate.hole != hole;
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
              const Icon(Icons.flag, size: 16, color: Palette.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint.label,
                  style: const TextStyle(fontSize: GameFont.s, color: Palette.parchmentText),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Palette.gold),
            ],
          ),
        ),
      ),
    );
  }
}
