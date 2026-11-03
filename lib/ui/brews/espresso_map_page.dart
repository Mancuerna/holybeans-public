import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/domain/espresso_chart.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// An espresso on the extraction map: the style its ratio suggests (which
/// the user can change), the target box, lines of equal ratio and a neutral
/// summary of where the shot falls.
class EspressoMapPage extends StatefulWidget {
  const EspressoMapPage({
    super.key,
    required this.eyPercent,
    required this.tdsPercent,
    required this.ratio,
  });

  final double eyPercent;
  final double tdsPercent;

  /// Beverage ÷ dose.
  final double ratio;

  @override
  State<EspressoMapPage> createState() => _EspressoMapPageState();
}

class _EspressoMapPageState extends State<EspressoMapPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context)!.espressoMap)),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: EspressoMapContent(
              eyPercent: widget.eyPercent,
              tdsPercent: widget.tdsPercent,
              ratio: widget.ratio,
            ),
          ),
        ),
      ),
    ),
  );
}

typedef EspressoMapPoint = ({
  double eyPercent,
  double tdsPercent,
  double ratio,
});

class EspressoMapContent extends StatefulWidget {
  const EspressoMapContent({
    super.key,
    required this.eyPercent,
    required this.tdsPercent,
    required this.ratio,
    this.other,
  });

  final double eyPercent;
  final double tdsPercent;
  final double ratio;
  final EspressoMapPoint? other;

  @override
  State<EspressoMapContent> createState() => _EspressoMapContentState();
}

class _EspressoMapContentState extends State<EspressoMapContent> {
  EspressoStyle? selectedStyle;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final suggested = EspressoStyle.forRatio(widget.ratio);
    final style = selectedStyle ?? suggested;
    String suggestion(double ratio) => s.espressoStyleByRatio(
      espressoStyleName(s, EspressoStyle.forRatio(ratio)),
      _formatEspressoRatio(ratio),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final option in EspressoStyle.values)
              ChoiceChip(
                key: ValueKey('espresso-style-${option.name}'),
                label: Text(espressoStyleName(s, option)),
                selected: option == style,
                onSelected: (_) => setState(() => selectedStyle = option),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            widget.other == null
                ? suggestion(widget.ratio)
                : 'A: ${suggestion(widget.ratio)}\nB: ${suggestion(widget.other!.ratio)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        EspressoMapChart(
          eyPercent: widget.eyPercent,
          tdsPercent: widget.tdsPercent,
          ratio: widget.ratio,
          style: style,
          other: widget.other,
        ),
      ],
    );
  }
}

class EspressoMapChart extends StatelessWidget {
  const EspressoMapChart({
    super.key,
    required this.eyPercent,
    required this.tdsPercent,
    required this.ratio,
    required this.style,
    this.other,
  });
  final double eyPercent;
  final double tdsPercent;
  final double ratio;
  final EspressoStyle style;
  final EspressoMapPoint? other;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final first = (eyPercent: eyPercent, tdsPercent: tdsPercent, ratio: ratio);
    final ey = style.eyAxis;
    final styleAxes = [
      style.tdsAxis,
      if (other != null) ...[
        EspressoStyle.forRatio(ratio).tdsAxis,
        EspressoStyle.forRatio(other!.ratio).tdsAxis,
      ],
    ];
    final tds = (
      min: styleAxes.map((axis) => axis.min).reduce(math.min),
      max: styleAxes.map((axis) => axis.max).reduce(math.max),
    );
    bool onChart(EspressoMapPoint point) =>
        point.eyPercent >= ey.min &&
        point.eyPercent <= ey.max &&
        point.tdsPercent >= tds.min &&
        point.tdsPercent <= tds.max;
    String summary(EspressoMapPoint point) {
      final position = espressoPosition(
        style: style,
        eyPercent: point.eyPercent,
        tdsPercent: point.tdsPercent,
      );
      return [
        if (position == (ey: RangePosition.within, tds: RangePosition.within))
          s.espressoWithin(espressoStyleName(s, style))
        else ...[
          switch (position.ey) {
            RangePosition.low => s.espressoEyLow,
            RangePosition.high => s.espressoEyHigh,
            RangePosition.within => s.espressoEyWithin,
          },
          switch (position.tds) {
            RangePosition.low => s.espressoTdsLow,
            RangePosition.high => s.espressoTdsHigh,
            RangePosition.within => s.espressoTdsWithin,
          },
        ],
        if (!onChart(point)) s.espressoOffChart,
      ].join(', ');
    }

