import 'package:flutter/material.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/profiles/profile_plot.dart';

/// The saved extraction curve, if the brew has one.
class BrewCurveSection extends StatelessWidget {
  const BrewCurveSection({
    super.key,
    required this.curve,
    required this.espresso,
    this.firstDripMs,
    this.onSaveProfile,
  });

  final bool espresso;

  final Future<({ShotCurve curve, String source})?> curve;
  final int? firstDripMs;
  final Future<void> Function(ShotCurve)? onSaveProfile;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({ShotCurve curve, String source})?>(
        future: curve,
        builder: (context, snapshot) => switch (snapshot.data) {
          (:final curve, :final source) => Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    AppLocalizations.of(context).extractionCurve,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (onSaveProfile != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => onSaveProfile!(curve),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(AppLocalizations.of(context).profileFromShot),
                    ),
                  ),
                const SizedBox(height: 6),
                ExtractionChart(
                  curve: curve,
                  firstDripMs: firstDripMs,
                  showFlowStatistics: espresso,
                  // Scales, and BeanConqueror, weigh the flow.
                  flowUnit: source == ImportOperations.meticulousSource
                      ? 'ml/s'
                      : 'g/s',
                ),
              ],
            ),
          ),
          null => const SizedBox.shrink(),
        },
      );
}

class BrewProfileSnapshot extends StatelessWidget {
  const BrewProfileSnapshot({super.key, required this.source});
  final String source;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    try {
      final profile = ExtractionProfile.decode(source);
      return ExpansionTile(
        title: Text(s.profileReference),
        subtitle: Text(profile.name),
        children: [ProfilePlot(profile: profile)],
      );
    } on FormatException {
      return Text(s.profileError);
    }
  }
}
