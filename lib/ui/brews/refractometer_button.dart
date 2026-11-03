import 'package:flutter/material.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// Asks the refractometer to measure; the result fills the TDS when it
/// arrives. Spins while a measurement is under way.
class RefractometerButton extends StatelessWidget {
  const RefractometerButton({super.key, required this.refractometer});

  final Refractometer refractometer;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return IconButton(
      key: const ValueKey('refractometer-measure'),
      tooltip: refractometer.measuring
          ? s.refractometerMeasuring
          : s.refractometerMeasure,
      onPressed: refractometer.measuring ? null : refractometer.measure,
      icon: refractometer.measuring
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.colorize_outlined),
    );
  }
}
