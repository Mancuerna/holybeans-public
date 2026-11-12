import 'package:flutter/material.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:intl/intl.dart' show NumberFormat;

class ProfileGuideSummary extends StatelessWidget {
  const ProfileGuideSummary({
    super.key,
    required this.profile,
    required this.elapsedMs,
    this.flowActual,
    this.pressureActual,
  });
  final ExtractionProfile profile;
  final int elapsedMs;
  final double? flowActual;
  final double? pressureActual;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final n = NumberFormat('0.0', Localizations.localeOf(context).toString());
    String value(double? v) => v == null ? '—' : n.format(v);
    Widget cell(String text, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: Text(text, style: style),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1.2),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                cell(s.pressureGuideTarget),
                cell(s.curveFlowCurrent),
              ],
            ),
            for (final flow in [
              profile.primary == 'flow',
              profile.primary != 'flow',
            ])
              TableRow(
                children: [
                  cell(
                    '${flow ? s.curveFlow : s.curvePressure}\n${flow ? 'g/s' : 'bar'}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: flow ? colors.primary : colors.tertiary,
                    ),
                  ),
                  cell(
                    value(
                      profile.targetAt(
                        flow ? profile.flow : profile.pressure,
                        elapsedMs,
                      ),
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  cell(
                    value(flow ? flowActual : pressureActual),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${s.pressureGuideAhead}: ${value(profile.targetAt(profile.flow, elapsedMs + 2000))} g/s · ${value(profile.targetAt(profile.pressure, elapsedMs + 2000))} bar',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
