import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

const sensoryMapDoiUrl = 'https://doi.org/10.1111/1750-3841.16531';

class SensoryMapPage extends StatelessWidget {
  const SensoryMapPage({
    super.key,
    required this.eyPercent,
    required this.tdsPercent,
  });

  final double eyPercent;
  final double tdsPercent;

  static const double minEy = 14;
  static const double maxEy = 26;
  static const double minTds = 0.8;
  static const double maxTds = 1.6;

  bool get hasFinitePositiveValues =>
      eyPercent.isFinite &&
      eyPercent > 0 &&
      tdsPercent.isFinite &&
      tdsPercent > 0;

  bool get isInRange =>
      hasFinitePositiveValues &&
      eyPercent >= minEy &&
      eyPercent <= maxEy &&
      tdsPercent >= minTds &&
      tdsPercent <= maxTds;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(strings.sensoryMap)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SensoryMapChart(
                      eyPercent: eyPercent,
                      tdsPercent: tdsPercent,
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(sensoryMapDoiUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(strings.sensoryMapSourceLink),
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
}

class SensoryMapChart extends StatelessWidget {
  const SensoryMapChart({
    super.key,
    required this.eyPercent,
    required this.tdsPercent,
    this.otherEyPercent,
    this.otherTdsPercent,
  });
  final double eyPercent;
  final double tdsPercent;
  final double? otherEyPercent;
  final double? otherTdsPercent;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final eyText = NumberFormat(
      '0.##',
      regionalLocale.toString(),
    ).format(eyPercent);
    final tdsText = NumberFormat(
      '0.##',
      regionalLocale.toString(),
    ).format(tdsPercent);
    final eyValueLabel = '${strings.ey} $eyText%';
    final tdsValueLabel = '${strings.tds} $tdsText%';
    final markerLabel = '${strings.ey} $eyText%, ${strings.tds} $tdsText%';
    final isInRange =
        eyPercent.isFinite &&
        tdsPercent.isFinite &&
        eyPercent >= SensoryMapPage.minEy &&
        eyPercent <= SensoryMapPage.maxEy &&
        tdsPercent >= SensoryMapPage.minTds &&
        tdsPercent <= SensoryMapPage.maxTds;
    final otherEyText = otherEyPercent == null
        ? null
        : NumberFormat(
            '0.##',
            regionalLocale.toString(),
          ).format(otherEyPercent);
    final otherTdsText = otherTdsPercent == null
        ? null
        : NumberFormat(
            '0.##',
            regionalLocale.toString(),
          ).format(otherTdsPercent);
    final otherMarkerLabel = otherEyText == null || otherTdsText == null
        ? null
        : '${strings.ey} $otherEyText%, ${strings.tds} $otherTdsText%';
    final otherIsInRange =
        otherEyPercent != null &&
        otherTdsPercent != null &&
        otherEyPercent!.isFinite &&
        otherTdsPercent!.isFinite &&
        otherEyPercent! >= SensoryMapPage.minEy &&
        otherEyPercent! <= SensoryMapPage.maxEy &&
        otherTdsPercent! >= SensoryMapPage.minTds &&
        otherTdsPercent! <= SensoryMapPage.maxTds;
    return _SensoryMapPlot(
      eyPercent: eyPercent,
      tdsPercent: tdsPercent,
      markerLabel: markerLabel,
      eyValueLabel: eyValueLabel,
      tdsValueLabel: tdsValueLabel,
      showMarker: isInRange,
      otherEyPercent: otherEyPercent,
      otherTdsPercent: otherTdsPercent,
      otherMarkerLabel: otherMarkerLabel,
      showOtherMarker: otherIsInRange,
      strings: strings,
    );
  }
}

class _SensoryMapPlot extends StatelessWidget {
  const _SensoryMapPlot({
    required this.eyPercent,
    required this.tdsPercent,
    required this.markerLabel,
    required this.eyValueLabel,
    required this.tdsValueLabel,
    required this.showMarker,
    required this.otherEyPercent,
    required this.otherTdsPercent,
    required this.otherMarkerLabel,
    required this.showOtherMarker,
    required this.strings,
  });

