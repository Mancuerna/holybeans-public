import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_ratio.dart';

export 'package:holybeans/domain/brew_ratio.dart';

/// [extractionYieldPercent] of a saved brew.
double? brewExtractionYield(Brew brew) => extractionYieldPercent(
  doseGrams: brew.doseGrams,
  beverageGrams: brew.beverageGrams,
  tdsPercent: brew.tdsPercent,
);
