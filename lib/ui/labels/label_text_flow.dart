import 'package:flutter/material.dart';

class LabelFlowLine {
  const LabelFlowLine(this.span, this.bounds);

  final TextSpan span;
  final Rect bounds;

  TextPainter painter() =>
      TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout(maxWidth: bounds.width);
}

class LabelTextFlow {
  LabelTextFlow(
    TextSpan span,
    Rect area,
    Rect exclusion, {
    required bool left,
  }) {
    final plain = span.toPlainText();
    final measure = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout(maxWidth: area.width);
    final lineHeight = measure.computeLineMetrics().fold(
      measure.preferredLineHeight,
      (height, line) => height > line.height ? height : line.height,
    );
    measure.dispose();
    var y = area.top;
    var paragraphStart = 0;
    for (final paragraph in plain.split('\n')) {
      final paragraphEnd = paragraphStart + paragraph.length;
      var start = paragraphStart;
      while (true) {
        var row = Rect.fromLTWH(area.left, y, area.width, lineHeight);
        if (row.overlaps(exclusion)) {
          row = Rect.fromLTRB(
            left ? exclusion.right.clamp(area.left, area.right) : area.left,
            y,
            left ? area.right : exclusion.left.clamp(area.left, area.right),
            y + lineHeight,
          );
        }
        if (row.width <= 0) {
          y = exclusion.bottom;
          continue;
        }
        final remaining = _slice(span, start, paragraphEnd);
        final measure = TextPainter(
          text: remaining,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: row.width);
        final end = start == paragraphEnd
            ? start
            : start +
                  measure.getLineBoundary(const TextPosition(offset: 0)).end;
        final width = measure.computeLineMetrics().firstOrNull?.width ?? 0;
        measure.dispose();
        if (width > row.width + 0.01 ||
            (end == start && start < paragraphEnd)) {
          if (row.overlaps(exclusion) || row.width < area.width) {
            y = exclusion.bottom;
            continue;
          }
          fits = false;
          return;
        }
        lines.add(LabelFlowLine(_slice(span, start, end), row));
        y = row.bottom;
        if (y > area.bottom + 0.01) {
          fits = false;
          return;
        }
        start = end;
        if (start >= paragraphEnd) break;
      }
      paragraphStart = paragraphEnd + 1;
    }
  }

  final List<LabelFlowLine> lines = [];
  bool fits = true;

  void paint(Canvas canvas) {
    for (final line in lines) {
      final painter = line.painter();
      painter.paint(canvas, line.bounds.topLeft);
      painter.dispose();
    }
  }
}

// Slice the rendered spans, not the Markdown source: wrapping must retain
// emphasis, literal substituted values and the emoji font's grapheme clusters.
TextSpan _slice(TextSpan span, int start, int end) {
  var offset = 0;
  TextSpan visit(TextSpan node) {
    final text = node.text ?? '';
    final from = (start - offset).clamp(0, text.length);
    final to = (end - offset).clamp(0, text.length);
    offset += text.length;
    return TextSpan(
      style: node.style,
      text: from < to ? text.substring(from, to) : null,
      children: node.children?.cast<TextSpan>().map(visit).toList(),
    );
  }

  return visit(span);
}