  final double eyPercent;
  final double tdsPercent;
  final String markerLabel;
  final String eyValueLabel;
  final String tdsValueLabel;
  final bool showMarker;
  final double? otherEyPercent;
  final double? otherTdsPercent;
  final String? otherMarkerLabel;
  final bool showOtherMarker;
  final AppLocalizations strings;

  static const _insets = EdgeInsets.fromLTRB(48, 30, 14, 54);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxWidth / 1.08);
      final plot = Rect.fromLTRB(
        _insets.left,
        _insets.top,
        size.width - _insets.right,
        size.height - _insets.bottom,
      );
      final markerOffset = Offset(
        plot.left +
            (eyPercent - SensoryMapPage.minEy) /
                (SensoryMapPage.maxEy - SensoryMapPage.minEy) *
                plot.width,
        plot.bottom -
            (tdsPercent - SensoryMapPage.minTds) /
                (SensoryMapPage.maxTds - SensoryMapPage.minTds) *
                plot.height,
      );
      final comparison = otherEyPercent != null && otherTdsPercent != null;
      final otherMarkerOffset = comparison
          ? Offset(
              plot.left +
                  (otherEyPercent! - SensoryMapPage.minEy) /
                      (SensoryMapPage.maxEy - SensoryMapPage.minEy) *
                      plot.width,
              plot.bottom -
                  (otherTdsPercent! - SensoryMapPage.minTds) /
                      (SensoryMapPage.maxTds - SensoryMapPage.minTds) *
                      plot.height,
            )
          : Offset.zero;

