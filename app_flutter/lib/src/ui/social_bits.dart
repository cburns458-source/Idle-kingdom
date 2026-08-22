import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../theme.dart';
import 'game_image.dart';

/// A guild banner: the chosen color with the chosen mark on it.
///
/// The mark is the same path string the web client draws, wrapped in a document
/// because that is what an SVG renderer wants.
class GuildEmblemBadge extends StatelessWidget {
  const GuildEmblemBadge({super.key, required this.emblem, this.size = 34});

  final GuildEmblem emblem;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _color(emblem.color),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Palette.edge),
      ),
      padding: EdgeInsets.all(size * 0.18),
      child: GuildEmblemMark(symbol: emblem.symbol),
    );
  }
}

/// Just the mark, for the picker where the color is chosen separately.
class GuildEmblemMark extends StatelessWidget {
  const GuildEmblemMark({super.key, required this.symbol, this.color = Palette.parchmentText});

  final String symbol;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<path fill="$hex" d="${guildEmblemSymbolPath(symbol)}"/></svg>',
      fit: BoxFit.contain,
    );
  }
}

Color _color(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return Palette.parchment;
  return Color(0xFF000000 | value);
}

/// A player's face, at the size social lists use.
class SocialPortrait extends StatelessWidget {
  const SocialPortrait({
    super.key,
    required this.appearance,
    this.size = 34,
    this.borderColor,
  });

  final PlayerAppearance appearance;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor ?? Palette.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: GameImage(
        playerAssetPath(appearance),
        alignment: Alignment.topCenter,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
      ),
    );
  }
}

/// One row of a social list: a mark, two lines of copy, and a trailing widget.
class SocialRow extends StatelessWidget {
  const SocialRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      highlight: highlight,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          if (leading case final leading?) ...[leading, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w400),
                ),
                if (subtitle.isNotEmpty) MutedText(subtitle),
              ],
            ),
          ),
          if (trailing case final trailing?) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }
}

/// The line a signed-out panel shows in place of everything else.
class SignedOutNotice extends StatelessWidget {
  const SignedOutNotice({
    super.key,
    required this.title,
    required this.prompt,
    this.showTitle = true,
  });

  final String title;
  final String prompt;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle) ...[
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
            const SizedBox(height: 8),
          ],
          Text(prompt),
        ],
      ),
    );
  }
}
