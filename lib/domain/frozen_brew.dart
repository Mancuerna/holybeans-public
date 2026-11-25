/// Coffee to thaw when a new brew is saved, never when its form is opened.
class FrozenBrewSource {
  const FrozenBrewSource({
    required this.portionId,
    required this.lotId,
    required this.grams,
  });

  final String portionId;
  final String lotId;
  final double grams;
}

/// Explicit replacement for an edited brew. A null portion uses available coffee.
typedef BrewDoseSource = ({String? portionId});

/// Where deleting or archiving a brew returns its recorded dose.
class BrewStockReturn {
  const BrewStockReturn({
    required this.availableGrams,
    this.frozenGrams = 0,
    this.portionLabel,
  });

  final double availableGrams;
  final double frozenGrams;
  final String? portionLabel;
}
