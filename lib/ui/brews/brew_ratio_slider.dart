import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

class BrewRatioSlider extends StatefulWidget {
  const BrewRatioSlider({
    super.key,
    required this.espresso,
    required this.doseGrams,
    required this.ratio,
    required this.onChanged,
  });

  final bool espresso;
  final double? doseGrams;
  final double? ratio;
  final ValueChanged<double> onChanged;

  @override
  State<BrewRatioSlider> createState() => _BrewRatioSliderState();
}

class _BrewRatioSliderState extends State<BrewRatioSlider> {
  late double _previousSelected;

  double get _selected => widget.ratio ?? (widget.espresso ? 2 : 16);

  @override
  void initState() {
    super.initState();
    _previousSelected = _selected;
  }

  @override
  void didUpdateWidget(BrewRatioSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _previousSelected = oldWidget.espresso == widget.espresso
        ? oldWidget.ratio ?? (oldWidget.espresso ? 2 : 16)
        : _selected;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final espresso = widget.espresso;
    final selected = _selected;
    final min = espresso ? 1.0 : 12.0;
    final max = espresso ? 10.0 : 20.0;
    final step = espresso ? 0.1 : 0.5;
    final enabled =
        widget.doseGrams != null &&
        widget.doseGrams!.isFinite &&
        widget.doseGrams! > 0;
    final interactive = enabled && selected >= min && selected <= max;
    final sliderValue = selected.clamp(min, max);
    final target = widget.ratio == null
        ? null
        : brewRatioTargetGrams(doseGrams: widget.doseGrams, ratio: selected);
    final label = widget.ratio == null
        ? '—'
        : '1:${formatBrewRatioMultiplier(selected, regionalLocale.toString())}';
    void pick(double value) => widget.onChanged((value / step).round() * step);
    return Column(
      key: const ValueKey('brew-ratio-control'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${espresso ? s.filterTargetRatio : s.ratio}: $label',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Row(
          children: [
            IconButton(
              key: const ValueKey('brew-ratio-decrease'),
              tooltip: s.brewRatioDecrease,
              onPressed: enabled && selected > min
                  ? () => pick(selected - step)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('brew-ratio-slider'),
                min: min,
                max: max,
                divisions: ((max - min) / step).round(),
                value: sliderValue,
                label: label,
                semanticFormatterCallback: (_) =>
                    '${espresso ? s.filterTargetRatio : s.ratio}: $label',
                onChanged: interactive ? pick : null,
              ),
            ),
            IconButton(
              key: const ValueKey('brew-ratio-increase'),
              tooltip: s.brewRatioIncrease,
              onPressed: enabled && (selected != max || _previousSelected > max)
                  ? () => pick(selected + step)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        // Filter water is the field right above; espresso's target is not
        // written anywhere else.
        if (espresso)
          Text(
            '${s.brewTargetBeverage}: '
            '${target == null ? '—' : '${formatDecimal(target, pattern: '0.#', locale: regionalLocale.toString())} g'}',
            key: const ValueKey('brew-ratio-target'),
          ),
      ],
    );
  }
}
