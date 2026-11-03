import 'package:flutter/material.dart';
import 'package:holybeans/domain/share_markdown.dart';

TextSpan shareMarkdownSpan(String source) => TextSpan(
  children: [
    for (final run in ShareMarkdown.parse(source))
      TextSpan(
        text: run.text,
        style: TextStyle(
          fontWeight: run.bold ? FontWeight.w700 : null,
          fontStyle: run.italic || run.quote ? FontStyle.italic : null,
          decoration: run.strike ? TextDecoration.lineThrough : null,
          fontFamily: run.code ? 'monospace' : null,
        ),
      ),
  ],
);

Widget shareMarkdownText(
  String source, {
  Key? key,
  TextStyle? style,
  bool selectable = false,
  int? maxLines,
  TextOverflow? overflow,
}) {
  final span = shareMarkdownSpan(source);
  final plain = span.toPlainText();
  // Keep ordinary templates ordinary, including their selection behaviour.
  if (!ShareMarkdown.parse(source)
      .any((r) => r.bold || r.italic || r.strike || r.code || r.quote)) {
    return selectable
        ? SelectableText(plain, key: key, style: style)
        : Text(
            plain,
            key: key,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
          );
  }
  return selectable
      ? SelectableText.rich(span, key: key, style: style)
      : Text.rich(
          span,
          key: key,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
        );
}
