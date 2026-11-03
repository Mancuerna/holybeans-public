typedef CafeStatsDrink = ({
  String cafeId,
  double? rating,
  int? priceCents,
  String currency,
});

class CafeStats {
  CafeStats(Iterable<CafeStatsDrink> drinks) {
    final venues = <String>{};
    var ratings = 0;
    var totalRating = 0.0;
    for (final d in drinks) {
      count++;
      venues.add(d.cafeId);
      if (d.rating case final r? when r.isFinite && r >= 0 && r <= 10) {
        ratings++;
        totalRating += r;
      }
      if (d.priceCents case final cents? when cents >= 0) {
        spending.update(d.currency, (n) => n + cents, ifAbsent: () => cents);
      }
    }
    cafeCount = venues.length;
    averageRating = ratings == 0 ? null : totalRating / ratings;
  }
  int count = 0;
  late final int cafeCount;
  late final double? averageRating;
  final spending = <String, int>{};
}
