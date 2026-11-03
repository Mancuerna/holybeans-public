/// The espresso extraction map: extraction yield against TDS, with a target
/// box per style and diagonal lines of equal brew ratio (TDS = EY ÷ ratio).
/// The filter sensory map does not apply to espresso, whose TDS is several
/// times higher.
library;

/// Espresso styles by strength. All share an 18–22 % extraction target.
enum EspressoStyle {
  ristretto(minTds: 12, maxTds: 18),
  normale(minTds: 8, maxTds: 12),
  lungo(minTds: 5, maxTds: 8);

  const EspressoStyle({required this.minTds, required this.maxTds});

  static const double minEy = 18;
  static const double maxEy = 22;

  final double minTds;
  final double maxTds;

  /// The axes: the target box plus its own width on each side, so the box
  /// sits in the middle third whatever the style.
  ({double min, double max}) get eyAxis =>
      (min: minEy - (maxEy - minEy), max: maxEy + (maxEy - minEy));
  ({double min, double max}) get tdsAxis =>
      (min: minTds - (maxTds - minTds), max: maxTds + (maxTds - minTds));

  /// Suggests a style from the beverage-to-dose [ratio].
  ///
  /// Ristretto is below 1:2, normale starts at 1:2, and lungo starts at 1:3.
  /// These recipe conventions are independent of the TDS target boxes.
  static EspressoStyle forRatio(double ratio) {
    if (ratio < 2) return ristretto;
    if (ratio < 3) return normale;
    return lungo;
  }
}

/// Where a value falls against a range.
enum RangePosition { low, within, high }

RangePosition _position(double value, double min, double max) => value < min
    ? RangePosition.low
    : value > max
    ? RangePosition.high
    : RangePosition.within;

/// How a shot compares with [style]'s target, without judging its taste.
({RangePosition ey, RangePosition tds}) espressoPosition({
  required EspressoStyle style,
  required double eyPercent,
  required double tdsPercent,
}) => (
  ey: _position(eyPercent, EspressoStyle.minEy, EspressoStyle.maxEy),
  tds: _position(tdsPercent, style.minTds, style.maxTds),
);

/// Brew ratios drawn as lines, as 1:n.
const espressoRatioLines = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0];
