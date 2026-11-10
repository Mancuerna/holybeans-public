import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/espresso_chart.dart';
import 'package:holybeans/domain/share_brew_charts.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/espresso_map_page.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/brews/sensory_map_page.dart';
import 'package:holybeans/ui/core/share_photo_overlay.dart';

BrewShareChartData brewShareChartData(
  Brew brew,
  BrewMethod? method,
  ({ShotCurve curve, String source})? recording,
) => BrewShareChartData(
  doseGrams: brew.doseGrams,
  beverageGrams: brew.beverageGrams,
  tdsPercent: brew.tdsPercent,
  methodName: method?.name ?? brew.methodName,
  category: method?.category,
  recording: recording,
);

class ShareChartOptions extends StatelessWidget {
  const ShareChartOptions({
    super.key,
    required this.data,
    required this.curveSelected,
    required this.mapSelected,
    required this.onCurveChanged,
    required this.onMapChanged,
    this.enabled = true,
  });

  final BrewShareChartData data;
  final bool curveSelected;
  final bool mapSelected;
  final ValueChanged<bool> onCurveChanged;
  final ValueChanged<bool> onMapChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      children: [
        CheckboxListTile(
          key: const ValueKey('share-include-curve'),
          contentPadding: EdgeInsets.zero,
          title: Text(s.shareIncludeCurve),
          subtitle: Text(
            data.hasCurve ? s.shareCurveHint : s.shareCurveUnavailable,
          ),
          value: curveSelected && data.hasCurve,
          onChanged: enabled && data.hasCurve
              ? (on) => onCurveChanged(on!)
              : null,
        ),
        CheckboxListTile(
          key: const ValueKey('share-include-map'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            data.espresso
                ? s.shareIncludeEspressoMap
                : s.shareIncludeSensoryMap,
          ),
          subtitle: data.hasMap ? null : Text(s.shareMapUnavailable),
          value: mapSelected && data.hasMap,
          onChanged: enabled && data.hasMap ? (on) => onMapChanged(on!) : null,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class BrewShareCharts extends StatelessWidget {
  const BrewShareCharts({
    super.key,
    required this.data,
    required this.includeCurve,
    required this.includeMap,
    this.panelBackgroundOpacity,
  });

  final BrewShareChartData data;
  final bool includeCurve;
  final bool includeMap;
  final double? panelBackgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final title = Theme.of(context).textTheme.titleMedium;
    final curve = includeCurve && data.hasCurve;
    final map = includeMap && data.hasMap;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (curve)
          _section(
            key: const ValueKey('share-curve-panel'),
            children: [
              Text(s.extractionCurve, style: title),
              const SizedBox(height: 8),
              ExtractionChart(
                key: const ValueKey('share-extraction-chart'),
                curve: data.recording!.curve,
                interactive: false,
                replayable: false,
                showReadout: false,
                flowUnit:
                    data.recording!.source == ImportOperations.meticulousSource
                    ? 'ml/s'
                    : 'g/s',
              ),
            ],
          ),
        if (curve && map && panelBackgroundOpacity != null)
          const SizedBox(height: 12),
        if (map)
          _section(
            key: const ValueKey('share-map-panel'),
            children: [
              Text(data.espresso ? s.espressoMap : s.sensoryMap, style: title),
              const SizedBox(height: 12),
              if (data.espresso)
                EspressoMapChart(
                  eyPercent: data.ey!,
                  tdsPercent: data.tdsPercent!,
                  ratio: data.ratio!,
                  style: EspressoStyle.forRatio(data.ratio!),
                )
              else ...[
                SensoryMapChart(
                  eyPercent: data.ey!,
                  tdsPercent: data.tdsPercent!,
                ),
                const SizedBox(height: 8),
                Text(
                  s.shareSensorySource,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _section({required Key key, required List<Widget> children}) {
    final opacity = panelBackgroundOpacity;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [if (opacity == null) const Divider(height: 28), ...children],
    );
    if (opacity == null) return content;
    return ShareOverlayPanel(
      key: key,
      backgroundOpacity: opacity,
      child: Padding(padding: const EdgeInsets.all(16), child: content),
    );
  }
}
