import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/repositories/brew_stats.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/optional_rating_slider.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

/// The rating chosen when archiving a coffee, possibly none.
class CoffeeArchiveDecision {
  const CoffeeArchiveDecision(this.rating);

  final double? rating;
}

/// Confirms archiving a coffee and offers a final rating, starting from the
/// average of its brews when they were rated.
class CoffeeArchiveDialog extends StatefulWidget {
  const CoffeeArchiveDialog({
    super.key,
    required this.coffeeName,
    required this.initialRating,
    required this.afterOverdraw,
    this.brewRatings = const [],
    this.reason,
  });

  final String coffeeName;
  final double? initialRating;
  final bool afterOverdraw;
  final String? reason;

  /// Ratings of this coffee's brews, offered as a starting point.
  final List<double> brewRatings;

  @override
  State<CoffeeArchiveDialog> createState() => _CoffeeArchiveDialogState();
}

class _CoffeeArchiveDialogState extends State<CoffeeArchiveDialog> {
  late double? rating = widget.initialRating;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('coffee-archive-dialog'),
      title: Text(s.archiveBeanTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.coffeeName),
            const SizedBox(height: 8),
            Text(
              widget.reason ??
                  (widget.afterOverdraw
                      ? s.archiveBeanForOverdraw
                      : s.archiveBeanDescription),
            ),
            if (widget.brewRatings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final average = meanRating(widget.brewRatings)!;
                  // Ratings move in half points.
                  final rounded = (average * 2).round() / 2;
                  return Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        s.averageBrewRating(
                          formatDecimal(
                            average,
                            pattern: '0.#',
                            locale: regionalLocale.toString(),
                          ),
                          widget.brewRatings.length,
                        ),
                        key: const ValueKey('archive-average-rating'),
                      ),
                      TextButton.icon(
                        key: const ValueKey('archive-use-average'),
                        onPressed: () => setState(() => rating = rounded),
                        icon: const Icon(Icons.download_rounded),
                        label: Text(s.useAverageRating),
                      ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            OptionalRatingSlider(
              value: rating,
              onChanged: (value) => setState(() => rating = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, CoffeeArchiveDecision(rating)),
          child: Text(s.archiveBean),
        ),
      ],
    );
  }
}