      final values = _valuesPlace(plot, markerOffset);
      return SizedBox(
        key: const ValueKey('sensory-map-chart'),
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SensoryMapPainter(
                  locale: strings.localeName,
                  eyAxisLabel: strings.sensoryMapEyAxis,
                  tdsAxisLabel: strings.sensoryMapTdsAxis,
                  colorScheme: Theme.of(context).colorScheme,
                  plotInsets: _insets,
                ),
              ),
            ),
            Positioned.fromRect(
              rect: plot,
              child: const IgnorePointer(
                child: SizedBox.expand(key: ValueKey('sensory-map-plot-area')),
              ),
            ),
            Positioned(
              left: plot.left + 8,
              top: plot.top + 6,
              child: _TrendLabel(
                key: const ValueKey('sensory-map-trend-citrus'),
                label: strings.sensoryMapCitrus,
              ),
            ),
            Positioned(
              right: _insets.right + 6,
              top: plot.top + 6,
              child: _TrendLabel(
                key: const ValueKey('sensory-map-trend-roasty'),
                label: strings.sensoryMapRoasty,
              ),
            ),
            Positioned(
              left: plot.left + 8,
              bottom: size.height - plot.bottom + 8,
              child: _TrendLabel(
                key: const ValueKey('sensory-map-trend-sweet'),
                label: strings.sensoryMapSweet,
              ),
            ),
            Positioned(
              right: _insets.right + 6,
              bottom: size.height - plot.bottom + 8,
              child: _TrendLabel(
                key: const ValueKey('sensory-map-trend-tea'),
                label: strings.sensoryMapTea,
              ),
            ),
            if (showMarker)
              Positioned(
                left: markerOffset.dx - 11,
                top: markerOffset.dy - 11,
                child: Semantics(
                  key: ValueKey(
                    comparison ? 'sensory-map-marker-a' : 'sensory-map-marker',
                  ),
                  label: comparison ? 'A: $markerLabel' : markerLabel,
                  child: ExcludeSemantics(
                    child: _MarkerDot(letter: comparison ? 'A' : null),
                  ),
                ),
              ),
            if (comparison && showOtherMarker)
              Positioned(
                left: otherMarkerOffset.dx - 11,
                top: otherMarkerOffset.dy - 11,
                child: Semantics(
                  key: const ValueKey('sensory-map-marker-b'),
                  label: 'B: $otherMarkerLabel',
                  child: ExcludeSemantics(
                    child: _MarkerDot(
                      letter: 'B',
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            if (showMarker && !comparison)
              Positioned(
                left: values.left,
                top: values.top,
                width: values.width,
                child: ExcludeSemantics(
                  child: _PointValues(eyValueLabel, tdsValueLabel),
                ),
              ),
            if (!showMarker || (comparison && !showOtherMarker))
              Positioned(
                left: plot.left + 8,
                right: size.width - plot.right + 8,
                top: plot.center.dy - 36,
                child: Semantics(
                  key: const ValueKey('sensory-map-out-of-range'),
                  container: true,
                  label:
                      '${[if (!showMarker) comparison ? 'A: $markerLabel' : markerLabel, if (comparison && !showOtherMarker) 'B: $otherMarkerLabel'].join('\n')}, ${strings.sensoryMapOutOfRange}',
                  child: ExcludeSemantics(
                    child: _OutOfRangeNote(
                      [
                        if (!showMarker)
                          comparison ? 'A: $markerLabel' : markerLabel,
                        if (comparison && !showOtherMarker)
                          'B: $otherMarkerLabel',
                      ].join('\n'),
                      strings.sensoryMapOutOfRange,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  /// Where the EY and TDS values go: beside the point, towards the middle,
  /// and inside the plot.
  static ({double left, double top, double width}) _valuesPlace(
    Rect plot,
    Offset marker,
  ) {
    final width = math.min(112.0, plot.width - 8);
    final placeRight = marker.dx <= plot.center.dx;
    final left = (placeRight ? marker.dx + 15 : marker.dx - 15 - width).clamp(
      plot.left + 4,
      plot.right - width - 4,
    );
    final top = marker.dy <= plot.top + 30
        ? plot.top + 40
        : marker.dy >= plot.bottom - 42
        ? marker.dy - 80
        : marker.dy <= plot.center.dy
        ? marker.dy + 12
        : marker.dy - 44;
    return (left: left, top: top, width: width);
  }
}

/// The brew's point on the map.
class _MarkerDot extends StatelessWidget {
  const _MarkerDot({this.letter, this.color});

  final String? letter;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? scheme.primary,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: letter == null
          ? null
          : Center(
              child: Text(
                letter!,
                style: TextStyle(
                  color: scheme.surface,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}

/// The brew's EY and TDS next to its point.
class _PointValues extends StatelessWidget {
  const _PointValues(this.eyLabel, this.tdsLabel);

  final String eyLabel;
  final String tdsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return Container(
      key: const ValueKey('sensory-map-point-values'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.96,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(eyLabel, style: style),
          Text(tdsLabel, style: style),
        ],
      ),
    );
  }
}

/// The brew's values when they fall off the map.
class _OutOfRangeNote extends StatelessWidget {
  const _OutOfRangeNote(this.markerLabel, this.outOfRange);

  final String markerLabel;
  final String outOfRange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.94,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            markerLabel,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            outOfRange,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _TrendLabel extends StatelessWidget {
  const _TrendLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 112),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(fontWeight: FontWeight.w600),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

class _SensoryMapPainter extends CustomPainter {
  const _SensoryMapPainter({
    required this.locale,
    required this.eyAxisLabel,
    required this.tdsAxisLabel,
    required this.colorScheme,
    required this.plotInsets,
  });

  final String locale;
  final String eyAxisLabel;
  final String tdsAxisLabel;
  final ColorScheme colorScheme;
  final EdgeInsets plotInsets;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      plotInsets.left,
      plotInsets.top,
      size.width - plotInsets.right,
      size.height - plotInsets.bottom,
    );
    final roundedPlot = RRect.fromRectAndRadius(
      plot,
      const Radius.circular(AppTheme.radiusMedium),
    );
    canvas.drawRRect(
      roundedPlot,
      Paint()..color = colorScheme.surfaceContainerLow,
    );

    _drawTint(
      canvas,
      plot,
      const Alignment(-0.92, -0.9),
      const Color(0xff72a997),
    );
    _drawTint(
      canvas,
      plot,
      const Alignment(0.92, -0.9),
      const Color(0xffa46b4a),
    );
    _drawTint(
      canvas,
      plot,
      const Alignment(-0.92, 0.9),
      const Color(0xffe1ad45),
    );
    _drawTint(
      canvas,
      plot,
      const Alignment(0.92, 0.9),
      const Color(0xff699db0),
    );

    canvas.save();
    canvas.clipRRect(roundedPlot);
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..strokeWidth = 1;
    for (var index = 0; index < 5; index++) {
      final x = plot.left + plot.width * index / 4;
      final y = plot.top + plot.height * index / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    canvas.restore();

    canvas.drawRRect(
      roundedPlot,
      Paint()
        ..color = const Color(0xff645f55).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final numberFormat = NumberFormat('0.#', regionalLocale.toString());
    final axisStyle = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontSize: 11,
    );
    for (var index = 0; index < 5; index++) {
      final x = plot.left + plot.width * index / 4;
      final eyTick = numberFormat.format(14 + 3 * index);
      _drawText(
        canvas,
        eyTick,
        axisStyle,
        Offset(x, plot.bottom + 5),
        textAlign: TextAlign.center,
      );

      final tdsTick = numberFormat.format(1.6 - 0.2 * index);
      _drawText(
        canvas,
        tdsTick,
        axisStyle,
        Offset(plot.left - 7, plot.top + plot.height * index / 4),
        textAlign: TextAlign.right,
        verticalCenter: true,
      );
    }
    _drawText(
      canvas,
      eyAxisLabel,
      axisStyle.copyWith(fontWeight: FontWeight.w600),
      Offset(plot.center.dx, size.height - 16),
      textAlign: TextAlign.center,
    );

    canvas.save();
    canvas.translate(12, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    _drawText(
      canvas,
      tdsAxisLabel,
      axisStyle.copyWith(fontWeight: FontWeight.w600),
      Offset.zero,
      textAlign: TextAlign.center,
    );
    canvas.restore();
  }

  void _drawTint(Canvas canvas, Rect plot, Alignment center, Color color) {
    final centerPoint = center.withinRect(plot);
    final shader = ui.Gradient.radial(
      centerPoint,
      plot.longestSide * 0.74,
      [color.withValues(alpha: 0.3), color.withValues(alpha: 0)],
      const [0.0, 1.0],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(plot, const Radius.circular(14)),
      Paint()..shader = shader,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset anchor, {
    TextAlign textAlign = TextAlign.left,
    TextBaseline textBaseline = TextBaseline.alphabetic,
    bool verticalCenter = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: textAlign,
      textScaler: TextScaler.noScaling,
    )..layout();
    final offset = Offset(
      textAlign == TextAlign.center
          ? anchor.dx - painter.width / 2
          : textAlign == TextAlign.right
          ? anchor.dx - painter.width
          : anchor.dx,
      verticalCenter
          ? anchor.dy - painter.height / 2
          : textBaseline == TextBaseline.alphabetic
          ? anchor.dy
          : anchor.dy - painter.height,
    );
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SensoryMapPainter oldDelegate) =>
      locale != oldDelegate.locale ||
      eyAxisLabel != oldDelegate.eyAxisLabel ||
      tdsAxisLabel != oldDelegate.tdsAxisLabel ||
      colorScheme != oldDelegate.colorScheme ||
      plotInsets != oldDelegate.plotInsets;
}