    final precise = NumberFormat('0.##', regionalLocale.toString());
    String values(EspressoMapPoint point) =>
        '${s.ey} ${precise.format(point.eyPercent)} %, '
        '${s.tds} ${precise.format(point.tdsPercent)} %, '
        '${_formatEspressoRatio(point.ratio)}';
    Widget caption(EspressoMapPoint point, String? letter) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          '${letter == null ? '' : '$letter: '}${values(point)}',
          key: ValueKey(
            letter == null
                ? 'espresso-values'
                : 'espresso-values-${letter.toLowerCase()}',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: letter == 'A' ? theme.colorScheme.primary : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          summary(point),
          key: ValueKey(
            letter == null
                ? 'espresso-summary'
                : 'espresso-summary-${letter.toLowerCase()}',
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Semantics(
            label: other == null
                ? '${values(first)}. ${summary(first)}'
                : 'A: ${values(first)}. ${summary(first)}. B: ${values(other!)}. ${summary(other!)}',
            excludeSemantics: true,
            child: CustomPaint(
              key: const ValueKey('espresso-map'),
              painter: _EspressoMapPainter(
                style: style,
                eyPercent: eyPercent,
                tdsPercent: tdsPercent,
                showPoint: onChart(first),
                other: other,
                showOther: other != null && onChart(other!),
                tdsAxis: tds,
                labels: theme.textTheme.labelSmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                colors: theme.colorScheme,
                number: NumberFormat('0.#', regionalLocale.toString()),
                eyTitle: '${s.ey} (%)',
                tdsTitle: '${s.tds} (%)',
              ),
            ),
          ),
        ),
        caption(first, other == null ? null : 'A'),
        if (other != null) caption(other!, 'B'),
      ],
    );
  }
}

String _formatEspressoRatio(double ratio) {
  final number = NumberFormat('0.##', regionalLocale.toString());
  final formatted = number.format(ratio);
  final rounded = number.parse(formatted).toDouble();
  // Keep rounding from presenting a shot below a style boundary as equal to it.
  final below =
      EspressoStyle.forRatio(ratio) != EspressoStyle.forRatio(rounded);
  return '${below ? '<' : ''}1:$formatted';
}

String espressoStyleName(AppLocalizations s, EspressoStyle style) =>
    switch (style) {
      EspressoStyle.ristretto => s.espressoRistretto,
      EspressoStyle.normale => s.espressoNormale,
      EspressoStyle.lungo => s.espressoLungo,
    };

class _EspressoMapPainter extends CustomPainter {
  _EspressoMapPainter({
    required this.style,
    required this.eyPercent,
    required this.tdsPercent,
    required this.showPoint,
    required this.other,
    required this.showOther,
    required this.tdsAxis,
    required this.labels,
    required this.colors,
    required this.number,
    required this.eyTitle,
    required this.tdsTitle,
  });

  final EspressoStyle style;
  final double eyPercent;
  final double tdsPercent;
  final bool showPoint;
  final EspressoMapPoint? other;
  final bool showOther;
  final ({double min, double max}) tdsAxis;
  final TextStyle labels;
  final ColorScheme colors;
  final NumberFormat number;
  final String eyTitle;
  final String tdsTitle;

  static const _insets = EdgeInsets.fromLTRB(36, 22, 30, 40);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _insets.deflateRect(Offset.zero & size);
    final ey = style.eyAxis;
    final tds = tdsAxis;
    double x(double value) =>
        plot.left + (value - ey.min) / (ey.max - ey.min) * plot.width;
    double y(double value) =>
        plot.bottom - (value - tds.min) / (tds.max - tds.min) * plot.height;
    final tdsStep = tds.max - tds.min > 12 ? 2.0 : 1.0;

