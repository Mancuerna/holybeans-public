import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';

class PressureReadouts extends StatelessWidget {
  const PressureReadouts({
    super.key,
    required this.target,
    required this.actual,
    this.unit = 'bar',
    this.actualLabel,
    this.keyPrefix = 'pressure',
  });
  final String target;
  final String actual;
  final String unit;
  final String? actualLabel;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 280 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.5;
        final reference = _Reading(
          label: s.pressureGuideTarget,
          value: target,
          color: colors.primary,
          valueKey: '$keyPrefix-target',
          unit: unit,
          icon: Icons.circle_outlined,
          fillLabel: columns,
        );
        final measured = _Reading(
          label: actualLabel ?? s.pressureGuideActual,
          value: actual,
          color: colors.tertiary,
          valueKey: '$keyPrefix-actual',
          unit: unit,
          icon: Icons.diamond_outlined,
          fillLabel: columns,
        );
        if (!columns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [reference, const SizedBox(height: 12), measured],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: reference),
              const SizedBox(width: 16),
              Expanded(child: measured),
            ],
          ),
        );
      },
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({
    required this.label,
    required this.value,
    required this.color,
    required this.valueKey,
    required this.unit,
    required this.icon,
    required this.fillLabel,
  });
  final String label;
  final String value;
  final Color color;
  final String valueKey;
  final String unit;
  final IconData icon;
  final bool fillLabel;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fillLabel) Expanded(child: heading) else heading,
        Text(
          value,
          key: ValueKey(valueKey),
          style: AppTheme.figures(Theme.of(context).textTheme.displayLarge)
              .copyWith(color: color),
        ),
        Text(
          unit,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: color),
        ),
      ],
    );
  }
}
