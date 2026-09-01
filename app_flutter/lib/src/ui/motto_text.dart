import 'package:flutter/material.dart';

/// Renders a motto with lightweight markup: **bold**, *italic*, __underline__.
///
/// Links and other markdown are not supported — unmatched markers stay as text.
class MottoText extends StatelessWidget {
  const MottoText(
    this.raw, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final String raw;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(style: base, children: parseMottoSpans(raw, base)),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Splits [raw] into styled spans for [MottoText] (and tests).
List<InlineSpan> parseMottoSpans(String raw, TextStyle base) {
  if (raw.isEmpty) return const <InlineSpan>[];
  final spans = <InlineSpan>[];
  // Prefer longer markers first so ** is not eaten as two * runs.
  final pattern = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*');
  var index = 0;
  for (final match in pattern.allMatches(raw)) {
    if (match.start > index) {
      spans.add(TextSpan(text: raw.substring(index, match.start), style: base));
    }
    if (match.group(1) != null) {
      spans.add(
        TextSpan(
          text: match.group(1),
          style: base.merge(const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
    } else if (match.group(2) != null) {
      spans.add(
        TextSpan(
          text: match.group(2),
          style: base.merge(const TextStyle(decoration: TextDecoration.underline)),
        ),
      );
    } else if (match.group(3) != null) {
      spans.add(
        TextSpan(
          text: match.group(3),
          style: base.merge(const TextStyle(fontStyle: FontStyle.italic)),
        ),
      );
    }
    index = match.end;
  }
  if (index < raw.length) {
    spans.add(TextSpan(text: raw.substring(index), style: base));
  }
  return spans;
}
