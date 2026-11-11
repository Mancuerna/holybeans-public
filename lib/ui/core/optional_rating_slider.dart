import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' show NumberFormat;

/// A nullable 0–10 rating that moves in half point steps.
///
/// The slider starts unset with a hollow handle; touching it sets a value, and a clear
/// button returns it to "no rating".
class OptionalRatingSlider extends StatelessWidget {
  const OptionalRatingSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final rated = value != null;
    final slider = Slider(
      value: value ?? 5,
      max: 10,
      divisions: 20,
      // The slider also reads its label aloud, so an unset rating has none.
      label: rated ? number.format(value) : null,
      semanticFormatterCallback: (selected) =>
          rated ? '${number.format(selected)} / 10' : strings.noRating,
      // Slider skips onChanged when the touched value equals the muted
      // placeholder, so an unset rating is committed as soon as touch starts.
      onChangeStart: rated ? null : onChanged,
      onChanged: onChanged,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rated
                        ? '${strings.rating}: ${number.format(value)} / 10'
                        : strings.noRating,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: rated ? FontWeight.w700 : null,
                    ),
                  ),
                  if (!rated)
                    Text(
                      strings.slideToRate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (rated)
              IconButton(
                key: const ValueKey('clear-rating'),
                tooltip: strings.clearRating,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => onChanged(null),
              )
            else
              const SizedBox(height: 48),
          ],
        ),
        if (rated)
          slider
        else
          SliderTheme(
            // A neutral track and hollow handle distinguish an unset rating
            // from the filled, coloured thumb of an actual score.
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: colors.outline,
              inactiveTrackColor: colors.outline,
              thumbShape: _UnsetRatingThumb(colors.surface, colors.onSurface),
              activeTickMarkColor: colors.surface,
              inactiveTickMarkColor: colors.surface,
            ),
            child: slider,
          ),
      ],
    );
  }
}

class _UnsetRatingThumb extends SliderComponentShape {
  const _UnsetRatingThumb(this.fill, this.border);

  final Color fill;
  final Color border;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 20);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas.drawCircle(center, 9, Paint()..color = fill);
    context.canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
