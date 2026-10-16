import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';
import 'game_popup.dart';

/// UI hex for Sys palette ids. The engine stores the id, not the colour.
Color guildBannerPaletteColor(String id) {
  return switch (id) {
    'midnight' => const Color(0xFF1B2433),
    'wine' => const Color(0xFF6B2C3A),
    'rust' => const Color(0xFF8B4A2B),
    'ivory' => const Color(0xFFE8D9B8),
    'ash' => const Color(0xFF8A8178),
    'indigo' => const Color(0xFF3D3A6B),
    'ocean' => const Color(0xFF2A5A6B),
    'ember' => const Color(0xFFA14A2A),
    'plum' => const Color(0xFF5A3A5A),
    _ => const Color(0xFF4A5560),
  };
}

/// Hall banner: palette fill, accent stripe, optional unlocked emblem and border.
class GuildHallBanner extends StatelessWidget {
  const GuildHallBanner({super.key, required this.banner, this.size = 36, this.onPressed});

  final GuildBanner banner;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final fill = guildBannerPaletteColor(banner.background);
    final accent = guildBannerPaletteColor(banner.accent);
    final flag = SizedBox(
      width: size * 1.6,
      height: size,
      child: CustomPaint(
        painter: _BannerPainter(
          banner: banner,
          fill: fill,
          accent: accent,
          border: UiChrome.of(context).embossFace,
        ),
      ),
    );
    if (onPressed == null) return flag;
    return InkWell(key: const Key('guild-hall-banner-edit'), onTap: onPressed, child: flag);
  }
}

class _BannerPainter extends CustomPainter {
  _BannerPainter({
    required this.banner,
    required this.fill,
    required this.accent,
    required this.border,
  });

  final GuildBanner banner;
  final Color fill;
  final Color accent;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = fill);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * 0.18, size.height), Paint()..color = accent);
    final borderId = banner.border;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = borderId == 'border_strength' ? border : accent
      ..strokeWidth = switch (borderId) {
        'border_vault' => 2,
        'border_hands' => 2,
        'border_more_hands' => 3,
        'border_strength' => 2,
        _ => 1,
      };
    if (borderId == null) {
      canvas.drawRect(
        rect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Palette.edge
          ..strokeWidth = 1,
      );
    } else {
      canvas.drawRect(rect.deflate(borderPaint.strokeWidth / 2), borderPaint);
    }
    final emblem = banner.emblem;
    if (emblem != null) {
      final mark = Rect.fromCenter(
        center: rect.center.translate(size.width * 0.06, 0),
        width: size.shortestSide * 0.46,
        height: size.shortestSide * 0.46,
      );
      _paintEmblem(canvas, mark, emblem, accent);
    }
  }

  void _paintEmblem(Canvas canvas, Rect box, String emblem, Color color) {
    final paint = Paint()..color = color;
    switch (emblem) {
      case 'emblem_counting':
        canvas.drawCircle(box.center, box.shortestSide / 2, paint);
      case 'emblem_boxing':
        canvas.drawPath(
          Path()
            ..moveTo(box.center.dx, box.top)
            ..lineTo(box.right, box.center.dy)
            ..lineTo(box.center.dx, box.bottom)
            ..lineTo(box.left, box.center.dy)
            ..close(),
          paint,
        );
      case 'emblem_garden':
        canvas.drawOval(box.deflate(box.width * 0.1), paint);
      case 'emblem_arcana':
        final c = box.center;
        final r = box.shortestSide / 2;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - r)
            ..lineTo(c.dx + r * 0.28, c.dy - r * 0.28)
            ..lineTo(c.dx + r, c.dy)
            ..lineTo(c.dx + r * 0.28, c.dy + r * 0.28)
            ..lineTo(c.dx, c.dy + r)
            ..lineTo(c.dx - r * 0.28, c.dy + r * 0.28)
            ..lineTo(c.dx - r, c.dy)
            ..lineTo(c.dx - r * 0.28, c.dy - r * 0.28)
            ..close(),
          paint,
        );
      case 'emblem_cage':
        canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(2)), paint);
      case 'emblem_pockets':
      case 'emblem_deeper_pockets':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            box.deflate(emblem == 'emblem_pockets' ? 2 : 0),
            Radius.circular(box.width * 0.2),
          ),
          paint,
        );
      default:
        canvas.drawRect(box, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BannerPainter old) =>
      old.banner.background != banner.background ||
      old.banner.accent != banner.accent ||
      old.banner.emblem != banner.emblem ||
      old.banner.border != banner.border ||
      old.fill != fill ||
      old.accent != accent ||
      old.border != border;
}

