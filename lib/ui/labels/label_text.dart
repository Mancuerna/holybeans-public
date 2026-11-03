import 'package:flutter/material.dart';
import 'package:holybeans/ui/core/share_markdown_text.dart';

// Use an explicit monochrome family for emoji grapheme clusters, including
// variation selectors, flags, skin tones and ZWJ sequences. Android's color
// emoji fallback can otherwise override the requested black text color.
final _emoji = RegExp(
  '[\u{1f000}-\u{1faff}\u2300-\u23ff\u2600-\u27ff\u2b00-\u2bff'
  '\ufe0f\u20e3]',
  unicode: true,
);

TextSpan labelMarkdownSpan(String source) => TextSpan(
  children: [
    for (final run in shareMarkdownSpan(source).children!.cast<TextSpan>())
      TextSpan(
        style: run.style,
        children: [
          for (final (text, emoji) in _segments(run.text!))
            TextSpan(
              text: text,
              style: emoji
                  ? const TextStyle(
                      fontFamily: 'NotoEmoji',
                      fontFamilyFallback: ['Plex'],
                    )
                  : null,
            ),
        ],
      ),
  ],
);

Iterable<(String, bool)> _segments(String source) sync* {
  var buffer = StringBuffer();
  bool? previous;
  for (final cluster in source.characters) {
    final emoji = _emoji.hasMatch(cluster);
    if (previous != null && previous != emoji) {
      yield (buffer.toString(), previous);
      buffer = StringBuffer();
    }
    buffer.write(cluster);
    previous = emoji;
  }
  if (previous != null) yield (buffer.toString(), previous);
}