    final grid = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    for (var value = ey.min; value <= ey.max + 1e-9; value++) {
      canvas.drawLine(
        Offset(x(value), plot.top),
        Offset(x(value), plot.bottom),
        grid,
      );
      if ((value - ey.min) % 2 == 0) {
        _label(
          canvas,
          number.format(value),
          Offset(x(value), plot.bottom + 4),
          alignX: 0.5,
        );
      }
    }
    for (var value = tds.min; value <= tds.max + 1e-9; value += tdsStep) {
      canvas.drawLine(
        Offset(plot.left, y(value)),
        Offset(plot.right, y(value)),
        grid,
      );
      if (((value - tds.min) / tdsStep).round().isEven) {
        _label(
          canvas,
          number.format(value),
          Offset(plot.left - 4, y(value)),
          alignX: 1,
          alignY: 0.5,
        );
      }
    }
    _label(
      canvas,
      eyTitle,
      Offset(plot.center.dx, plot.bottom + 20),
      alignX: 0.5,
    );
    _label(
      canvas,
      tdsTitle,
      Offset(plot.left - 4, plot.top - 4),
      alignX: 0.5,
      alignY: 1,
    );

    // Target box.
    final box = Rect.fromLTRB(
      x(EspressoStyle.minEy),
      y(style.maxTds),
      x(EspressoStyle.maxEy),
      y(style.minTds),
    );
    canvas.drawRect(
      box,
      Paint()..color = colors.primary.withValues(alpha: 0.12),
    );
    canvas.drawRect(
      box,
      Paint()
        ..color = colors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Lines of equal ratio: TDS = EY ÷ ratio, labelled where they leave.
    canvas.save();
    canvas.clipRect(plot);
    final line = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: 0.6)
      ..strokeWidth = 1.2;
    final exits = <(double, Offset)>[];
    for (final ratio in espressoRatioLines) {
      final start = Offset(x(ey.min), y(ey.min / ratio));
      final end = Offset(x(ey.max), y(ey.max / ratio));
      canvas.drawLine(start, end, line);
      // Where it leaves the plot: the top edge or the right one.
      final topEy = tds.max * ratio;
      final exit = topEy < ey.max
          ? Offset(x(topEy), plot.top)
          : Offset(plot.right, y(ey.max / ratio));
      if (exit.dy >= plot.top &&
          exit.dy <= plot.bottom &&
          exit.dx >= plot.left) {
        exits.add((ratio, exit));
      }
    }
    canvas.restore();
    for (final (ratio, exit) in exits) {
      final atTop = exit.dy <= plot.top + 0.5;
      _label(
        canvas,
        '1:${number.format(ratio)}',
        atTop ? exit.translate(0, -2) : exit.translate(3, 0),
        alignX: atTop ? 0.5 : 0,
        alignY: atTop ? 1 : 0.5,
      );
    }

    if (showPoint) {
      final point = Offset(x(eyPercent), y(tdsPercent));
      canvas.drawCircle(point, 8, Paint()..color = colors.surface);
      canvas.drawCircle(
        point,
        6.5,
        Paint()..color = other == null ? colors.tertiary : colors.primary,
      );
      if (other != null) {
        _label(canvas, 'A', point.translate(-10, 0), alignX: 1, alignY: 0.5);
      }
    }
    if (showOther) {
      final point = Offset(x(other!.eyPercent), y(other!.tdsPercent));
      final square = Rect.fromCenter(center: point, width: 17, height: 17);
      canvas.drawRect(
        square,
        Paint()
          ..color = colors.onSurface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _label(canvas, 'B', point.translate(12, 0), alignY: 0.5);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    double alignX = 0,
    double alignY = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labels),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      at - Offset(painter.width * alignX, painter.height * alignY),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(_EspressoMapPainter old) =>
      old.style != style ||
      old.other != other ||
      old.showPoint != showPoint ||
      old.showOther != showOther ||
      old.tdsAxis != tdsAxis ||
      old.number.locale != number.locale ||
      old.eyTitle != eyTitle ||
      old.tdsTitle != tdsTitle ||
      old.eyPercent != eyPercent ||
      old.tdsPercent != tdsPercent ||
      old.colors != colors ||
      old.labels != labels;
}