/// Picker for the four engine banner fields. Locked cosmetics stay off the pad.
Future<GuildBanner?> askGuildBanner(
  BuildContext context, {
  required GuildBanner banner,
  required Iterable<String> unlockedAchievementIds,
}) {
  return showGamePopup<GuildBanner>(
    context: context,
    maxHeight: 560,
    builder: (context) =>
        _BannerSheet(initial: banner, unlockedAchievementIds: unlockedAchievementIds),
  );
}

class _BannerSheet extends StatefulWidget {
  const _BannerSheet({required this.initial, required this.unlockedAchievementIds});

  final GuildBanner initial;
  final Iterable<String> unlockedAchievementIds;

  @override
  State<_BannerSheet> createState() => _BannerSheetState();
}

class _BannerSheetState extends State<_BannerSheet> {
  late GuildBanner _banner = widget.initial;

  void _set(GuildBanner next) => setState(() => _banner = next);

  @override
  Widget build(BuildContext context) {
    final rewards = unlockedRewardIds(widget.unlockedAchievementIds);
    return GamePopupCard(
      child: GamePanel(
        framed: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: GuildHallBanner(banner: _banner, size: 48)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in guildBannerPalette)
                  _Swatch(
                    key: Key('guild-banner-bg-$id'),
                    color: guildBannerPaletteColor(id),
                    selected: _banner.background == id,
                    onTap: () => _set(
                      GuildBanner(
                        background: id,
                        accent: _banner.accent,
                        emblem: _banner.emblem,
                        border: _banner.border,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in guildBannerPalette)
                  _Swatch(
                    key: Key('guild-banner-accent-$id'),
                    color: guildBannerPaletteColor(id),
                    selected: _banner.accent == id,
                    onTap: () => _set(
                      GuildBanner(
                        background: _banner.background,
                        accent: id,
                        emblem: _banner.emblem,
                        border: _banner.border,
                      ),
                    ),
                  ),
              ],
            ),
            if (rewards.emblems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _RewardChip(
                    key: const Key('guild-banner-emblem-none'),
                    selected: _banner.emblem == null,
                    onTap: () => _set(
                      GuildBanner(
                        background: _banner.background,
                        accent: _banner.accent,
                        border: _banner.border,
                      ),
                    ),
                    child: const SizedBox.shrink(),
                  ),
                  for (final id in rewards.emblems)
                    _RewardChip(
                      key: Key('guild-banner-emblem-$id'),
                      selected: _banner.emblem == id,
                      onTap: () => _set(
                        GuildBanner(
                          background: _banner.background,
                          accent: _banner.accent,
                          emblem: id,
                          border: _banner.border,
                        ),
                      ),
                      child: CustomPaint(
                        size: const Size(18, 18),
                        painter: _BannerPainter(
                          banner: GuildBanner(
                            background: _banner.background,
                            accent: _banner.accent,
                            emblem: id,
                          ),
                          fill: Colors.transparent,
                          accent: guildBannerPaletteColor(_banner.accent),
                          border: UiChrome.of(context).embossFace,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (rewards.borders.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _RewardChip(
                    key: const Key('guild-banner-border-none'),
                    selected: _banner.border == null,
                    onTap: () => _set(
                      GuildBanner(
                        background: _banner.background,
                        accent: _banner.accent,
                        emblem: _banner.emblem,
                      ),
                    ),
                    child: const SizedBox.shrink(),
                  ),
                  for (final id in rewards.borders)
                    _RewardChip(
                      key: Key('guild-banner-border-$id'),
                      selected: _banner.border == id,
                      onTap: () => _set(
                        GuildBanner(
                          background: _banner.background,
                          accent: _banner.accent,
                          emblem: _banner.emblem,
                          border: id,
                        ),
                      ),
                      child: CustomPaint(
                        size: const Size(22, 14),
                        painter: _BannerPainter(
                          banner: GuildBanner(
                            background: _banner.background,
                            accent: _banner.accent,
                            border: id,
                          ),
                          fill: guildBannerPaletteColor(_banner.background),
                          accent: guildBannerPaletteColor(_banner.accent),
                          border: UiChrome.of(context).embossFace,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                GameButton(
                  label: 'Cancel',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameButton(
                    label: 'Save',
                    onPressed: () => Navigator.of(context).pop(_banner),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({super.key, required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
            color: selected ? Palette.borderSelected : UiChrome.of(context).edge,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({super.key, required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.panel,
          border: Border.all(
            color: selected ? Palette.borderSelected : UiChrome.of(context).edge,
            width: selected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}
