import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// Blooms and pours found on the brew's curve, offered to be saved when
/// none are recorded.
class BrewPoursFromCurve extends StatelessWidget {
  const BrewPoursFromCurve({
    super.key,
    required this.curve,
    required this.brew,
    required this.onSave,
    this.error,
  });

  final Future<({ShotCurve curve, String source})?> curve;
  final Brew brew;
  final Future<void> Function(BrewPours pours) onSave;
  final String? error;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({ShotCurve curve, String source})?>(
        future: curve,
        builder: (context, snapshot) {
          final found = switch (snapshot.data) {
            (:final curve, source: _) => brewPoursFromCurve(
              curve,
              doseGrams: brew.doseGrams,
              bloomCount: brew.bloomCount,
              pourCount: brew.pourCount,
            ),
            null => null,
          };
          if (found == null) return const SizedBox.shrink();
          final s = AppLocalizations.of(context);
          final colors = Theme.of(context).colorScheme;
          return Card(
            key: const ValueKey('brew-detail-pours-from-curve'),
            margin: const EdgeInsets.only(top: 12),
            color: colors.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_graph_rounded,
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        s.curveShowsPours(
                          found.bloomCount ?? 0,
                          found.pourCount ?? 0,
                        ),
                        ?error,
                      ].join('\n'),
                      style: TextStyle(
                        color: error == null
                            ? colors.onSecondaryContainer
                            : colors.error,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('brew-detail-pours-save'),
                    onPressed: () => onSave(found),
                    child: Text(s.save),
                  ),
                ],
              ),
            ),
          );
        },
      );
}
